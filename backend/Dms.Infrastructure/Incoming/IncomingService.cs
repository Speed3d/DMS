using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Incoming;

// ----- مدخلات العمليات -----
public sealed record CreateIncomingInput(
    int? CompanyId,
    string? ExternalNumber,
    DateTime? ExternalDate,
    DateTime ReceivedDate,
    TimeSpan? ReceivedTime,
    int EntityId,
    string Subject,
    int? DocumentTypeId,
    ReceiveMethod ReceiveMethod,
    string? FolderName,
    string? Keywords,
    string? Notes,
    decimal? Amount,
    Currency? Currency,
    decimal? ExchangeRate);

public sealed record UpdateIncomingInput(
    string? ExternalNumber,
    DateTime? ExternalDate,
    DateTime ReceivedDate,
    TimeSpan? ReceivedTime,
    int EntityId,
    string Subject,
    int? DocumentTypeId,
    ReceiveMethod ReceiveMethod,
    string? FolderName,
    string? Keywords,
    string? Notes,
    decimal? Amount,
    Currency? Currency,
    decimal? ExchangeRate);

public interface IIncomingService
{
    IQueryable<IncomingBook> Query();
    Task<IncomingBook> GetAsync(int id, CancellationToken ct = default);
    Task<IncomingBook> CreateAsync(CreateIncomingInput input, CancellationToken ct = default);
    Task<IncomingBook> UpdateAsync(int id, UpdateIncomingInput input, CancellationToken ct = default);
    Task ChangeStatusAsync(int id, IncomingStatus newStatus, string? note, CancellationToken ct = default);
    Task ForwardAsync(int id, string toDepartment, string? note, CancellationToken ct = default);
    Task LinkToOutgoingAsync(int incomingId, int outgoingId, CancellationToken ct = default);
    Task UnlinkFromOutgoingAsync(int incomingId, CancellationToken ct = default);
    Task SoftDeleteAsync(int id, CancellationToken ct = default);
    Task<List<MovementLog>> GetMovementsAsync(int incomingId, CancellationToken ct = default);
}

