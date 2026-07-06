using System.Text.Json;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Documents;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Outgoing;

// ----- مدخلات العمليات -----
public sealed record CreateOutgoingInput(
    int? CompanyId, int EntityId, int TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record UpdateOutgoingInput(
    int EntityId, int TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record EditApprovedInput(
    int EntityId, int TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate,
    byte[] RowVersion, string? ChangeNote);

public interface IOutgoingService
{
    IQueryable<OutgoingBook> Query();
    Task<OutgoingBook> GetAsync(int id, CancellationToken ct = default);
    Task<OutgoingBook> CreateDraftAsync(CreateOutgoingInput input, CancellationToken ct = default);
    Task<OutgoingBook> UpdateDraftAsync(int id, UpdateOutgoingInput input, CancellationToken ct = default);
    Task ApproveAsync(int id, CancellationToken ct = default);
    Task EditAfterApprovalAsync(int id, EditApprovedInput input, CancellationToken ct = default);
    Task SoftDeleteAsync(int id, CancellationToken ct = default);
    Task<byte[]> GetPdfAsync(int id, CancellationToken ct = default);
    Task<byte[]> GetWordAsync(int id, CancellationToken ct = default);
    Task<byte[]> PreviewPdfAsync(CreateOutgoingInput input, CancellationToken ct = default);
}

public sealed class OutgoingService(
    AppDbContext db,
    ICurrentUser current,
    INumberingService numbering,
    IAuditService audit,
    BookRenderer renderer,
    IFileStorage storage) : IOutgoingService
{
    private const string CounterType = "Outgoing";

    /// <summary>استعلام يطبّق رؤية الموظف (عمله فقط)؛ العزل حسب الشركة يفرضه DbContext.</summary>
    public IQueryable<OutgoingBook> Query()
    {
        var q = db.OutgoingBooks.AsQueryable();
        if (current.Role == UserRole.Employee || current.Role == UserRole.Reader)
            q = q.Where(b => b.CreatedByUserId == current.UserId);
        return q;
    }

    public async Task<OutgoingBook> GetAsync(int id, CancellationToken ct = default)
        => await Query().FirstOrDefaultAsync(b => b.OutgoingId == id, ct)
           ?? throw new NotFoundException("الكتاب غير موجود أو لا تملك صلاحية رؤيته.");

    public async Task<OutgoingBook> CreateDraftAsync(CreateOutgoingInput input, CancellationToken ct = default)
    {
        RequireRole(UserRole.Employee); // موظف فأعلى
        var companyId = ResolveCompanyId(input.CompanyId);
        await ValidateRefsAsync(companyId, input.EntityId, input.TemplateId, ct);

        var amountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        ValidateRequired(input.Subject, input.BodyHtml);

        var book = new OutgoingBook
        {
            CompanyId = companyId,
            EntityId = input.EntityId,
            TemplateId = input.TemplateId,
            Date = input.Date,
            HeaderPhrase = input.HeaderPhrase?.Trim(),
            SignatoryName = input.SignatoryName?.Trim(),
            SignatoryTitle = input.SignatoryTitle?.Trim(),
            Subject = input.Subject.Trim(),
            BodyHtml = input.BodyHtml,
            Amount = input.Amount,
            Currency = input.Currency,
            ExchangeRate = input.ExchangeRate,
            AmountInIqd = amountInIqd,
            Status = BookStatus.Draft,
            CreatedByUserId = current.UserId!.Value,
            CreatedAt = DateTime.UtcNow,
        };
        db.OutgoingBooks.Add(book);
        audit.Add("Create", nameof(OutgoingBook), null, $"مسودّة: {book.Subject}", companyId);
        await db.SaveChangesAsync(ct);
        return book;
    }

    public async Task<OutgoingBook> UpdateDraftAsync(int id, UpdateOutgoingInput input, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        if (book.Status != BookStatus.Draft)
            throw new ValidationException("لا يمكن تعديل كتاب معتمد عبر هذه العملية (استخدم التعديل بعد الاعتماد).");
        EnsureCanModifyDraft(book);
        await ValidateRefsAsync(book.CompanyId, input.EntityId, input.TemplateId, ct);
        ValidateRequired(input.Subject, input.BodyHtml);

        book.EntityId = input.EntityId;
        book.TemplateId = input.TemplateId;
        book.Date = input.Date;
        book.HeaderPhrase = input.HeaderPhrase?.Trim();
        book.SignatoryName = input.SignatoryName?.Trim();
        book.SignatoryTitle = input.SignatoryTitle?.Trim();
        book.Subject = input.Subject.Trim();
        book.BodyHtml = input.BodyHtml;
        book.Amount = input.Amount;
        book.Currency = input.Currency;
        book.ExchangeRate = input.ExchangeRate;
        book.AmountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        book.UpdatedAt = DateTime.UtcNow;

        audit.Add("Update", nameof(OutgoingBook), id.ToString(), "تعديل مسودّة", book.CompanyId);
        await db.SaveChangesAsync(ct);
        return book;
    }

    public async Task ApproveAsync(int id, CancellationToken ct = default)
    {
        if (!EffectiveCanApprove())
            throw new ForbiddenException("لا تملك صلاحية الاعتماد.");

        var book = await GetAsync(id, ct);
        if (book.Status != BookStatus.Draft)
            throw new ValidationException("الكتاب معتمد بالفعل.");
        ValidateRequired(book.Subject, book.BodyHtml);

        var (company, template, entity) = await LoadRefsAsync(book, ct);

        // وحدة قابلة لإعادة المحاولة (متوافقة مع EnableRetryOnFailure) تضمّ المعاملة كاملة.
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            var year = DateTime.UtcNow.Year;
            var serial = await numbering.NextSerialAsync(book.CompanyId, year, CounterType, ct);

            book.Year = year;
            book.SerialNo = serial;
            book.Number = $"{company.Prefix}-{year}-{serial:D5}";
            book.Status = BookStatus.Final;
            book.ApprovedByUserId = current.UserId;
            book.ApprovedAt = DateTime.UtcNow;
            book.AmountInIqd = FinancialCalculator.ComputeIqd(book.Amount, book.Currency, book.ExchangeRate);

            var render = await renderer.RenderPdfAsync(book, template, entity, company, false, ct);
            book.QrContent = render.QrContent;
            book.QrSignature = render.QrSignature;
            book.GeneratedPdfBlobKey = await storage.SaveAsync($"{book.Number}.pdf", render.Pdf, ct);

            audit.Add("Approve", nameof(OutgoingBook), id.ToString(), $"اعتماد ورقم {book.Number}", book.CompanyId);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
    }

    public async Task EditAfterApprovalAsync(int id, EditApprovedInput input, CancellationToken ct = default)
    {
        RequireRole(UserRole.Manager); // المدير فأعلى
        var book = await GetAsync(id, ct);
        if (book.Status != BookStatus.Final)
            throw new ValidationException("التعديل بعد الاعتماد يخص الكتب المعتمدة فقط.");
        await ValidateRefsAsync(book.CompanyId, input.EntityId, input.TemplateId, ct);
        ValidateRequired(input.Subject, input.BodyHtml);

        // تزامن متفائل: امنع الكتابة فوق نسخة قديمة
        db.Entry(book).Property(b => b.RowVersion).OriginalValue = input.RowVersion;

        // سناب-شوت للنسخة الحالية قبل التعديل
        var lastVersion = await db.DocumentVersions
            .Where(v => v.DocType == OwnerType.Outgoing && v.DocId == id)
            .MaxAsync(v => (int?)v.VersionNo, ct) ?? 0;

        db.DocumentVersions.Add(new DocumentVersion
        {
            DocType = OwnerType.Outgoing,
            DocId = id,
            VersionNo = lastVersion + 1,
            SnapshotJson = Snapshot(book),
            ChangedByUserId = current.UserId!.Value,
            ChangedAt = DateTime.UtcNow,
            ChangeNote = input.ChangeNote,
        });

        // تطبيق التعديلات (الرقم يبقى ثابتاً)
        book.EntityId = input.EntityId;
        book.TemplateId = input.TemplateId;
        book.Date = input.Date;
        book.HeaderPhrase = input.HeaderPhrase?.Trim();
        book.SignatoryName = input.SignatoryName?.Trim();
        book.SignatoryTitle = input.SignatoryTitle?.Trim();
        book.Subject = input.Subject.Trim();
        book.BodyHtml = input.BodyHtml;
        book.Amount = input.Amount;
        book.Currency = input.Currency;
        book.ExchangeRate = input.ExchangeRate;
        book.AmountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        book.UpdatedAt = DateTime.UtcNow;

        // إعادة توليد PDF/QR
        var (company, template, entity) = await LoadRefsAsync(book, ct);
        var render = await renderer.RenderPdfAsync(book, template, entity, company, false, ct);
        book.QrContent = render.QrContent;
        book.QrSignature = render.QrSignature;
        book.GeneratedPdfBlobKey = await storage.SaveAsync($"{book.Number}.pdf", render.Pdf, ct);

        audit.Add("EditApproved", nameof(OutgoingBook), id.ToString(),
            $"تعديل بعد الاعتماد (إصدار {lastVersion + 1})", book.CompanyId);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new ConflictException("تم تعديل الكتاب من مستخدم آخر — أعد التحميل وحاول مجدداً.");
        }
    }

    public async Task SoftDeleteAsync(int id, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        if (book.Status == BookStatus.Final)
            RequireRole(UserRole.Manager);      // المعتمد: المدير فأعلى
        else
            EnsureCanModifyDraft(book);          // المسودّة: المالك أو المدير فأعلى

        book.IsDeleted = true;
        book.DeletedByUserId = current.UserId;
        book.DeletedAt = DateTime.UtcNow;
        audit.Add("Delete", nameof(OutgoingBook), id.ToString(), "حذف ناعم", book.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task<byte[]> GetPdfAsync(int id, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        if (book.GeneratedPdfBlobKey is null)
            throw new ValidationException("لا يوجد PDF — يُولَّد عند الاعتماد.");
        return await storage.ReadAsync(book.GeneratedPdfBlobKey, ct);
    }

    public async Task<byte[]> GetWordAsync(int id, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        var entity = await db.Entities.FindAsync([book.EntityId], ct);
        var company = await db.Companies.FindAsync([book.CompanyId], ct);
        return renderer.RenderWord(book, entity!, company!);
    }

    public async Task<byte[]> PreviewPdfAsync(CreateOutgoingInput input, CancellationToken ct = default)
    {
        var companyId = ResolveCompanyId(input.CompanyId);
        await ValidateRefsAsync(companyId, input.EntityId, input.TemplateId, ct);

        var company = await db.Companies.FindAsync([companyId], ct);
        var template = await db.Templates.FindAsync([input.TemplateId], ct);
        var entity = await db.Entities.FindAsync([input.EntityId], ct);

        var amountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);

        var book = new OutgoingBook
        {
            CompanyId = companyId,
            EntityId = input.EntityId,
            TemplateId = input.TemplateId,
            Date = input.Date,
            HeaderPhrase = input.HeaderPhrase?.Trim(),
            SignatoryName = input.SignatoryName?.Trim(),
            SignatoryTitle = input.SignatoryTitle?.Trim(),
            Subject = input.Subject.Trim(),
            BodyHtml = input.BodyHtml,
            Amount = input.Amount,
            Currency = input.Currency,
            ExchangeRate = input.ExchangeRate,
            AmountInIqd = amountInIqd,
            Status = BookStatus.Draft,
            Number = "مسودة (معاينة)", // نص وهمي لغرض العرض
            CreatedByUserId = current.UserId ?? 0,
            CreatedAt = DateTime.UtcNow,
        };

        var result = await renderer.RenderPdfAsync(book, template!, entity!, company!, isPreview: true, ct);
        return result.Pdf;
    }

    // --- الوظائف المساعدة ----------------

    private int ResolveCompanyId(int? requested)
    {
        if (current.ActiveCompanyId is not null) return current.ActiveCompanyId.Value;
        if (current.IsSuperAdmin && requested is not null) return requested.Value;
        throw new ValidationException("تعذّر تحديد الشركة. حدّد الشركة الفعّالة.");
    }

    private async Task ValidateRefsAsync(int companyId, int entityId, int templateId, CancellationToken ct)
    {
        if (!await db.Entities.AnyAsync(e => e.EntityId == entityId && e.CompanyId == companyId, ct))
            throw new ValidationException("الجهة غير موجودة في هذه الشركة.");
        if (!await db.Templates.AnyAsync(t => t.TemplateId == templateId && t.CompanyId == companyId && t.IsActive, ct))
            throw new ValidationException("القالب غير موجود أو غير مُفعّل في هذه الشركة.");
    }

    private async Task<(Company company, Template template, Entity entity)> LoadRefsAsync(OutgoingBook book, CancellationToken ct)
    {
        var company = await db.Companies.FirstOrDefaultAsync(c => c.CompanyId == book.CompanyId, ct)
                      ?? throw new NotFoundException("الشركة غير موجودة.");
        var template = await db.Templates.FirstOrDefaultAsync(t => t.TemplateId == book.TemplateId, ct)
                       ?? throw new NotFoundException("القالب غير موجود.");
        var entity = await db.Entities.FirstOrDefaultAsync(e => e.EntityId == book.EntityId, ct)
                     ?? throw new NotFoundException("الجهة غير موجودة.");
        return (company, template, entity);
    }

    private static void ValidateRequired(string subject, string body)
    {
        if (string.IsNullOrWhiteSpace(subject)) throw new ValidationException("الموضوع مطلوب.");
        if (string.IsNullOrWhiteSpace(body)) throw new ValidationException("نص الكتاب مطلوب.");
    }

    private void EnsureCanModifyDraft(OutgoingBook book)
    {
        var role = RequireAnyRole();
        if (RoleHierarchy.IsManagerOrAbove(role)) return;        // المدير فأعلى: أي مسودّة
        if (book.CreatedByUserId == current.UserId) return;       // الموظف: مسودّته فقط
        throw new ForbiddenException("لا تملك صلاحية تعديل هذه المسودّة.");
    }

    private bool EffectiveCanApprove()
    {
        var role = current.Role ?? UserRole.Reader;
        if (RoleHierarchy.IsManagerOrAbove(role)) return true;
        if (current.CanApprove) return true;
        // تفويض نشط ضمن المدّة
        var now = DateTime.UtcNow;
        return db.ApprovalDelegations.Any(d => d.ToUserId == current.UserId && d.IsActive
            && d.StartDate <= now && (d.EndDate == null || d.EndDate >= now));
    }

    private UserRole RequireAnyRole() =>
        current.Role ?? throw new ForbiddenException("غير مصرّح.");

    private void RequireRole(UserRole minimumOrHigher)
    {
        var role = RequireAnyRole();
        if ((int)role > (int)minimumOrHigher)
            throw new ForbiddenException("صلاحيتك لا تسمح بهذه العملية.");
    }

    private static string Snapshot(OutgoingBook b) => JsonSerializer.Serialize(new
    {
        b.Number, b.Date, b.EntityId, b.TemplateId, b.Subject, b.BodyHtml,
        b.Amount, b.Currency, b.ExchangeRate, b.AmountInIqd, b.QrContent
    });
}
