using Dms.Domain;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Archive;

public sealed record CreateArchiveInput(
    int? CompanyId, string Title, string? BookNumber, DateTime? BookDate,
    int? FromEntityId, int? ToEntityId, int? DocumentTypeId,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate,
    string? Keywords, string? Notes, string? BodyHtml,
    int? DepartmentId = null);

public sealed record UpdateArchiveInput(
    string Title, string? BookNumber, DateTime? BookDate,
    int? FromEntityId, int? ToEntityId, int? DocumentTypeId,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate,
    string? Keywords, string? Notes, string? BodyHtml,
    int? DepartmentId = null);

public sealed record ArchiveSearchInput(
    string? Text, DateTime? From, DateTime? To, int? DocumentTypeId, int? EntityId);

/// <summary>مرشِّحات «عدسة الأرشيف» (ADR-021) — تخدم الشاشة والتقرير معاً.</summary>
/// <param name="Source">`Incoming` أو `Paper` أو فارغ = الاثنان.</param>
public sealed record ArchiveLensFilter(
    string? Search = null, int? Year = null, int? Month = null,
    int? DepartmentId = null, string? Source = null);

/// <summary>صفٌّ في عدسة الأرشيف — مصدرُه وارداً مؤرشفاً أو أضبارةً ورقية.</summary>
/// <param name="IsIncoming">`true` للوارد المؤرشف، `false` للأضبارة الورقية.</param>
/// <param name="AmountInIqd">للأضابير وحدها — الوارد لا يدخل الحساب المالي (قرار 2026-07-25).</param>
public sealed record ArchiveLensRow(
    bool IsIncoming, int Id, string Number, string Title,
    DateTime ArchivedAt, int Year, int Month,
    string? EntityName, string? DocumentTypeName,
    List<string> Departments, string? Notes, decimal? AmountInIqd);

public interface IArchiveService
{
    /// <summary>
    /// قاعدة رؤية الأرشيف — **مُعلَنة ليستدعيها غيرُها بدل أن ينسخها** (ADR-030).
    /// </summary>
    /// <remarks>
    /// 🔴 كان التقرير المالي يكتب نسخةً **أضيق** منها (المُنشئ وحده)، فيقرأ موظفُ القسم
    /// أضبارةً على الشاشة ولا يجدها في تقريره. نظيرُ `IOutgoingService.Query()` و
    /// `IIncomingService.Query()` — وثلاثتها الآن مُعلَنة لأن **كل نسخةٍ ثانية تتباعد**.
    /// </remarks>
    IQueryable<ArchiveDoc> Query();

    /// <summary>
    /// **عدسة الأرشيف** (ADR-021): الوارد المؤرشف + الأضابير الورقية في قائمةٍ واحدة.
    /// </summary>
    /// <remarks>
    /// 🔴 **نُقلت من `ArchiveController` إلى هنا (2026-08-11)** حين احتاجها **التقرير التفصيلي**.
    /// والبديل — نسخُها في التقرير — هو بعينه العطل الذي أُغلق قبل يومٍ واحد: تقريرٌ يجمع غيرَ
    /// ما تعرضه الشاشة (ADR-030). **دالّةٌ واحدة تخدم الاثنين، فلا تتباعد قاعدتان.**
    ///
    /// 🔐 **والحدّ المزدوج محفوظ داخلها:** صفوف الوارد المؤرشف **تتطلّب قسم «الوارد» أيضاً**،
    /// وإلا صار الأرشيف باباً خلفياً لقراءة وارد محجوب. والرؤية تُبنى على `IncomingService.Query()`
    /// نفسها لا بإعادة كتابة الشرط.
    /// </remarks>
    Task<List<ArchiveLensRow>> LensAsync(ArchiveLensFilter filter, CancellationToken ct = default);

    Task<List<ArchiveDoc>> SearchAsync(ArchiveSearchInput filter, CancellationToken ct = default);
    Task<ArchiveDoc> GetAsync(int id, CancellationToken ct = default);
    Task<ArchiveDoc> CreateAsync(CreateArchiveInput input, CancellationToken ct = default);
    Task<ArchiveDoc> UpdateAsync(int id, UpdateArchiveInput input, CancellationToken ct = default);
    Task SoftDeleteAsync(int id, CancellationToken ct = default);
}

