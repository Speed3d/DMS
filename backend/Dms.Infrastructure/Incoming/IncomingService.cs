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
    string? Keywords,
    string? Notes,
    decimal? Amount,
    Currency? Currency,
    decimal? ExchangeRate);

/// <summary>
/// بيانات عرض الكتاب الوارد مع الأسماء المرتبطة.
/// Hint: تُجهَّز في الخدمة (لا في الـ Controller) ليبقى الأخير مجرّد محوّل إلى DTO.
/// </summary>
public sealed record IncomingDetailData(
    IncomingBook Book,
    string EntityName,
    string? DocumentTypeName,
    string ReceivedByUserName,
    string? ReplyOutgoingNumber,
    IReadOnlyList<AssignmentData> Departments);

/// <summary>إسناد قسم مع اسمه واسم مَن أحاله (للعرض).</summary>
public sealed record AssignmentData(int DepartmentId, string Name, string? Note, string AssignedByUserName, DateTime AssignedAt);

/// <summary>قسم مُحال إليه مع ملاحظته الخاصة (ADR-018).</summary>
public sealed record ForwardTarget(int DepartmentId, string? Note);

/// <summary>حركة مع اسم منفّذها (Hint: الاسم لا يُخزَّن في السجل بل يُجلب عند العرض).</summary>
public sealed record MovementLogData(MovementLog Log, string PerformedByUserName);

