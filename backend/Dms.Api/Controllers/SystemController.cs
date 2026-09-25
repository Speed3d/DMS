using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Dms.Api.Ops;
using Dms.Api.Seeding;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SystemController(AppDbContext db, IServiceProvider services, IConfiguration config, IWebHostEnvironment env, ILogger<SystemController> logger, IMaintenanceState maintenance, ISystemControl system, IAuditService audit, ICurrentUser current) : ControllerBase
{
    /// <summary>
    /// حالة النظام — مسموح بلا مصادقة ليعرف العميل متى يكون النظام قيد الصيانة (أثناء استعادة نسخة)
    /// أو موقوفاً للصيانة (ADR-050). تستطلعها الواجهة كل 30 ثانية.
    /// Hint: هذا المسار مستثنى من MaintenanceMiddleware وLockdownMiddleware، فيبقى مجيباً دائماً.
    /// </summary>
    /// <remarks>
    /// 🔐 **الشريط للمصادَق وحده** — نصّه قد يكون داخلياً، والنقطة مفتوحةٌ للعالم عبر الدومين.
    /// أما رسالة الإيقاف فعامّة **عمداً**: تظهر على شاشة الدخول قبل أن يكتب أحدٌ كلمة مروره.
    /// </remarks>
    [HttpGet("status")]
    [AllowAnonymous]
    public SystemStatusResponse Status()
    {
        var isSuper = current.IsAuthenticated && current.IsSuperAdmin;
        var a = system.Announcement;
        return new SystemStatusResponse(
            maintenance.IsActive, maintenance.Reason, maintenance.SinceUtc,
            ToDto(system.Lockdown, withActor: isSuper),
            current.IsAuthenticated && a.Visible ? ToDto(a) : null,
            current.IsAuthenticated ? BuildInfo.Current.Display : null);
    }

    /// <summary>
    /// «حول النظام» — الإصدار والـcommit ولحظة البناء وآخر مهاجرة (ADR-054).
    /// </summary>
    /// <remarks>
    /// ⚠️ **آخر مهاجرةٍ في الكود مقابل آخر ما طُبّق على القاعدة** — اختلافُهما يعني تحديثاً لم يكتمل
    /// (والطبيعيّ أن يتساويا: الإقلاع يطبّق المهاجرات). 🔐 للمصادَق وحده، والقراءة خفيفة (لا تُستطلع).
    /// </remarks>
    [HttpGet("about")]
    [Authorize]
    public async Task<SystemAboutResponse> About(CancellationToken ct)
    {
        var all = db.Database.GetMigrations().ToList();
        var applied = (await db.Database.GetAppliedMigrationsAsync(ct)).ToList();
        var v = BuildInfo.Current;
        return new SystemAboutResponse(
            v.Display, v.ShortCommit, BuildInfo.BuiltAtUtc,
            all.LastOrDefault(), applied.LastOrDefault(), applied.Count);
    }

    // ───────────── إيقاف النظام وشريط الإعلان (ADR-050) — للسوبر أدمن وحده ─────────────

    /// <summary>لوحة التحكّم: الإيقاف والشريط والنصوص المحفوظة.</summary>
    [HttpGet("control")]
    [Authorize(Roles = "SuperAdmin")]
    public SystemControlResponse Control() => ControlView();

    /// <summary>يوقف النظام عن كل المستخدمين عدا السوبر أدمن، أو يشغّله. الرسالة **مطلوبة** عند الإيقاف.</summary>
    /// <remarks>
    /// ⚠️ **لا يعود النظام للعمل وحده أبداً** (قرار المالك) — لا مهلةَ ولا موعد؛ التشغيلُ بهذه النقطة
    /// أو بأمر الطوارئ على السيرفر فقط.
    /// </remarks>
    [HttpPut("lockdown")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<SystemControlResponse> SetLockdown(SetLockdownRequest req, CancellationToken ct)
    {
        var before = system.Lockdown;
        var name = await ActorNameAsync(ct);
        var after = system.SetLockdown(req.Active, req.Message, current.UserId, name);

        if (before.Active != after.Active || before.Message != after.Message)
        {
            audit.Add(after.Active ? "SystemLockdownOn" : "SystemLockdownOff",
                SystemControlWatcher.SystemAuditEntity, null, after.Active ? after.Message : null);
            await db.SaveChangesAsync(ct);
        }
        return ControlView();
    }

    /// <summary>يُظهر شريط الإعلان للجميع أو يُخفيه. النصّ **مطلوب** عند الإظهار.</summary>
    [HttpPut("announcement")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<SystemControlResponse> SetAnnouncement(SetAnnouncementRequest req, CancellationToken ct)
    {
        var before = system.Announcement;
        var after = system.SetAnnouncement(req.Visible, req.Text, req.Kind);

        var action = (before.Visible, after.Visible) switch
        {
            (false, true) => "AnnouncementShown",
            (true, false) => "AnnouncementHidden",
            (true, true) when before.Text != after.Text || before.Kind != after.Kind => "AnnouncementChanged",
            _ => null,
        };
        if (action is not null)
        {
            audit.Add(action, SystemControlWatcher.SystemAuditEntity, null,
                after.Visible ? $"[{after.Kind}] {after.Text}" : null);
            await db.SaveChangesAsync(ct);
        }
        return ControlView();
    }

    /// <summary>يحفظ نصّاً لاستعماله لاحقاً (نصوص الإيقاف منفصلةٌ عن نصوص الشريط).</summary>
    [HttpPost("saved-texts")]
    [Authorize(Roles = "SuperAdmin")]
    public SystemControlResponse AddSavedText(SavedTextRequest req)
    {
        system.AddSavedText(req.Kind, req.Text);
        return ControlView();
    }

    /// <summary>يحذف نصّاً محفوظاً.</summary>
    [HttpDelete("saved-texts")]
    [Authorize(Roles = "SuperAdmin")]
    public SystemControlResponse RemoveSavedText([FromQuery] SavedTextKind kind, [FromQuery] string text)
    {
        if (!system.RemoveSavedText(kind, text))
            throw new NotFoundException("النصّ غير موجود في المحفوظات.");
        return ControlView();
    }

    private SystemControlResponse ControlView() => new(
        ToDto(system.Lockdown, withActor: true), ToDto(system.Announcement),
        system.SavedTexts(SavedTextKind.Lockdown), system.SavedTexts(SavedTextKind.Announcement));

    private static LockdownDto ToDto(LockdownState l, bool withActor)
        => new(l.Active, l.Message, l.SinceUtc, withActor ? l.ByName : null);

    private static AnnouncementDto ToDto(AnnouncementState a)
        => new(a.Visible, a.Text, a.Kind, a.UpdatedAtUtc);

    /// <summary>اسم الفاعل لعرضه في لوحة التحكّم («أوقفه فلان»).</summary>
    /// <remarks>⚠️ `IgnoreQueryFilters` قراءةٌ لاسم الطالب نفسه — السوبر أدمن غير مُسنَد لشركة فيُحجب بالفلتر.</remarks>
    private async Task<string?> ActorNameAsync(CancellationToken ct)
        => current.UserId is { } id
            ? await db.Users.IgnoreQueryFilters().Where(u => u.UserId == id).Select(u => u.FullName).FirstOrDefaultAsync(ct)
            : null;

    /// <summary>حالة عمليةٍ طويلة بدأت في الخلفية (نسخ · مرآة · استعادة · حذف شركة).</summary>
    /// <remarks>
    /// ⚠️ **أثناء الاستعادة تردّ 503 كبقيّة النقاط** (وضع الصيانة يسبق المصادقة) — والواجهة
    /// تسأل حينها <c>/api/system/status</c> العامّة وحدها حتى تعود. **وهذا مقصود**: لو سُمح
    /// بها وانتهت صلاحية الرمز لحاول العميل التجديد، والتجديد مرفوضٌ في الصيانة، **فيُخرج
    /// المستخدم من النظام في منتصف الاستعادة**.
    /// 🔐 **للسوبر أدمن وحده** — مَن يملك بدء هذه العمليات أصلاً.
    /// </remarks>
    [HttpGet("jobs/{id:guid}")]
    [Authorize(Roles = "SuperAdmin")]
    public ActionResult<JobResponse> Job(Guid id, [FromServices] IBackgroundJobs jobs)
        => jobs.Get(id) is { } j
            ? JobResponse.From(j)
            : throw new NotFoundException(
                "العملية غير معروفة — ربما أُعيد تشغيل الخادم أثناءها. تحقّق من النتيجة ثم أعد المحاولة إن لزم.");

    /// <summary>العملية الطويلة الجارية الآن — لتستأنف الشاشة متابعتها بعد إعادة التحميل (204 إن لم توجد).</summary>
    [HttpGet("jobs/current")]
    [Authorize(Roles = "SuperAdmin")]
    public IActionResult CurrentJob([FromServices] IBackgroundJobs jobs)
        => jobs.Current is { } j ? Ok(JobResponse.From(j)) : NoContent();

    [HttpPost("reset-db")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ResetDb()
    {
        // عملية تدميرية شاملة — متاحة في بيئة التطوير فقط (لا يجوز مسح قاعدة الإنتاج عبر الـ API).
        if (!env.IsDevelopment())
            throw new ForbiddenException("تصفير قاعدة البيانات غير متاح في بيئة الإنتاج.");

        await db.Database.EnsureDeletedAsync();
        await DbSeeder.MigrateAndSeedAsync(services, config, logger);
        return Ok(new { message = "تم تصفير قاعدة البيانات بنجاح." });
    }
}
