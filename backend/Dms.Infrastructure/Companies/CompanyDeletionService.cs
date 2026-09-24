using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Backup;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Companies;

/// <summary>بيانُ ما سيُحذف مع الشركة وسببُ المنع إن وُجد.</summary>
public sealed record CompanyDeletionCheck(Company Company, CompanyContents Contents, CompanyBlockReason Block);

/// <summary>
/// دورة حياة الشركة في الخادم — **بيانُ الحذف · فحصُه · وتنفيذُه** (ADR-047).
/// </summary>
/// <remarks>
/// 🔄 **انتقل من وحدة التحكّم إلى هنا** (2026-09-23) لسببين: الحذف صار **عمليةً خلفية** (يأخذ
/// نسخةً كاملة قبله، وخلف Cloudflare يُقطع كلُّ طلبٍ يتجاوز ~100 ثانية) فيحتاج أن يجري في
/// **نطاقه الخاصّ** بعد انتهاء الطلب — ومنطقُ العمل مكانُه البنية التحتية لا وحدة التحكّم
/// (<c>rules/architecture.md</c>). **والقواعد نفسها لم تتغيّر بحرف** — ما زالت في
/// <c>Dms.Domain/CompanyLifecycle.cs</c>.
/// </remarks>
public interface ICompanyDeletionService
{
    /// <summary>مَن تكون هذه الشركة إسنادَه الوحيد — عدا السوبر أدمن.</summary>
    Task<int> SoleCompanyUsersAsync(int id, CancellationToken ct = default);

    /// <summary>البيان وسببُ المنع — <paramref name="confirm"/> يُقارَن باسم الشركة.</summary>
    Task<CompanyDeletionCheck> CheckDeletionAsync(int id, string? confirm, CancellationToken ct = default);

    /// <summary>يرمي <see cref="ConflictException"/> بالسبب إن لم يجز الحذف — قبل بدء العملية.</summary>
    Task EnsureDeletableAsync(int id, string? confirm, CancellationToken ct = default);

    /// <summary>الحذف الجذريّ: نسخةٌ احتياطية أوّلاً ثم محوُ كل ما يخصّ الشركة.</summary>
    Task DeleteAsync(int id, string? confirm, CancellationToken ct = default, IJobProgress? progress = null);
}

public sealed class CompanyDeletionService(
    AppDbContext db, IAuditService audit, IFileStorage storage,
    ICurrentUser current, IBackupService backups) : ICompanyDeletionService
{

    private async Task<Company> FindAnyAsync(int id, CancellationToken ct) =>
        await db.Companies.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.CompanyId == id, ct)
        ?? throw new NotFoundException("الشركة غير موجودة.");

    /// <summary>مَن تكون هذه الشركة إسنادَه الوحيد — **عدا السوبر أدمن**.</summary>
    /// <remarks>
    /// ⚠️ **السوبر أدمن مستثنى عمداً**: هو بلا فلتر شركة أصلاً (`AppDbContext`)، فيبقى
    /// يرى كل شيء ولو لم يُسنَد لشركةٍ واحدة — وعدُّه هنا كان **يمنع تعطيل أيّ شركةٍ
    /// أُسند إليها وحدها**، وهي الحالة الشائعة في نظامٍ صغير.
    /// </remarks>
    public async Task<int> SoleCompanyUsersAsync(int id, CancellationToken ct) =>
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

    private async Task<(Company c, CompanyContents contents, CompanyBlockReason block)> CheckAsync(
        int id, string? confirm, CancellationToken ct)
    {
        var c = await FindAnyAsync(id, ct);
        var contents = await ContentsAsync(id, ct);
        var isLast = await db.Companies.IgnoreQueryFilters().CountAsync(ct) <= 1;
        var block = CompanyLifecycle.CanDelete(
            c.IsActive, current.ActiveCompanyId == id, isLast, contents, c.Name, confirm);
        return (c, contents, block);
    }

    public async Task<CompanyDeletionCheck> CheckDeletionAsync(int id, string? confirm, CancellationToken ct = default)
    {
        var (c, contents, block) = await CheckAsync(id, confirm, ct);
        return new CompanyDeletionCheck(c, contents, block);
    }

    public async Task EnsureDeletableAsync(int id, string? confirm, CancellationToken ct = default)
    {
        var (c, contents, block) = await CheckAsync(id, confirm, ct);
        if (block != CompanyBlockReason.None)
            throw new ConflictException(CompanyLifecycle.Explain(block, c.Name, contents));
    }

    public async Task DeleteAsync(int id, string? confirm, CancellationToken ct = default, IJobProgress? progress = null)
    {
        // 🔴 **يُعاد الفحص هنا** ولو فُحص قبل البدء: بين الضغط والتنفيذ قد يُضاف سجلّ.
        progress?.Report("التحقّق من إمكان الحذف");
        var (c, contents, block) = await CheckAsync(id, confirm, ct);
        if (block != CompanyBlockReason.None)
            throw new ConflictException(CompanyLifecycle.Explain(block, c.Name, contents));

        // 🔴 شبكة الأمان **قبل** أيّ حذف — وفشلُها يُلغي العملية.
        // 🔴 **وفشلُ النسخة لا يرمي دائماً** — `RunAsync` يعيد سجلّاً بحالة `Failed` حين يفشل
        //    الضغط أو نسخ القاعدة (عيبٌ كان قائماً، كُشف عند نقل هذا الكود 2026-09-23): فكان
        //    الحذف **يمضي بلا نسخة** والرسالة تَعِد بعكسه. الحالة تُفحص صراحةً الآن.
        string? backupFailure = null;
        try
        {
            var rec = await backups.RunAsync(BackupType.Manual, BackupScope.Full, RetentionCategory.Manual, ct, progress);
            if (rec.Status != BackupStatus.Success) backupFailure = rec.Note ?? "سببٌ غير معروف";
        }
        catch (Exception ex)
        {
            backupFailure = ex.Message;
        }
        if (backupFailure is not null)
            throw new ConflictException(
                "تعذّر أخذ نسخةٍ احتياطية قبل الحذف، فأُلغيت العملية. " +
                $"عالج سبب النسخ ثم أعِد المحاولة. ({backupFailure})");

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
        // ⚠️ **ومن هنا بلا إلغاء**: المعاملة تتراجع كلُّها إن فشلت، لكنّ قطعَها بإيقاف الخدمة
        //    بين الحفظ وتنظيف الملفات يترك ملفاتٍ بلا مالك — فتكتمل ما دامت بدأت.
        progress?.Report("حذف بيانات الشركة");
        ct = CancellationToken.None;
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

            // مفاتيح منع التكرار (ADR-051) — بلا مفتاحٍ أجنبيّ فلا تمنع الحذف، لكن لا يُترك يتيم.
            await db.ClientRequests.IgnoreQueryFilters().Where(x => x.CompanyId == id).ExecuteDeleteAsync(ct);

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

        progress?.Succeed($"حُذفت «{c.Name}» — مُحي {contents.WillBeErased} سجلّاً، وأُخذت نسخةٌ احتياطية قبل الحذف.");
    }
}