public interface IIncomingService
{
    IQueryable<IncomingBook> Query();
    Task<IncomingBook> GetAsync(int id, CancellationToken ct = default);
    Task<IncomingDetailData> GetDetailAsync(int id, CancellationToken ct = default);
    Task<IncomingBook> CreateAsync(CreateIncomingInput input, CancellationToken ct = default);
    Task<IncomingBook> UpdateAsync(int id, UpdateIncomingInput input, CancellationToken ct = default);
    Task ChangeStatusAsync(int id, IncomingStatus newStatus, string? note, CancellationToken ct = default);
    Task ForwardAsync(int id, IReadOnlyList<ForwardTarget> targets, string? generalNote, CancellationToken ct = default);
    Task LinkToOutgoingAsync(int incomingId, int outgoingId, CancellationToken ct = default);
    Task UnlinkFromOutgoingAsync(int incomingId, CancellationToken ct = default);
    Task SoftDeleteAsync(int id, CancellationToken ct = default);
    Task<List<MovementLogData>> GetMovementsAsync(int incomingId, CancellationToken ct = default);
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
        // الموظف/القارئ يرى ثلاثة أنواع من الكتب:
        //   1) ما استلمه بنفسه.
        //   2) ما أُحيل إلى قسمه — وهذا ما يجعل الإحالة مفيدة: كتاب مُحال لـ«المالية»
        //      يظهر لكل موظفي المالية.
        //   3) **ما أحاله هو بنفسه إلى أي قسم** — ولو لم يكن مستلِمَه ولا من قسم الوجهة.
        // المدير فأعلى يرى كل كتب الشركة (بلا تقييد هنا).
        //
        // ⚠️ البند (3) ليس تزيّناً: قبله كان موظفُ «المالية» الذي يُحيل كتاباً إلى «القانونية»
        //    **يفقد رؤيته للكتاب فور إحالته** إن لم يكن مستلِمَه — فيختفي من قائمته عملٌ
        //    باشره بنفسه ولا يقدر على متابعة مصيره. «مَن أحال يبقى يرى» قاعدةُ متابعةٍ لا
        //    امتياز، ونستند فيها إلى AssignedByUserId المسجَّل على الإسناد نفسه (ADR-018).
        if (current.Role is UserRole.Employee or UserRole.Reader)
        {
            var uid = current.UserId;
            var dept = current.DepartmentId;
            q = q.Where(b => b.ReceivedByUserId == uid
                             || (dept != null && b.Assignments.Any(a => a.DepartmentId == dept))
                             || b.Assignments.Any(a => a.AssignedByUserId == uid));
        }
        return q;
    }

    public async Task<IncomingBook> GetAsync(int id, CancellationToken ct = default)
        => await Query()
            .Include(b => b.Entity)
            .FirstOrDefaultAsync(b => b.IncomingId == id, ct)
           ?? throw new NotFoundException("الكتاب الوارد غير موجود أو لا تملك صلاحية رؤيته.");

    public async Task<IncomingDetailData> GetDetailAsync(int id, CancellationToken ct = default)
    {
        // Hint: ReplyOutgoing مُضمَّن هنا فقط (شاشة التفاصيل) — بقية العمليات لا تحتاجه فتبقى GetAsync خفيفة.
        var book = await Query()
            .Include(b => b.Entity)
            .Include(b => b.ReplyOutgoing)
            .Include(b => b.Assignments).ThenInclude(a => a.Department)
            .FirstOrDefaultAsync(b => b.IncomingId == id, ct)
            ?? throw new NotFoundException("الكتاب الوارد غير موجود أو لا تملك صلاحية رؤيته.");

        var docTypeName = book.DocumentTypeId is null
            ? null
            : await db.DocumentTypes.Where(d => d.DocumentTypeId == book.DocumentTypeId)
                .Select(d => d.Name).FirstOrDefaultAsync(ct);

        // أسماء المُحيلين دفعةً واحدة (تفادي N+1)، ثم تُركَّب مع كل إسناد.
        var assignerIds = book.Assignments.Select(a => a.AssignedByUserId).Distinct().ToList();
        var assignerNames = new Dictionary<int, string>();
        foreach (var uid in assignerIds) assignerNames[uid] = await UserNameAsync(uid, ct);

        var departments = book.Assignments
            .OrderBy(a => a.AssignedAt)
            .Select(a => new AssignmentData(
                a.DepartmentId, a.Department?.Name ?? "—", a.Note,
                assignerNames.TryGetValue(a.AssignedByUserId, out var n) ? n : "—", a.AssignedAt))
            .ToList();

        return new IncomingDetailData(
            book,
            book.Entity?.Name ?? "—",
            docTypeName,
            await UserNameAsync(book.ReceivedByUserId, ct),
            book.ReplyOutgoing?.Number,
            departments);
    }

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
        EnsureEditable(book);

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

        // ⚠️ **فكّ الأرشفة يتطلّب سبباً إلزامياً.** الأرشفة تُغلق باب التعديل على السجل الرسمي،
        //    وفكّها يفتحه من جديد — فالسبب ليس تزيّناً بل الأثر الوحيد الذي يشرح لاحقاً
        //    **لماذا** خرج كتابٌ من الأرشيف ومن أذِن بذلك. بدونه يصير الفكّ عمليةً بلا ذاكرة.
        if (oldStatus == IncomingStatus.Archived && string.IsNullOrWhiteSpace(note))
            throw new ValidationException("يجب إدخال سبب فكّ الأرشفة — يُسجَّل في سجل الحركة والتدقيق.");

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

    /// <summary>إحالة الكتاب إلى **قسم واحد أو أكثر** معاً، بملاحظة لكل قسم وملاحظة عامة (ADR-018).</summary>
    /// <remarks>
    /// الإحالة **تراكمية**: تُضيف أقساماً ولا تُزيح الموجود (قرار المالك) — لأن الإزاحة الضمنية
    /// تُفقد قسماً كتابَه بلا أن يقصد أحد. وإعادة الإحالة لقسم موجود **تُحدّث ملاحظته** ولا تُكرّره.
    /// </remarks>
    public async Task ForwardAsync(int id, IReadOnlyList<ForwardTarget> targets, string? generalNote, CancellationToken ct = default)
    {
        // القارئ لا يُحيل: دوره اطّلاع لا معالجة.
        if (current.Role is UserRole.Reader)
            throw new ForbiddenException("القارئ لا يملك صلاحية إحالة الكتب.");

        if (targets is null || targets.Count == 0)
            throw new ValidationException("اختر قسماً واحداً على الأقل للإحالة إليه.");

        var book = await db.IncomingBooks.Include(b => b.Assignments)
                       .FirstOrDefaultAsync(b => b.IncomingId == id, ct) is { } found
                       && (await Query().AnyAsync(b => b.IncomingId == id, ct))
                   ? found
                   : throw new NotFoundException("الكتاب الوارد غير موجود أو لا تملك صلاحية رؤيته.");

        // Hint: الإحالة إجراء تشغيلي على كتاب قيد المعالجة — لا تُقبل على مغلق أو مؤرشف.
        if (!IncomingWorkflow.IsOperable(book.Status))
            throw new ValidationException(
                $"لا يمكن إحالة كتاب في حالة ({ArabicName(book.Status)}) — الإحالة متاحة للكتب (جديد) أو (قيد المراجعة) فقط.");

        var wantedIds = targets.Select(t => t.DepartmentId).Distinct().ToList();
        var depts = await db.Departments
            .Where(d => wantedIds.Contains(d.DepartmentId) && d.CompanyId == book.CompanyId)
            .ToListAsync(ct);

        // نتحقّق من **كل** الأقسام قبل تعديل أي شيء — إحالة نصفية أسوأ من رفض كامل.
        foreach (var wanted in wantedIds)
        {
            var d = depts.FirstOrDefault(x => x.DepartmentId == wanted)
                    ?? throw new ValidationException("أحد الأقسام المحدّدة غير موجود في هذه الشركة.");
            if (!d.IsActive)
                throw new ValidationException($"القسم «{d.Name}» معطّل — لا يمكن الإحالة إليه.");
        }

        var now = DateTime.UtcNow;
        var uid = current.UserId!.Value;
        var added = new List<string>();
        var general = generalNote?.Trim();

        foreach (var t in targets)
        {
            var dept = depts.First(d => d.DepartmentId == t.DepartmentId);
            var note = string.IsNullOrWhiteSpace(t.Note) ? null : t.Note!.Trim();

            var existing = book.Assignments.FirstOrDefault(a => a.DepartmentId == dept.DepartmentId);
            if (existing is not null)
            {
                existing.Note = note ?? existing.Note;   // إعادة إحالة = تحديث توجيه، لا تكرار
                existing.AssignedByUserId = uid;
                existing.AssignedAt = now;
            }
            else
            {
                book.Assignments.Add(new IncomingAssignment
                {
                    DepartmentId = dept.DepartmentId,
                    Note = note,
                    AssignedByUserId = uid,
                    AssignedAt = now,
                });
            }
            added.Add(dept.Name);

            // سطر سجلّ **لكل قسم**: من يقرأ المسار يحتاج توجيه كل قسم على حدة.
            var parts = new List<string> { $"أُحيل إلى ({dept.Name})" };
            if (note is not null) parts.Add($"ملاحظة القسم: {note}");
            if (!string.IsNullOrWhiteSpace(general)) parts.Add($"ملاحظة عامة: {general}");

            db.MovementLogs.Add(new MovementLog
            {
                CompanyId = book.CompanyId,
                IncomingId = book.IncomingId,
                Action = "Forwarded",
                Description = string.Join(". ", parts),
                ToDepartment = dept.Name,
                PerformedByUserId = uid,
                PerformedAt = now,
            });
        }

        if (book.Status == IncomingStatus.New)
            book.Status = IncomingStatus.InReview;  // الإحالة تنقل الجديد تلقائياً لقيد المراجعة
        book.LastAction = $"محال إلى {string.Join("، ", added)}";
        book.UpdatedAt = now;

        audit.Add("Forward", nameof(IncomingBook), id.ToString(), string.Join("، ", added), book.CompanyId);
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

    public async Task<List<MovementLogData>> GetMovementsAsync(int incomingId, CancellationToken ct = default)
    {
        // سجل الحركة يراه **كل من يستطيع إحالة الكتاب** (قرار المالك): من يقرّر الوجهة
        // التالية يحتاج أن يعرف أين مرّ الكتاب وما كُتب في ملاحظات الإحالات السابقة.
        // القارئ مستثنى لأنه لا يُحيل أصلاً — انظر EnsureCanForward.
        if (current.Role is UserRole.Reader)
            throw new ForbiddenException("لا تملك صلاحية رؤية سجل الحركة.");

        _ = await GetAsync(incomingId, ct); // تحقّق أمني: الكتاب ضمن شركة المستخدم ورؤيته

        var logs = await db.MovementLogs
            .Where(m => m.IncomingId == incomingId)
            .OrderBy(m => m.PerformedAt)
            .ToListAsync(ct);

        // Hint: جلب الأسماء دفعة واحدة بدل استعلام لكل حركة (تفادي N+1).
        // التجاوز المقصود للفلتر مشروح في UserNameAsync.
        var userIds = logs.Select(l => l.PerformedByUserId).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => userIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.FullName, ct);

        return logs
            .Select(l => new MovementLogData(l, names.TryGetValue(l.PerformedByUserId, out var n) ? n : "—"))
            .ToList();
    }

    // --- الوظائف المساعدة ----------------

    /// <summary>الاسم العربي للحالة (Hint: اختصار لـ IncomingWorkflow.ArabicName داخل هذا الملف).</summary>
    private static string ArabicName(IncomingStatus status) => IncomingWorkflow.ArabicName(status);

    /// <summary>
    /// اسم المستخدم للعرض.
    /// Hint: تجاوز مقصود لفلتر الشركة على المستخدمين — السوبر أدمن بلا CompanyId فيختفي اسمه
    /// وقت وجود شركة فعّالة. لا يُكشف سوى الاسم لمستخدم نفّذ إجراءً على كتاب يراه الطالب أصلاً.
    /// شرطة عند تعذّر الجلب: لا نُفشل عرض الكتاب بسبب اسم.
    /// </summary>
    private async Task<string> UserNameAsync(int userId, CancellationToken ct) =>
        await db.Users.IgnoreQueryFilters()
            .Where(u => u.UserId == userId)
            .Select(u => u.FullName)
            .FirstOrDefaultAsync(ct) ?? "—";

    /// <summary>
    /// صلاحية تعديل بيانات الكتاب.
    /// Hint: المؤرشف سجل نهائي لا يُعدَّل مطلقاً · المدير فأعلى يصحّح البيانات في بقية الحالات
    /// (الأخطاء تُكتشف غالباً بعد الإحالة) · الموظف يعدّل كتابه ما دام في حالة (جديد).
    /// </summary>
    private void EnsureEditable(IncomingBook book)
    {
        if (book.Status == IncomingStatus.Archived)
            throw new ValidationException("لا يمكن تعديل كتاب مؤرشف — الأرشفة نهائية.");

        var role = RequireAnyRole();
        if ((int)role <= (int)UserRole.Manager) return;   // المدير فأعلى

        if (book.Status != IncomingStatus.New)
            throw new ForbiddenException(
                $"صلاحيتك تسمح بالتعديل في حالة (جديد) فقط — الكتاب حالياً ({ArabicName(book.Status)}).");

        if (book.CreatedByUserId != current.UserId)
            throw new ForbiddenException("لا تملك صلاحية تعديل كتاب أنشأه غيرك.");
    }

    /// <summary>
    /// صلاحية الدور في تغيير الحالة.
    /// Hint: الأرشفة للمدير فأعلى دائماً. الموظف/القارئ يقتصر على «جديد ← قيد المراجعة»،
    ///       إلا من مُنح صلاحية CanManageIncoming فيستطيع كل الانتقالات عدا الأرشفة (نمط CanApprove للصادر).
    /// </summary>
    private void EnsureStatusChangePermission(IncomingStatus from, IncomingStatus to)
    {
        // الأرشفة **وفكّها** كلاهما للمدير فأعلى — والفكّ يفتح قفل التعديل على السجل
        // الرسمي، فلا يُترك لصلاحية «إدارة الوارد» التي تُمنح للموظفين.
        if (to == IncomingStatus.Archived || from == IncomingStatus.Archived)
        {
            RequireRole(UserRole.Manager);
            return;
        }

        var role = RequireAnyRole();
        if (role is UserRole.Employee or UserRole.Reader
            && !current.CanManageIncoming
            && !(from == IncomingStatus.New && to == IncomingStatus.InReview))
            throw new ForbiddenException(
                "صلاحيتك تسمح فقط بتحويل الكتاب (جديد) إلى (قيد المراجعة). لإدارة بقية الحالات تحتاج صلاحية «إدارة الوارد».");
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