public sealed class IncomingService(
    AppDbContext db,
    ICurrentUser current,
    INumberingService numbering,
    IAuditService audit) : IIncomingService
{
    private const string CounterType = "Incoming";

    public IQueryable<IncomingBook> Query()
    {
        var q = db.IncomingBooks.AsQueryable();
        // الموظف/القارئ يرى فقط الكتب التي استلمها بنفسه
        if (current.Role == UserRole.Employee || current.Role == UserRole.Reader)
            q = q.Where(b => b.ReceivedByUserId == current.UserId);
        return q;
    }

    public async Task<IncomingBook> GetAsync(int id, CancellationToken ct = default)
        => await Query()
            .Include(b => b.Entity)
            .FirstOrDefaultAsync(b => b.IncomingId == id, ct)
           ?? throw new NotFoundException("الكتاب الوارد غير موجود أو لا تملك صلاحية رؤيته.");

    public async Task<IncomingBook> CreateAsync(CreateIncomingInput input, CancellationToken ct = default)
    {
        RequireRole(UserRole.Employee); // موظف فأعلى
        var companyId = ResolveCompanyId(input.CompanyId);
        await ValidateRefsAsync(companyId, input.EntityId, input.DocumentTypeId, ct);
        ValidateRequired(input.Subject);

        var amountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        var year = input.ReceivedDate.Year;

        // وحدة قابلة لإعادة المحاولة لمعاملة الترقيم
        var strategy = db.Database.CreateExecutionStrategy();
        IncomingBook book = null!;

        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var serial = await numbering.NextSerialAsync(companyId, year, CounterType, ct);
            var company = await db.Companies.FindAsync(new object[] { companyId }, ct);

            book = new IncomingBook
            {
                CompanyId = companyId,
                Year = year,
                SerialNo = serial,
                IncomingNumber = $"{company!.Prefix}-IN-{year}-{serial:D5}",
                ExternalNumber = input.ExternalNumber?.Trim(),
                ExternalDate = input.ExternalDate,
                ReceivedDate = input.ReceivedDate,
                ReceivedTime = input.ReceivedTime,
                EntityId = input.EntityId,
                Subject = input.Subject.Trim(),
                DocumentTypeId = input.DocumentTypeId,
                ReceiveMethod = input.ReceiveMethod,
                FolderName = input.FolderName?.Trim(),
                Keywords = input.Keywords?.Trim(),
                Notes = input.Notes?.Trim(),
                Amount = input.Amount,
                Currency = input.Currency,
                ExchangeRate = input.ExchangeRate,
                AmountInIqd = amountInIqd,
                Status = IncomingStatus.New,
                ReceivedByUserId = current.UserId!.Value,
                CreatedByUserId = current.UserId!.Value,
                CreatedAt = DateTime.UtcNow,
                LastAction = "تم التسجيل"
            };

            db.IncomingBooks.Add(book);
            
            var log = new MovementLog
            {
                CompanyId = companyId,
                IncomingBook = book,
                Action = "Registered",
                Description = $"تم تسجيل الكتاب الوارد رقم {book.IncomingNumber}",
                PerformedByUserId = current.UserId.Value,
                PerformedAt = DateTime.UtcNow
            };
            db.MovementLogs.Add(log);

            audit.Add("Create", nameof(IncomingBook), null, $"تسجيل وارد: {book.Subject}", companyId);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });

        return book;
    }

    public async Task<IncomingBook> UpdateAsync(int id, UpdateIncomingInput input, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        if (book.Status != IncomingStatus.New)
            throw new ValidationException("لا يمكن تعديل الكتاب بشكل كامل إلا وهو في حالة (جديد).");

        await ValidateRefsAsync(book.CompanyId, input.EntityId, input.DocumentTypeId, ct);
        ValidateRequired(input.Subject);

        book.ExternalNumber = input.ExternalNumber?.Trim();
        book.ExternalDate = input.ExternalDate;
        book.ReceivedDate = input.ReceivedDate;
        book.ReceivedTime = input.ReceivedTime;
        book.EntityId = input.EntityId;
        book.Subject = input.Subject.Trim();
        book.DocumentTypeId = input.DocumentTypeId;
        book.ReceiveMethod = input.ReceiveMethod;
        book.FolderName = input.FolderName?.Trim();
        book.Keywords = input.Keywords?.Trim();
        book.Notes = input.Notes?.Trim();
        book.Amount = input.Amount;
        book.Currency = input.Currency;
        book.ExchangeRate = input.ExchangeRate;
        book.AmountInIqd = FinancialCalculator.ComputeIqd(input.Amount, input.Currency, input.ExchangeRate);
        book.UpdatedAt = DateTime.UtcNow;

        var log = new MovementLog
        {
            CompanyId = book.CompanyId,
            IncomingId = book.IncomingId,
            Action = "Updated",
            Description = "تم تعديل بيانات الكتاب",
            PerformedByUserId = current.UserId!.Value,
            PerformedAt = DateTime.UtcNow
        };
        db.MovementLogs.Add(log);

        audit.Add("Update", nameof(IncomingBook), id.ToString(), "تعديل وارد", book.CompanyId);
        await db.SaveChangesAsync(ct);
        return book;
    }

    public async Task ChangeStatusAsync(int id, IncomingStatus newStatus, string? note, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        var oldStatus = book.Status;

        IncomingWorkflow.EnsureTransitionAllowed(oldStatus, newStatus);  // مصفوفة الانتقالات (منطق المجال)
        EnsureStatusChangePermission(oldStatus, newStatus);               // صلاحية الدور

        // Hint: الانتقال لـ«تم الرد» يتم تلقائياً عند الربط بصادر؛ فإن تمّ يدوياً (ردّ ورقي خارج النظام)
        // تصبح الملاحظة إلزامية لتوثيق سبب الرد.
        if (newStatus == IncomingStatus.Replied && book.ReplyOutgoingId is null && string.IsNullOrWhiteSpace(note))
            throw new ValidationException("يجب إدخال ملاحظة عند تغيير الحالة إلى (تم الرد) يدوياً بدون ربط بكتاب صادر.");

        book.Status = newStatus;
        book.LastAction = $"تغيير الحالة إلى {ArabicName(newStatus)}";
        book.UpdatedAt = DateTime.UtcNow;

        var description = $"تغيير الحالة من ({ArabicName(oldStatus)}) إلى ({ArabicName(newStatus)})";
        if (!string.IsNullOrWhiteSpace(note)) description += $". ملاحظة: {note.Trim()}";

        var log = new MovementLog
        {
            CompanyId = book.CompanyId,
            IncomingId = book.IncomingId,
            Action = "StatusChanged",
            Description = description,
            PerformedByUserId = current.UserId!.Value,
            PerformedAt = DateTime.UtcNow
        };
        db.MovementLogs.Add(log);

        audit.Add("ChangeStatus", nameof(IncomingBook), id.ToString(), newStatus.ToString(), book.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task ForwardAsync(int id, string toDepartment, string? note, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        if (string.IsNullOrWhiteSpace(toDepartment))
            throw new ValidationException("اسم القسم مطلوب.");

        // Hint: الإحالة إجراء تشغيلي على كتاب قيد المعالجة — لا تُقبل على كتاب مغلق أو مؤرشف
        // (وإلا أعادت السجل الرسمي إلى قيد المراجعة).
        if (!IncomingWorkflow.IsOperable(book.Status))
            throw new ValidationException(
                $"لا يمكن إحالة كتاب في حالة ({ArabicName(book.Status)}) — الإحالة متاحة للكتب (جديد) أو (قيد المراجعة) فقط.");

        var toDept = toDepartment.Trim();
        var oldDept = book.FolderName;
        book.FolderName = toDept;
        if (book.Status == IncomingStatus.New)
            book.Status = IncomingStatus.InReview;  // الإحالة تنقل الكتاب الجديد تلقائياً لقيد المراجعة
        book.LastAction = $"محال إلى {toDept}";
        book.UpdatedAt = DateTime.UtcNow;

        var description = $"تم التحويل من ({oldDept ?? "غير محدد"}) إلى ({toDept})";
        if (!string.IsNullOrWhiteSpace(note)) description += $". ملاحظة: {note.Trim()}";

        var log = new MovementLog
        {
            CompanyId = book.CompanyId,
            IncomingId = book.IncomingId,
            Action = "Forwarded",
            Description = description,
            FromDepartment = oldDept,
            ToDepartment = toDept,
            PerformedByUserId = current.UserId!.Value,
            PerformedAt = DateTime.UtcNow
        };
        db.MovementLogs.Add(log);

        audit.Add("Forward", nameof(IncomingBook), id.ToString(), toDept, book.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task LinkToOutgoingAsync(int incomingId, int outgoingId, CancellationToken ct = default)
    {
        // Hint: الربط ينقل الكتاب إلى «تم الرد» — فهو قرار إداري بصلاحية المدير فأعلى،
        // وإلا صار طريقاً للالتفاف على قيد الموظف (جديد ← قيد المراجعة فقط) في تغيير الحالة.
        RequireRole(UserRole.Manager);

        var incoming = await GetAsync(incomingId, ct);

        // Hint: الربط يعني «تم الرد» — فهو إجراء على كتاب قيد المعالجة فقط، لا على مغلق أو مؤرشف.
        // (استثناء مقصود من مصفوفة الانتقالات: الربط بصادر معتمد ينقل الكتاب مباشرة إلى «تم الرد».)
        if (!IncomingWorkflow.IsOperable(incoming.Status))
            throw new ValidationException(
                $"لا يمكن ربط كتاب في حالة ({ArabicName(incoming.Status)}) بكتاب صادر — الربط متاح للكتب (جديد) أو (قيد المراجعة) فقط.");

        // Hint: ربط جديد فوق ربط قائم يُفقد الأثر — يُطلب فك الارتباط أولاً.
        if (incoming.ReplyOutgoingId is not null && incoming.ReplyOutgoingId != outgoingId)
            throw new ConflictException("الكتاب الوارد مرتبط بكتاب صادر آخر. افكك الارتباط الحالي أولاً.");

        // التحقق من الصادر
        var outgoing = await db.OutgoingBooks.FirstOrDefaultAsync(b => b.OutgoingId == outgoingId, ct)
            ?? throw new NotFoundException("الكتاب الصادر غير موجود.");

        if (outgoing.CompanyId != incoming.CompanyId)
            throw new ValidationException("لا يمكن ربط كتب من شركات مختلفة.");

        if (outgoing.Status != BookStatus.Final)
            throw new ValidationException("يمكن الربط فقط مع الكتب الصادرة المعتمدة.");

        // Hint: الصادر الواحد يردّ على وارد واحد — علاقة واحد‑لواحد في الاتجاهين.
        if (outgoing.ReplyToIncomingId is not null && outgoing.ReplyToIncomingId != incomingId)
            throw new ConflictException("الكتاب الصادر مرتبط بكتاب وارد آخر. اختر صادراً غير مرتبط.");

        incoming.ReplyOutgoingId = outgoing.OutgoingId;
        incoming.Status = IncomingStatus.Replied;   // الربط بصادر معتمد = ردّ رسمي
        incoming.LastAction = $"تم الرد بالصادر {outgoing.Number}";
        incoming.UpdatedAt = DateTime.UtcNow;

        outgoing.ReplyToIncomingId = incoming.IncomingId;

        var log = new MovementLog
        {
            CompanyId = incoming.CompanyId,
            IncomingId = incoming.IncomingId,
            Action = "LinkedToOutgoing",
            Description = $"تم ربط الكتاب بالصادر رقم {outgoing.Number}",
            PerformedByUserId = current.UserId!.Value,
            PerformedAt = DateTime.UtcNow
        };
        db.MovementLogs.Add(log);

        audit.Add("Link", nameof(IncomingBook), incomingId.ToString(), $"Linked to {outgoing.Number}", incoming.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task UnlinkFromOutgoingAsync(int incomingId, CancellationToken ct = default)
    {
        // Hint: فك الربط يُرجع الكتاب من «تم الرد» إلى «قيد المراجعة» — نفس صلاحية الربط.
        RequireRole(UserRole.Manager);

        var incoming = await GetAsync(incomingId, ct);
        if (incoming.ReplyOutgoingId is null)
            throw new ValidationException("لا يوجد كتاب صادر مرتبط بهذا الكتاب الوارد.");

        // Hint: الكتاب المؤرشف سجل رسمي مغلق — لا يُعدَّل ارتباطه.
        if (incoming.Status == IncomingStatus.Archived)
            throw new ValidationException("لا يمكن فك ارتباط كتاب مؤرشف.");

        var outgoing = await db.OutgoingBooks.FindAsync(new object[] { incoming.ReplyOutgoingId.Value }, ct);
        if (outgoing != null)
        {
            outgoing.ReplyToIncomingId = null;
        }

        incoming.ReplyOutgoingId = null;
        // Hint: العودة لقيد المراجعة تخصّ الكتاب الذي صار «تم الرد» بسبب هذا الربط؛
        // أما المغلق فيبقى مغلقاً (الإغلاق قرار مستقل عن الربط).
        if (incoming.Status == IncomingStatus.Replied)
            incoming.Status = IncomingStatus.InReview;
        incoming.LastAction = "تم فك الارتباط من الصادر";
        incoming.UpdatedAt = DateTime.UtcNow;

        var log = new MovementLog
        {
            CompanyId = incoming.CompanyId,
            IncomingId = incoming.IncomingId,
            Action = "UnlinkedFromOutgoing",
            Description = "تم فك ربط الكتاب من الصادر",
            PerformedByUserId = current.UserId!.Value,
            PerformedAt = DateTime.UtcNow
        };
        db.MovementLogs.Add(log);

        audit.Add("Unlink", nameof(IncomingBook), incomingId.ToString(), null, incoming.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task SoftDeleteAsync(int id, CancellationToken ct = default)
    {
        var book = await GetAsync(id, ct);
        
        if (book.Status == IncomingStatus.Archived && current.Role != UserRole.SuperAdmin)
        {
            throw new ForbiddenException("فقط السوبر أدمن يمكنه حذف الكتب المؤرشفة.");
        }

        if (book.Status != IncomingStatus.New)
            RequireRole(UserRole.Manager); // المدير فأعلى للكتب قيد المعالجة

        // فك الارتباط التلقائي إن وُجد
        if (book.ReplyOutgoingId != null)
        {
            var outgoing = await db.OutgoingBooks.FindAsync(new object[] { book.ReplyOutgoingId.Value }, ct);
            if (outgoing != null) outgoing.ReplyToIncomingId = null;
        }

        book.IsDeleted = true;
        book.DeletedByUserId = current.UserId;
        book.DeletedAt = DateTime.UtcNow;
        
        audit.Add("Delete", nameof(IncomingBook), id.ToString(), "حذف ناعم", book.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task<List<MovementLog>> GetMovementsAsync(int incomingId, CancellationToken ct = default)
    {
        // حسب الخطة: يظهر فقط للسوبر أدمن ورئيس الشركة (المرحلة 1)
        if (current.Role is not (UserRole.SuperAdmin or UserRole.President))
            throw new ForbiddenException("لا تملك صلاحية رؤية سجل الحركة.");

        var book = await GetAsync(incomingId, ct); // للتحقق من الأمان

        return await db.MovementLogs
            .Where(m => m.IncomingId == incomingId)
            .OrderBy(m => m.PerformedAt)
            .ToListAsync(ct);
    }

    // --- الوظائف المساعدة ----------------

    /// <summary>الاسم العربي للحالة (Hint: اختصار لـ IncomingWorkflow.ArabicName داخل هذا الملف).</summary>
    private static string ArabicName(IncomingStatus status) => IncomingWorkflow.ArabicName(status);

    /// <summary>
    /// صلاحية الدور في تغيير الحالة.
    /// Hint: الأرشفة للمدير فأعلى، والموظف/القارئ لا يتجاوز تحويل الكتاب الجديد لقيد المراجعة.
    /// </summary>
    private void EnsureStatusChangePermission(IncomingStatus from, IncomingStatus to)
    {
        if (to == IncomingStatus.Archived)
        {
            RequireRole(UserRole.Manager);
            return;
        }

        var role = RequireAnyRole();
        if (role is UserRole.Employee or UserRole.Reader
            && !(from == IncomingStatus.New && to == IncomingStatus.InReview))
            throw new ForbiddenException("صلاحيتك تسمح فقط بتحويل الكتاب (جديد) إلى (قيد المراجعة).");
    }

    private int ResolveCompanyId(int? requested)
    {
        if (current.ActiveCompanyId is not null) return current.ActiveCompanyId.Value;
        if (current.IsSuperAdmin && requested is not null) return requested.Value;
        throw new ValidationException("تعذّر تحديد الشركة. حدّد الشركة الفعّالة.");
    }

    private async Task ValidateRefsAsync(int companyId, int entityId, int? docTypeId, CancellationToken ct)
    {
        if (!await db.Entities.AnyAsync(e => e.EntityId == entityId && e.CompanyId == companyId, ct))
            throw new ValidationException("الجهة غير موجودة في هذه الشركة.");
            
        if (docTypeId.HasValue && !await db.DocumentTypes.AnyAsync(d => d.DocumentTypeId == docTypeId.Value && d.CompanyId == companyId, ct))
            throw new ValidationException("نوع الكتاب غير موجود.");
    }

    private static void ValidateRequired(string subject)
    {
        if (string.IsNullOrWhiteSpace(subject)) throw new ValidationException("الموضوع مطلوب.");
    }

    private UserRole RequireAnyRole() =>
        current.Role ?? throw new ForbiddenException("غير مصرّح.");

    private void RequireRole(UserRole minimumOrHigher)
    {
        var role = RequireAnyRole();
        if ((int)role > (int)minimumOrHigher)
            throw new ForbiddenException("صلاحيتك لا تسمح بهذه العملية.");
    }
}
