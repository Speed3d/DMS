using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Companies;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public sealed class CompaniesController(
    AppDbContext db, IAuditService audit, IFileStorage storage,
    ICurrentUser currentUser, ICompanyDeletionService deletion, IBackgroundJobs jobs) : ControllerBase
{
    /// <summary>شركاتي — **النشِطة وحدها افتراضاً** (ADR-047).</summary>
    /// <remarks>
    /// 🔴 **الافتراض «النشِطة فقط» لا «الكل»** — لأن أكثر قارئٍ لهذه النقطة هو **مُبدّل
    /// الشركات**، والشركة المعطَّلة يجب ألّا تظهر فيه. وشاشةُ الإعدادات وحدها تطلب
    /// <c>includeInactive=true</c> لتُظهرها رماديةً مع زرّ إعادة التفعيل.
    ///
    /// ⚠️ **ومقصورٌ على السوبر أدمن** — فغيرُه لا يملك إدارة الشركات أصلاً، وإظهارُها له
    /// يعني اسمَ شركةٍ لا يستطيع دخولها ولا تفعيلها.
    /// </remarks>
    [HttpGet]
    public async Task<ActionResult<List<CompanyResponse>>> List(
        [FromQuery] bool includeInactive = false, CancellationToken ct = default)
    {
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!includeInactive || !currentUser.IsSuperAdmin) q = q.Where(c => c.IsActive);
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        return await q.OrderBy(c => c.Name)
            .Select(c => new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey))
            .ToListAsync(ct);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CompanyResponse>> Get(int id, CancellationToken ct)
    {
        // متسق مع List/Update: غير السوبر أدمن يرى أي شركة مسموحة له (لا الشركة النشطة فقط).
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
    public async Task<ActionResult<CompanyResponse>> Create(CompanyRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || string.IsNullOrWhiteSpace(req.Prefix))
            throw new ValidationException("الاسم والرمز مطلوبان.");
        if (await db.Companies.IgnoreQueryFilters().AnyAsync(c => c.Prefix == req.Prefix, ct))
            throw new ConflictException("رمز الترقيم مستخدم بالفعل.");

        var c = new Company
        {
            Name = req.Name.Trim(),
            Prefix = req.Prefix.Trim().ToUpperInvariant(),
            IsActive = req.IsActive,
            DefaultSignatoryName = req.DefaultSignatoryName,
            DefaultSignatoryTitle = req.DefaultSignatoryTitle,
            CreatedAt = DateTime.UtcNow,
        };
        db.Companies.Add(c);
        audit.Add("Create", nameof(Company), null, $"إنشاء شركة {c.Name}", null);
        await db.SaveChangesAsync(ct);

        // بذر أنواع المستندات الافتراضية — **بعد** الحفظ لأن `CompanyId` يُولَّد هناك.
        // Hint: بدونها تبدأ الشركة بقائمة أنواع فارغة، فيجد المستخدم الحقل معطّلاً في نموذج
        //       الوارد ولا يعرف أنه يُملأ من الإعدادات. نقطة انطلاق يعدّلها كما يشاء.
        db.DocumentTypes.AddRange(DefaultDocumentTypes.For(c.CompanyId));
        await db.SaveChangesAsync(ct);

        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President")]
    [RequireModule(AppModule.Settings)]
    public async Task<ActionResult<CompanyResponse>> Update(int id, CompanyRequest req, CancellationToken ct)
    {
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        if (await db.Companies.IgnoreQueryFilters().AnyAsync(x => x.Prefix == req.Prefix && x.CompanyId != id, ct))
            throw new ConflictException("رمز الترقيم مستخدم بالفعل.");

        // 🔴 **تعطيلٌ يُقفل مستخدماً خارج النظام يُرفض** (ADR-047): التعطيل يُخرج الشركة
        //    من الرمز، فمن لا يملك غيرها يصير بلا شركةٍ فعّالة — **فلا يرى شيئاً ولا يفهم
        //    لماذا**. والقاعدة في `Dms.Domain/CompanyLifecycle.cs` وحدها.
        if (c.IsActive && !req.IsActive)
        {
            var sole = await deletion.SoleCompanyUsersAsync(id, ct);
            var block = CompanyLifecycle.CanDeactivate(sole);
            if (block != CompanyBlockReason.None)
                throw new ConflictException(CompanyLifecycle.Explain(
                    block, c.Name, EmptyContents with { SoleCompanyUsers = sole }));
        }

        c.Name = req.Name.Trim();
        c.Prefix = req.Prefix.Trim().ToUpperInvariant();
        c.IsActive = req.IsActive;
        c.DefaultSignatoryName = req.DefaultSignatoryName;
        c.DefaultSignatoryTitle = req.DefaultSignatoryTitle;
        audit.Add("Update", nameof(Company), id.ToString(), null, id);
        await db.SaveChangesAsync(ct);
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
    }

    [HttpPost("{id:int}/logo")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    [RequireModule(AppModule.Settings)]
    public async Task<IActionResult> UploadLogo(int id, IFormFile file, CancellationToken ct)
    {
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");

        var allowedTypes = new[] { "image/png", "image/jpeg" };
        if (!allowedTypes.Contains(file.ContentType.ToLowerInvariant()))
            throw new ValidationException("يُسمح فقط بملفات PNG و JPG.");
        if (file.Length > 2 * 1024 * 1024)
            throw new ValidationException("حجم الصورة يجب ألا يتجاوز 2 ميغابايت.");

        if (!string.IsNullOrEmpty(c.LogoImageKey))
            await storage.DeleteAsync(c.LogoImageKey, ct);

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var key = await storage.SaveAsync($"company_{id}_logo_{Guid.NewGuid():N}.img", ms.ToArray(), ct);

        c.LogoImageKey = key;
        audit.Add("UploadLogo", nameof(Company), id.ToString(), null, id);
        await db.SaveChangesAsync(ct);

        return Ok();
    }

    // ═════════════ دورة حياة الشركة: التعطيل ثم الحذف (ADR-047) ═════════════

    private static readonly CompanyContents EmptyContents = new(0,0,0,0,0,0,0,0,0,0,0,0,0);

    /// <summary>**بيانُ ما سيُحذف** — يُقرأ قبل الحذف ويُعرض للمالك (ADR-047).</summary>
    /// <remarks>
    /// 🔑 **«لا تحذف ما لا تراه».** حوارُ تحذيرٍ عامّ بلا أرقام يجعل الموافقة بلا معنى —
    /// وهو بعينه ما جعل زرّ تصفير القاعدة يُضغط بالخطأ.
    ///
    /// ⚠️ **ويُمرَّر الاسمُ نفسه تأكيداً** عمداً: الغرض إظهار **الموانع الحقيقية** (لم
    /// تُعطَّل · فيها سجلّات · …) لا التذكير بأن المستخدم لم يكتب شيئاً بعد.
    /// </remarks>
    [HttpGet("{id:int}/delete-preview")]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
    public async Task<ActionResult<CompanyDeletePreviewResponse>> DeletePreview(int id, CancellationToken ct)
    {
        var check = await deletion.CheckDeletionAsync(id, confirm: null, ct);
        var (c, contents) = (check.Company, check.Contents);
        // ⚠️ **التأكيد لا يُفحص في البيان** (يُفحص أخيراً فلا يحجب مانعاً قبله): الغرض الموانع
        //    الحقيقية لا التذكير بأن المستخدم لم يكتب الاسم بعد.
        var block = check.Block == CompanyBlockReason.BadConfirmation ? CompanyBlockReason.None : check.Block;

        return new CompanyDeletePreviewResponse(
            c.CompanyId, c.Name, c.Prefix, c.IsActive,
            contents.LiveOutgoing, contents.DeletedOutgoing,
            contents.LiveIncoming, contents.DeletedIncoming,
            contents.Archive, contents.Employees, contents.Tasks, contents.CaseFiles,
            contents.Users, contents.SoleCompanyUsers,
            contents.Departments, contents.Entities, contents.Templates,
            contents.WillBeErased,
            block == CompanyBlockReason.None,
            block.ToString(),
            block == CompanyBlockReason.None
                ? null
                : CompanyLifecycle.Explain(block, c.Name, contents),
            contents.DeletedArchive, contents.DeletedTasks, contents.DeletedCaseFiles, contents.DeletedEmployees,
            contents.DeletedRecords);
    }

    /// <summary>
    /// حذف جذريّ للشركة — **معطَّلةً · بلا سجلٍّ حيّ · بتأكيدٍ بالاسم · وبنسخةٍ قبله** (ADR-047).
    /// </summary>
    /// <remarks>
    /// 🔴 **أربع طبقاتٍ لا زرّ واحد**، وكلُّها وُلدت من حادثةٍ وقعت 2026-09-21:
    /// <list type="number">
    /// <item><b>لا تُحذف إلا معطَّلة</b> — خطوتان لا واحدة، فلا تقع بضغطةٍ خاطئة.</item>
    /// <item><b>لا سجلَّ حيّاً فيها</b> — والمحذوفُ ناعماً **لا يمنع** (قرار المالك).</item>
    /// <item><b>تأكيدٌ بكتابة الاسم</b> — نمط الاستعادة، لا زرٌّ أحمر.</item>
    /// <item>🔴 <b>نسخةٌ احتياطية قبل الحذف</b> — والفشل فيها <b>يوقف الحذف</b>.</item>
    /// </list>
    ///
    /// ⚠️ **وفشلُ النسخة يُوقف العملية عمداً**: النسخة **هي** شبكة الأمان، والمضيُّ بلا
    /// شبكةٍ يجعل الطبقة الرابعة **وعداً لا حارساً**.
    ///
    /// ⚙️ **ويجري في الخلفية** (2026-09-23) — النسخة الكاملة قبله تتجاوز ~100 ثانية مع بياناتٍ
    /// حقيقية، فيقطعها Cloudflare ومهلة الواجهة (30 ثانية) قبله. **يردّ 202 برقم العملية**.
    /// </remarks>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
    public async Task<IActionResult> Delete(int id, [FromQuery] string? confirm, CancellationToken ct)
    {
        // ⚠️ **الفحص قبل البدء** — المنع يعود 409 فوراً كما كان، لا فشلاً في شاشة المتابعة.
        await deletion.EnsureDeletableAsync(id, confirm, ct);
        var job = jobs.Start("delete-company", "حذف شركة", currentUser, async (sp, progress, stop) =>
        {
            await sp.GetRequiredService<ICompanyDeletionService>().DeleteAsync(id, confirm, stop, progress);
            return null;
        });
        return Accepted(JobResponse.From(job));
    }

    [HttpGet("{id:int}/logo")]
    [AllowAnonymous]
    public async Task<IActionResult> GetLogo(int id, CancellationToken ct)
    {
        var c = await db.Companies.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.CompanyId == id, ct);
        if (c == null || string.IsNullOrEmpty(c.LogoImageKey))
            return NotFound();

        var bytes = await storage.ReadAsync(c.LogoImageKey, ct);
        if (bytes == null || bytes.Length == 0) return NotFound();

        return File(bytes, "image/png");
    }
}
