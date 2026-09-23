using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Backup;
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
    ICurrentUser currentUser, IBackupService backups) : ControllerBase
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
            var sole = await SoleCompanyUsersAsync(id, ct);
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

    private async Task<Company> FindAnyAsync(int id, CancellationToken ct) =>
        await db.Companies.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.CompanyId == id, ct)
        ?? throw new NotFoundException("الشركة غير موجودة.");

    /// <summary>مَن تكون هذه الشركة إسنادَه الوحيد — **عدا السوبر أدمن**.</summary>
    /// <remarks>
    /// ⚠️ **السوبر أدمن مستثنى عمداً**: هو بلا فلتر شركة أصلاً (`AppDbContext`)، فيبقى
    /// يرى كل شيء ولو لم يُسنَد لشركةٍ واحدة — وعدُّه هنا كان **يمنع تعطيل أيّ شركةٍ
    /// أُسند إليها وحدها**، وهي الحالة الشائعة في نظامٍ صغير.
    /// </remarks>
    private async Task<int> SoleCompanyUsersAsync(int id, CancellationToken ct) =>
        await db.Users.IgnoreQueryFilters()
            .Where(u => u.IsActive && u.Role != UserRole.SuperAdmin
                        && u.AssignedCompanies.Any(a => a.CompanyId == id)
                        && u.AssignedCompanies.Count == 1)
            .CountAsync(ct);

    /// <summary>بيانُ ما تحويه الشركة — **يفصل الحيّ عن المحذوف ناعماً**.</summary>
    /// <remarks>
    /// 🔴 **هذا الفصل هو أصل العطل الذي بلّغ عنه المالك**: الحارس القديم كان يعدّ
    /// بـ<c>IgnoreQueryFilters()</c> **بلا <c>!IsDeleted</c>**، فكتابٌ حذفه المالك بنفسه
    /// يبقى يمنع حذف الجهة والشركة معاً — **ورسالةٌ تقول «1 صادر» وهو لا يرى كتاباً واحداً**.
    /// </remarks>
    private async Task<CompanyContents> ContentsAsync(int id, CancellationToken ct) => new(
        LiveOutgoing:     await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        DeletedOutgoing:  await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && x.IsDeleted, ct),
        LiveIncoming:     await db.IncomingBooks.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        DeletedIncoming:  await db.IncomingBooks.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && x.IsDeleted, ct),
        Archive:          await db.ArchiveDocs.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        Employees:        await db.EmployeeCompanies.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        Tasks:            await db.DmsTasks.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        CaseFiles:        await db.CaseFiles.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id && !x.IsDeleted, ct),
        Users:            await db.UserCompanies.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id, ct),
        SoleCompanyUsers: await SoleCompanyUsersAsync(id, ct),
        Departments:      await db.Departments.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id, ct),
        Entities:         await db.Entities.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id, ct),
        Templates:        await db.Templates.IgnoreQueryFilters().CountAsync(x => x.CompanyId == id, ct));

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
        var c = await FindAnyAsync(id, ct);
        var contents = await ContentsAsync(id, ct);
        var isLast = await db.Companies.IgnoreQueryFilters().CountAsync(ct) <= 1;

        var block = CompanyLifecycle.CanDelete(
            c.IsActive, currentUser.ActiveCompanyId == id, isLast, contents, c.Name, c.Name);

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
                : CompanyLifecycle.Explain(block, c.Name, contents));
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
    /// </remarks>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
    public async Task<IActionResult> Delete(int id, [FromQuery] string? confirm, CancellationToken ct)
    {
        var c = await FindAnyAsync(id, ct);
        var contents = await ContentsAsync(id, ct);
        var isLast = await db.Companies.IgnoreQueryFilters().CountAsync(ct) <= 1;

        var block = CompanyLifecycle.CanDelete(
            c.IsActive, currentUser.ActiveCompanyId == id, isLast, contents, c.Name, confirm);
        if (block != CompanyBlockReason.None)
            throw new ConflictException(CompanyLifecycle.Explain(block, c.Name, contents));

        // 🔴 شبكة الأمان **قبل** أيّ حذف — وفشلُها يُلغي العملية.
        try
        {
            await backups.RunAsync(BackupType.Manual, BackupScope.Full, RetentionCategory.Manual, ct);
        }
        catch (Exception ex)
        {
            throw new ConflictException(
                "تعذّر أخذ نسخةٍ احتياطية قبل الحذف، فأُلغيت العملية. " +
                $"عالج سبب النسخ ثم أعِد المحاولة. ({ex.Message})");
        }

        // اجمع مفاتيح التخزين قبل الحذف لتنظيفها بعد نجاح المعاملة.
        var blobKeys = new List<string>();
        if (!string.IsNullOrEmpty(c.LogoImageKey)) blobKeys.Add(c.LogoImageKey);

        var templateKeys = await db.Templates.IgnoreQueryFilters().Where(t => t.CompanyId == id)
            .Select(t => new { t.HeaderImageKey, t.FooterImageKey, t.WatermarkImageKey }).ToListAsync(ct);
        foreach (var t in templateKeys)
        {
            if (!string.IsNullOrEmpty(t.HeaderImageKey)) blobKeys.Add(t.HeaderImageKey);
            if (!string.IsNullOrEmpty(t.FooterImageKey)) blobKeys.Add(t.FooterImageKey);
            if (!string.IsNullOrEmpty(t.WatermarkImageKey)) blobKeys.Add(t.WatermarkImageKey);
        }

        var bookIds = await db.OutgoingBooks.IgnoreQueryFilters().Where(b => b.CompanyId == id)
            .Select(b => b.OutgoingId).ToListAsync(ct);
        blobKeys.AddRange(await db.OutgoingBooks.IgnoreQueryFilters()
            .Where(b => b.CompanyId == id && b.GeneratedPdfBlobKey != null)
            .Select(b => b.GeneratedPdfBlobKey!).ToListAsync(ct));
        blobKeys.AddRange(await db.Attachments
            .Where(a => a.OwnerType == OwnerType.Outgoing && bookIds.Contains(a.OwnerId))
            .Select(a => a.BlobKey).ToListAsync(ct));

        // 🔴 **وما بقي محذوفاً ناعماً من الوحدات الأخرى يُمحى معها** (مراجعة 2026-09-23).
        //    الحارس لا يعدّ المحذوف ناعماً فيسمح بالحذف — وكان الحذف لا يمسّه:
        //    · **مهمةٌ محذوفة ناعماً تُفشل الحذف كلَّه بـ500** — لها مفتاحٌ أجنبيّ نحو الشركة
        //      (`FK_DmsTasks_Companies_CompanyId`)، **بعد** أخذ نسخةٍ كاملة.
        //    · والأرشيف المحذوف والأقسام وكشوف الرواتب وإعدادات الوحدة **تبقى يتيمةً** تشير
        //      إلى شركةٍ لا وجود لها — وملفاتُ مرفقاتها على القرص بلا مالك.
        //    ⚠️ **وما لا يُمسّ عمداً**: سجلّ التدقيق (شاهدٌ لا يُمحى) · والموظف نفسه (كيانٌ عابرٌ
        //    للشركات، يُحذف إسنادُه لهذه الشركة وحده) · ومستمسكاتُه (تخصّه لا الشركة).
        var incomingIds = await db.IncomingBooks.IgnoreQueryFilters().Where(b => b.CompanyId == id)
            .Select(b => b.IncomingId).ToListAsync(ct);
        var archiveIds = await db.ArchiveDocs.IgnoreQueryFilters().Where(a => a.CompanyId == id)
            .Select(a => a.ArchiveId).ToListAsync(ct);
        var taskIds = await db.DmsTasks.IgnoreQueryFilters().Where(t => t.CompanyId == id)
            .Select(t => t.TaskId).ToListAsync(ct);
        var entryIds = await db.PayrollEntries.IgnoreQueryFilters().Where(e => e.CompanyId == id)
            .Select(e => e.EntryId).ToListAsync(ct);
        var periodIds = await db.PayrollPeriods.IgnoreQueryFilters().Where(p => p.CompanyId == id)
            .Select(p => p.PeriodId).ToListAsync(ct);

        IQueryable<Attachment> OwnedAttachments() => db.Attachments.Where(a =>
            (a.OwnerType == OwnerType.Incoming && incomingIds.Contains(a.OwnerId)) ||
            (a.OwnerType == OwnerType.Archive && archiveIds.Contains(a.OwnerId)) ||
            (a.OwnerType == OwnerType.Task && taskIds.Contains(a.OwnerId)) ||
            (a.OwnerType == OwnerType.PayrollEntry && entryIds.Contains(a.OwnerId)));
        blobKeys.AddRange(await OwnedAttachments().Select(a => a.BlobKey).ToListAsync(ct));

        // العملية كوحدة قابلة لإعادة المحاولة (ADR-008 — EnableRetryOnFailure مُفعّل).
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            // ── أوّلاً ما يمنع حذف الشركة أو ما يعتمد على ما سيُحذف بعده ──
            // ⚠️ `ExecuteDelete` يُنفَّذ فوراً **داخل المعاملة** — فإن فشل ما بعده تراجع كلُّه.
            await OwnedAttachments().ExecuteDeleteAsync(ct);
            await db.DocumentVersions
                .Where(v => v.DocType == OwnerType.PayrollPeriod && periodIds.Contains(v.DocId))
                .ExecuteDeleteAsync(ct);

            // المهام: يُفكّ رابط «الأمّ المتكرّرة» أولاً (مفتاحٌ ذاتيّ بلا تعاقب)، ثم تُحذف
            // فتتعاقب سجلّاتُها ومشاركوها في القاعدة.
            await db.DmsTasks.IgnoreQueryFilters()
                .Where(t => t.CompanyId == id && t.ParentRecurringTaskId != null)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.ParentRecurringTaskId, (int?)null), ct);
            await db.DmsTasks.IgnoreQueryFilters().Where(t => t.CompanyId == id).ExecuteDeleteAsync(ct);

            await db.ArchiveDocs.IgnoreQueryFilters().Where(a => a.CompanyId == id).ExecuteDeleteAsync(ct);

            // الرواتب: الكشوف (وسطورها بالتعاقب) قبل الإسنادات لأن السطر يمنع حذف إسناده.
            await db.EmployeeLeaveSettlements.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.PayrollPeriods.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.PayrollEntries.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.EmployeeLeaves.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.EmployeeLogs.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.EmployeeCompanies.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);
            await db.HrSettings.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);

            db.Attachments.RemoveRange(db.Attachments.Where(a => a.OwnerType == OwnerType.Outgoing && bookIds.Contains(a.OwnerId)));
            db.DocumentVersions.RemoveRange(db.DocumentVersions.Where(v => v.DocType == OwnerType.Outgoing && bookIds.Contains(v.DocId)));
            db.OutgoingBooks.RemoveRange(db.OutgoingBooks.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            // 🔴 **جدولا ADR-045 يُنظَّفان صراحةً**: `BookReply` يتعاقب مع الكتب، لكن
            //    `CaseFile` مرتبطٌ بها بـ`SetNull` — فحذفُ الكتب يترك **معاملاتٍ يتيمة**.
            db.BookReplies.RemoveRange(db.BookReplies.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.CaseFiles.RemoveRange(db.CaseFiles.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.MovementLogs.RemoveRange(db.MovementLogs.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.IncomingBooks.RemoveRange(db.IncomingBooks.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            // 🔴 **والإشعارات معها** (ADR-046): لها `CompanyId`، وتركُها يُخلّف صفوفاً تشير
            //    إلى شركةٍ لا وجود لها — تظهر في «شركاتك الأخرى» باسمٍ «—» بلا معنى.
            db.Notifications.RemoveRange(db.Notifications.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.UserCompanies.RemoveRange(db.UserCompanies.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.ApprovalDelegations.RemoveRange(db.ApprovalDelegations.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Templates.RemoveRange(db.Templates.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Entities.RemoveRange(db.Entities.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.DocumentTypes.RemoveRange(db.DocumentTypes.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Counters.RemoveRange(db.Counters.Where(x => x.CompanyId == id));

            // فكّ ربط المستخدمين الذين شركتهم الرئيسية هي هذه الشركة.
            var primaryUsers = await db.Users.IgnoreQueryFilters().Where(u => u.CompanyId == id).ToListAsync(ct);
            foreach (var u in primaryUsers) u.CompanyId = null;

            db.Companies.Remove(c);
            audit.Add("Delete", nameof(Company), id.ToString(),
                $"حذف الشركة «{c.Name}» بعد تعطيلها — مُحي {contents.WillBeErased} سجلّاً", null);
            await db.SaveChangesAsync(ct);

            // الأقسام **بعد** الوارد والإسنادات: الإحالة تمنع حذف قسمها، والوارد (وإحالاتُه
            // بالتعاقب) حُذف في الحفظ أعلاه.
            await db.Departments.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);

            await tx.CommitAsync(ct);
        });

        // تنظيف التخزين بعد ثبات الـ DB (فشل حذف ملف مفقود لا يُفشل العملية).
        foreach (var key in blobKeys.Distinct())
        {
            try { await storage.DeleteAsync(key, ct); }
            catch { /* تجاهل — الملف قد يكون محذوفاً مسبقاً */ }
        }

        return NoContent();
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