public sealed class ArchiveService(
    AppDbContext db, ICurrentUser current, INumberingService numbering, IAuditService audit,
    IIncomingService incoming) : IArchiveService
{
    private const string CounterType = "Archive";

    /// <inheritdoc />
    public async Task<List<ArchiveLensRow>> LensAsync(ArchiveLensFilter f, CancellationToken ct = default)
    {
        var items = new List<ArchiveLensRow>();
        var search = f.Search;

        var wantIncoming = !string.Equals(f.Source, "Paper", StringComparison.OrdinalIgnoreCase);
        var wantPaper = !string.Equals(f.Source, "Incoming", StringComparison.OrdinalIgnoreCase);

        // ---- المصدر الأول: الوارد المؤرشف ----
        // 🔐 يتطلّب قسم الوارد **أيضاً** — بدونه يصير الأرشيف باباً خلفياً لقراءة وارد محجوب.
        if (wantIncoming && current.HasModule(AppModule.Incoming))
        {
            var q = incoming.Query()
                .Where(b => b.Status == IncomingStatus.Archived)
                .Include(b => b.Entity)
                .Include(b => b.Assignments).ThenInclude(a => a.Department)
                .AsQueryable();

            if (!string.IsNullOrWhiteSpace(search))
                q = q.Where(b => (b.IncomingNumber != null && b.IncomingNumber.Contains(search))
                                 || b.Subject.Contains(search)
                                 || (b.Keywords != null && b.Keywords.Contains(search)));

            if (f.DepartmentId.HasValue)
                q = q.Where(b => b.Assignments.Any(a => a.DepartmentId == f.DepartmentId.Value));

            var books = await q.ToListAsync(ct);
            var typeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

            items.AddRange(books.Select(b =>
            {
                // Hint: `UpdatedAt` هو تاريخ الأرشفة فعلياً — التعديل ممنوع بعدها، فآخر
                //       تحديث للكتاب هو لحظة أرشفته. فلا حاجة لعمود جديد ولا مهاجرة.
                var archivedAt = b.UpdatedAt ?? b.CreatedAt;
                return new ArchiveLensRow(
                    true, b.IncomingId, b.IncomingNumber ?? "—", b.Subject,
                    archivedAt, archivedAt.Year, archivedAt.Month,
                    b.Entity?.Name,
                    b.DocumentTypeId is not null && typeNames.TryGetValue(b.DocumentTypeId.Value, out var tn) ? tn : null,
                    b.Assignments.Select(a => a.Department?.Name ?? "—").ToList(),
                    b.Notes,
                    // 🔴 **الوارد بلا مبلغ عمداً**: أُلغي من الحساب المالي (قرار المالك
                    //    2026-07-25) لأنه يُسجَّل للمتابعة لا للمحاسبة. وإدراجه هنا كان
                    //    سيُضخّم إجمالي التقرير التفصيلي بلا معنى.
                    null);
            }));
        }

        // ---- المصدر الثاني: الأضابير الورقية القديمة ----
        if (wantPaper)
        {
            var docs = await SearchAsync(new ArchiveSearchInput(search, null, null, null, null), ct);
            var docTypeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

            items.AddRange(docs
                .Where(a => !f.DepartmentId.HasValue || a.DepartmentId == f.DepartmentId.Value)
                .Select(a =>
                {
                    // تاريخ الكتاب الأصلي أدقّ للأضبارة القديمة من تاريخ إدخالها في النظام.
                    var at = a.BookDate ?? a.CreatedAt;
                    return new ArchiveLensRow(
                        false, a.ArchiveId, a.ArchiveNumber, a.Title,
                        at, at.Year, at.Month, null,
                        a.DocumentTypeId is not null && docTypeNames.TryGetValue(a.DocumentTypeId.Value, out var tn) ? tn : null,
                        a.Department?.Name is null ? [] : [a.Department.Name],
                        a.Notes, a.AmountInIqd);
                }));
        }

        // Hint: الفلترة بالسنة/الشهر بعد الدمج لا قبله — المصدران يشتقّان تاريخهما من
        //       حقلين مختلفين (`UpdatedAt` للوارد و`BookDate` للأضبارة)، فتوحيدهما هنا
        //       يضمن أن «شهر ٥» يعني الشيء نفسه في الجهتين.
        if (f.Year.HasValue) items = items.Where(i => i.Year == f.Year.Value).ToList();
        if (f.Month.HasValue) items = items.Where(i => i.Month == f.Month.Value).ToList();

        return items.OrderByDescending(i => i.ArchivedAt).ToList();
    }

    /// <summary>
    /// رؤية الأضابير الورقية — **على قاعدة رؤية الوارد نفسها** (قرار المالك 2026-07-28).
    /// </summary>
    /// <remarks>
    /// الموظف/القارئ يرى: ما أنشأه هو **+ أضابير قسمه**. المدير فأعلى يرى كل شيء.
    ///
    /// ⚠️ كانت القاعدة «ما أنشأه هو **فقط**» — مختلفة كلياً عن الوارد، ونتيجتها أن أضبارة
    /// يُدخلها موظف تصير **قبراً**: لا يراها زميله في القسم نفسه ولا من يخلفه في وظيفته.
    /// والأرشيف ذاكرةُ الشركة لا ملكيةَ مُدخِله.
    ///
    /// وأضبارة **بلا قسم** تبقى للمنشئ والمدير فأعلى — لا تتسرّب، ولا تختفي عمّن أدخلها.
    /// </remarks>
    public IQueryable<ArchiveDoc> Query()
    {
        var q = db.ArchiveDocs.AsQueryable();
        // ⚠️ نفس صلاحية «يرى كل الوارد» تشمل الأرشيف (قرار المالك: علَمٌ واحد للاثنين —
        //    فصلُهما يُنتج مصفوفة صلاحيات لا يتذكّرها أحد).
        if (current.Role is UserRole.Employee or UserRole.Reader && !current.CanViewAllIncoming)
        {
            var uid = current.UserId;
            var dept = current.DepartmentId;
            q = q.Where(a => a.CreatedByUserId == uid
                             || (dept != null && a.DepartmentId == dept));
        }
        return q;
    }

    public async Task<List<ArchiveDoc>> SearchAsync(ArchiveSearchInput f, CancellationToken ct = default)
    {
        var q = Query();
        if (!string.IsNullOrWhiteSpace(f.Text))
            q = q.Where(a => a.Title.Contains(f.Text)
                || (a.Keywords != null && a.Keywords.Contains(f.Text))
                || (a.BookNumber != null && a.BookNumber.Contains(f.Text))
                || a.ArchiveNumber.Contains(f.Text));
        if (f.From is not null)
            q = q.Where(a => (a.BookDate ?? a.CreatedAt) >= f.From);
        if (f.To is not null)
            q = q.Where(a => (a.BookDate ?? a.CreatedAt) <= f.To);
        if (f.DocumentTypeId is not null)
            q = q.Where(a => a.DocumentTypeId == f.DocumentTypeId);
        if (f.EntityId is not null)
            q = q.Where(a => a.FromEntityId == f.EntityId || a.ToEntityId == f.EntityId);
        return await q.Include(a => a.Department).OrderByDescending(a => a.CreatedAt).ToListAsync(ct);
    }

    public async Task<ArchiveDoc> GetAsync(int id, CancellationToken ct = default)
        => await Query().FirstOrDefaultAsync(a => a.ArchiveId == id, ct)
           ?? throw new NotFoundException("المستند غير موجود أو لا تملك صلاحية رؤيته.");

    public async Task<ArchiveDoc> CreateAsync(CreateArchiveInput input, CancellationToken ct = default)
    {
        RequireNotReader();
        var companyId = ResolveCompanyId(input.CompanyId);
        if (string.IsNullOrWhiteSpace(input.Title)) throw new ValidationException("العنوان مطلوب.");
        await ValidateRefsAsync(companyId, input.FromEntityId, input.ToEntityId, input.DocumentTypeId, ct);
        var amountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);

        var company = await db.Companies.FirstOrDefaultAsync(c => c.CompanyId == companyId, ct)
                      ?? throw new NotFoundException("الشركة غير موجودة.");

        ArchiveDoc doc = null!;
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var year = DateTime.UtcNow.Year;
            var serial = await numbering.NextSerialAsync(companyId, year, CounterType, ct);

            doc = new ArchiveDoc
            {
                CompanyId = companyId,
                ArchiveNumber = $"{company.Prefix}-AR-{year}-{serial:D5}",
                Title = input.Title.Trim(),
                BookNumber = input.BookNumber,
                BookDate = input.BookDate,
                FromEntityId = input.FromEntityId,
                ToEntityId = input.ToEntityId,
                DocumentTypeId = input.DocumentTypeId,
                DepartmentId = input.DepartmentId,
                Amount = input.Amount,
                Currency = input.Currency,
                ExchangeRate = input.ExchangeRate,
                AmountInIqd = amountInIqd,
                Keywords = input.Keywords,
                Notes = input.Notes,
                BodyHtml = input.BodyHtml,
                CreatedByUserId = current.UserId!.Value,
                CreatedAt = DateTime.UtcNow,
            };
            db.ArchiveDocs.Add(doc);
            audit.Add("Create", nameof(ArchiveDoc), null, $"أرشيف: {doc.ArchiveNumber}", companyId);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
        return doc;
    }

    public async Task<ArchiveDoc> UpdateAsync(int id, UpdateArchiveInput input, CancellationToken ct = default)
    {
        var doc = await GetAsync(id, ct);
        EnsureCanModify(doc);
        if (string.IsNullOrWhiteSpace(input.Title)) throw new ValidationException("العنوان مطلوب.");
        await ValidateRefsAsync(doc.CompanyId, input.FromEntityId, input.ToEntityId, input.DocumentTypeId, ct);

        doc.Title = input.Title.Trim();
        doc.BookNumber = input.BookNumber;
        doc.BookDate = input.BookDate;
        doc.FromEntityId = input.FromEntityId;
        doc.ToEntityId = input.ToEntityId;
        doc.DocumentTypeId = input.DocumentTypeId;
        doc.DepartmentId = input.DepartmentId;
        doc.Amount = input.Amount;
        doc.Currency = input.Currency;
        doc.ExchangeRate = input.ExchangeRate;
        doc.AmountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        doc.Keywords = input.Keywords;
        doc.Notes = input.Notes;
        doc.BodyHtml = input.BodyHtml;

        audit.Add("Update", nameof(ArchiveDoc), id.ToString(), null, doc.CompanyId);
        await db.SaveChangesAsync(ct);
        return doc;
    }

    public async Task SoftDeleteAsync(int id, CancellationToken ct = default)
    {
        var doc = await GetAsync(id, ct);
        EnsureCanModify(doc);
        doc.IsDeleted = true;
        doc.DeletedByUserId = current.UserId;
        doc.DeletedAt = DateTime.UtcNow;
        audit.Add("Delete", nameof(ArchiveDoc), id.ToString(), "حذف ناعم", doc.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    // ---------------- مساعدات ----------------
    private int ResolveCompanyId(int? requested)
    {
        if (current.ActiveCompanyId is not null) return current.ActiveCompanyId.Value;
        if (current.IsSuperAdmin && requested is not null) return requested.Value;
        throw new ValidationException("تعذّر تحديد الشركة. حدّد الشركة الفعّالة.");
    }

    private async Task ValidateRefsAsync(int companyId, int? fromEntity, int? toEntity, int? docType, CancellationToken ct)
    {
        foreach (var eid in new[] { fromEntity, toEntity })
            if (eid is not null && !await db.Entities.AnyAsync(e => e.EntityId == eid && e.CompanyId == companyId, ct))
                throw new ValidationException("جهة غير موجودة في هذه الشركة.");
        if (docType is not null && !await db.DocumentTypes.AnyAsync(t => t.DocumentTypeId == docType && t.CompanyId == companyId, ct))
            throw new ValidationException("نوع المستند غير موجود في هذه الشركة.");
    }

    private void EnsureCanModify(ArchiveDoc doc)
    {
        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if (RoleHierarchy.IsManagerOrAbove(role)) return;
        if (role == UserRole.Employee && doc.CreatedByUserId == current.UserId) return;
        throw new ForbiddenException("لا تملك صلاحية تعديل هذا المستند.");
    }

    private void RequireNotReader()
    {
        if (current.Role is null or UserRole.Reader)
            throw new ForbiddenException("القارئ لا يملك صلاحية الإضافة.");
    }
}
