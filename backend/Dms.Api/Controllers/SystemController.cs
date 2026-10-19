using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Dms.Api.Ops;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SystemController(
    AppDbContext db,
    ILogger<SystemController> logger,
    IMaintenanceState maintenance,
    ISystemControl system,
    IAuditService audit,
    ICurrentUser current,
    IPasswordHasher hasher,
    AppPaths paths) : ControllerBase
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
    /// Hint: التفاصيل التقنية الكاملة (commit، وقت البناء، والمهاجرات) محصورة بالسوبر أدمن وحده،
    ///       بينما تعرض الواجهة لبقية الأدوار (رئيس/مدير/موظف/قارئ) رقم الإصدار فقط.
    /// </summary>
    [HttpGet("about")]
    [Authorize(Roles = "SuperAdmin")]
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

    /// <summary>
    /// قائمة الجداول التي يُعاد تصفير عدّاد الترقيم التلقائي (IDENTITY) لها إلى الصفر عند تصفير القاعدة.
    /// </summary>
    public static IReadOnlyList<string> TablesToReseedZero => AppDbContext.TablesToReseedZero;

    /// <summary>
    /// تصفير قاعدة البيانات بالكامل ومسح جميع البيانات والمرفقات للبدء من الصفر — **للسوبر أدمن حصراً**.
    /// Hint: يتحقّق أولاً من كلمة التأكيد «تصفير» ومن كلمة مرور السوبر أدمن الفعلية عبر IPasswordHasher.Verify.
    /// Hint: يحذف جميع الجداول داخل معاملة واحدة (Transaction) مرتّبة حسب المفاتيح الأجنبية بدلاً من DROP DATABASE،
    ///       مع الإبقاء على حساب السوبر أدمن الحالي وحده دون غيره حتى لا يُقفل المالك خارج النظام أبداً.
    /// </summary>
    [HttpPost("reset-db")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ResetDb([FromBody] ResetDatabaseRequest req, CancellationToken ct)
    {
        // Hint: فحص مزدوج لصلاحية السوبر أدمن (فوق [Authorize(Roles = "SuperAdmin")]) لضمان الأمان 100%.
        if (!current.IsSuperAdmin || current.UserId is not { } superAdminId)
            throw new ForbiddenException("هذا الإجراء مخصّص للسوبر أدمن حصراً.");

        if (req is null || !string.Equals(req.Confirmation?.Trim(), "تصفير", StringComparison.Ordinal))
            throw new ValidationException("يرجى كتابة كلمة التأكيد «تصفير» بشكل صحيح.");

        if (string.IsNullOrWhiteSpace(req.Password))
            throw new ValidationException("كلمة مرور السوبر أدمن مطلوبة للتأكيد.");

        var superUser = await db.Users.IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.UserId == superAdminId && u.Role == UserRole.SuperAdmin && u.IsActive, ct)
            ?? throw new ForbiddenException("حساب السوبر أدمن غير صالح.");

        // Hint: نرمي ValidationException (400) عند خطأ كلمة المرور بدلاً من Unauthorized (401)
        //       لئلا يظنّ عميل الواجهة أن جلسة JWT انتهت فيُخرج السوبر أدمن من الشاشة قبل أن يصحّح الكلمة.
        if (!hasher.Verify(req.Password, superUser.PasswordHash))
            throw new ValidationException("كلمة مرور السوبر أدمن غير صحيحة.");

        var none = CancellationToken.None;
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(none);

            // 1) فكّ المراجع الذاتية والمراجع الاختيارية المتقاطعة قبل الحذف لتجنّب تعارض المفاتيح الأجنبية (Restrict/NoAction)
            await db.DmsTasks.IgnoreQueryFilters()
                .ExecuteUpdateAsync(s => s
                    .SetProperty(t => t.ParentRecurringTaskId, (int?)null)
                    .SetProperty(t => t.RelatedIncomingId, (int?)null)
                    .SetProperty(t => t.RelatedOutgoingId, (int?)null), none);

            await db.PayrollPeriods.IgnoreQueryFilters()
                .ExecuteUpdateAsync(s => s.SetProperty(p => p.OutgoingBookId, (int?)null), none);

            await db.OutgoingBooks.IgnoreQueryFilters()
                .ExecuteUpdateAsync(s => s.SetProperty(b => b.CaseFileId, (int?)null), none);

            await db.IncomingBooks.IgnoreQueryFilters()
                .ExecuteUpdateAsync(s => s.SetProperty(b => b.CaseFileId, (int?)null), none);

            // Hint: فكّ ارتباط حساب السوبر أدمن بأي شركة أو صورة قبل حذف الشركات والملفات
            await db.Users.IgnoreQueryFilters()
                .Where(u => u.UserId == superAdminId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(u => u.CompanyId, (int?)null)
                    .SetProperty(u => u.PhotoBlobKey, (string?)null)
                    .SetProperty(u => u.FailedLoginCount, 0)
                    .SetProperty(u => u.LockedUntil, (DateTime?)null), none);

            // 2) حذف الجداول الفرعية والمرفقات والإشعارات والمهام
            await db.Attachments.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.DocumentVersions.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.ClientRequests.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Notifications.IgnoreQueryFilters().ExecuteDeleteAsync(none);

            await db.DmsTaskUpdates.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.DmsTaskParticipants.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.DmsTasks.IgnoreQueryFilters().ExecuteDeleteAsync(none);

            // 3) حذف حركات الكتب والردود والإحالات
            await db.BookReplies.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.OutgoingMovements.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.MovementLogs.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Set<IncomingAssignment>().IgnoreQueryFilters().ExecuteDeleteAsync(none);

            // 4) حذف بيانات الموارد البشرية والرواتب والإجازات والموظفين
            await db.EmployeeLeaveSettlements.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.PayrollEntries.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.PayrollPeriods.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.EmployeeLeaves.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.EmployeeLogs.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.EmployeeCompanies.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Employees.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.HrSettings.IgnoreQueryFilters().ExecuteDeleteAsync(none);

            // 5) حذف الكتب الصادرة والواردة والأرشيف والمعاملات
            await db.OutgoingBooks.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.IncomingBooks.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.ArchiveDocs.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.CaseFiles.IgnoreQueryFilters().ExecuteDeleteAsync(none);

            // 6) حذف التفويضات وإسنادات الشركات ورموز الدخول وجميع المستخدمين عدا السوبر أدمن الحالي
            await db.ApprovalDelegations.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.UserCompanies.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.RefreshTokens.IgnoreQueryFilters().Where(r => r.UserId != superAdminId).ExecuteDeleteAsync(none);
            await db.Users.IgnoreQueryFilters().Where(u => u.UserId != superAdminId).ExecuteDeleteAsync(none);

            // 7) حذف القوالب وأنواع الكتب والجهات والأقسام والعدّادات وأسعار الصرف والشركات وسجلّ التدقيق
            await db.Templates.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.OutgoingBookTypes.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.DocumentTypes.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Entities.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Departments.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Counters.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.ExchangeRates.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.Companies.IgnoreQueryFilters().ExecuteDeleteAsync(none);
            await db.AuditLogs.IgnoreQueryFilters().ExecuteDeleteAsync(none);

            // 8) تصفير عدّادات الترقيم التلقائي (IDENTITY) في SQL Server لتبدأ الجداول الجديدة من الرقم 1
            // Hint:
            //   1. جدول إحالات الوارد اسمه الفعلي في القاعدة [IncomingAssignment] بالمفرد (وليس بالجمع).
            //   2. في SQL Server، إذا لم يُدرج في الجدول أيّ صفّ من قبل تكون (last_value IS NULL) في sys.identity_columns؛
            //      واستدعاء RESEED, 0 على جدول بـ last_value = NULL يجعل أوّل صفّ جديد يأخذ الرقم 0 بدل 1!
            //      لذلك نفحص (last_value IS NOT NULL) قبل تنفيذ DBCC CHECKIDENT ليبدأ أوّل صفّ دائماً من 1.
            if (db.Database.IsSqlServer())
            {
                foreach (var tbl in TablesToReseedZero)
                {
                    var target = $"[{tbl}]";
                    await db.Database.ExecuteSqlAsync(
                        $"IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID({target}, 'U') AND last_value IS NOT NULL) DBCC CHECKIDENT ({target}, RESEED, 0);",
                        none);
                }
                await db.Database.ExecuteSqlAsync(
                    $"IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('[Users]', 'U') AND last_value IS NOT NULL) BEGIN DECLARE @maxUser int = ISNULL((SELECT MAX(UserId) FROM [Users]), 0); DBCC CHECKIDENT ('[Users]', RESEED, @maxUser); END",
                    none);
                await db.Database.ExecuteSqlAsync(
                    $"IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('[RefreshTokens]', 'U') AND last_value IS NOT NULL) BEGIN DECLARE @maxRt int = ISNULL((SELECT MAX(RefreshTokenId) FROM [RefreshTokens]), 0); DBCC CHECKIDENT ('[RefreshTokens]', RESEED, @maxRt); END",
                    none);
            }

            audit.Add("SystemReset", SystemControlWatcher.SystemAuditEntity, null,
                "تصفير قاعدة البيانات بالكامل للبدء من الصفر");
            await db.SaveChangesAsync(none);

            await tx.CommitAsync(none);
        });

        // 9) مسح جميع الملفات المرفوعة والمولّدة داخل StorageRoot (مع عدم المساس بمجلد النسخ الاحتياطية BackupDir)
        if (Directory.Exists(paths.StorageRoot))
        {
            try
            {
                foreach (var file in Directory.GetFiles(paths.StorageRoot))
                {
                    try { System.IO.File.Delete(file); } catch { /* أفضل جهد */ }
                }
                foreach (var dir in Directory.GetDirectories(paths.StorageRoot))
                {
                    try { Directory.Delete(dir, recursive: true); } catch { /* أفضل جهد */ }
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "تعذّر مسح بعض ملفات التخزين أثناء تصفير النظام.");
            }
        }

        logger.LogWarning("تم تصفير قاعدة البيانات بالكامل بواسطة السوبر أدمن '{User}' (ID={Id}).", superUser.Username, superAdminId);
        return Ok(new { message = "تم تصفير قاعدة البيانات بالكامل بنجاح." });
    }
}
