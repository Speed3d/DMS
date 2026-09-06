using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Tasks;

public sealed record CreateTaskInput(
    string Title, string? Description, DmsTaskType TaskType, DmsTaskPriority Priority,
    DateTime DueDate, DateTime? StartDate,
    int? DepartmentId, int? AssignedToUserId,
    int? RelatedIncomingId, int? RelatedOutgoingId,
    bool IsRecurring, DmsRecurrencePattern? RecurrencePattern, int? RecurrenceInterval,
    DateTime? RecurrenceEndDate, string? Notes, int? CompanyId = null);

public sealed record UpdateTaskInput(
    string Title, string? Description, DmsTaskPriority Priority,
    DateTime DueDate, DateTime? StartDate,
    int? DepartmentId, int? RelatedIncomingId, int? RelatedOutgoingId,
    string? Notes, string RowVersion);

public sealed record TaskFilters(
    DmsTaskStatus? Status = null, DmsTaskPriority? Priority = null,
    int? DepartmentId = null, int? AssignedToUserId = null, int? CreatedByUserId = null,
    DateTime? DueFrom = null, DateTime? DueTo = null,
    bool? IsOverdue = null, bool MineOnly = false, string? Search = null);

/// <summary>ملخّص المهام للوحة التحكم.</summary>
public sealed record TaskSummary(
    int Total, int Active, int Overdue, int DueToday, int CompletedThisMonth, int MineActive);

public interface ITaskService
{
    /// <summary>🔴 **مصدر الحقيقة الوحيد لقاعدة رؤية المهام** — يستدعيه غيرُه ولا ينسخه.</summary>
    IQueryable<DmsTask> Query();

    Task<(List<DmsTask> Items, int Total)> QueryAsync(
        TaskFilters filters, int page, int pageSize, CancellationToken ct = default);

    Task<DmsTask> GetByIdAsync(int id, CancellationToken ct = default);
    Task<List<DmsTaskUpdate>> GetUpdatesAsync(int id, CancellationToken ct = default);

    Task<DmsTask> CreateAsync(CreateTaskInput input, CancellationToken ct = default);
    Task<DmsTask> UpdateAsync(int id, UpdateTaskInput input, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);

    Task<DmsTask> ChangeStatusAsync(int id, DmsTaskStatus to, string? reason, CancellationToken ct = default);
    Task<DmsTask> UpdateProgressAsync(int id, int percent, string? comment, CancellationToken ct = default);
    Task<DmsTask> ReassignAsync(int id, int assignedToUserId, CancellationToken ct = default);
    Task<DmsTask> ReopenAsync(int id, string reason, CancellationToken ct = default);
    Task<DmsTaskUpdate> AddCommentAsync(int id, string text, CancellationToken ct = default);

    Task<List<DmsTask>> GetOverdueAsync(CancellationToken ct = default);
    Task<TaskSummary> GetSummaryAsync(CancellationToken ct = default);

    /// <summary>مَن يُشعَر بتغيّرٍ على هذه المهمة — تستعملها الدفعتان ٥ و٦.</summary>
    Task<List<int>> GetRecipientsAsync(DmsTask task, CancellationToken ct = default);

    /// <summary>مَن يصلح مسؤولاً عن مهمة في الشركة الفعّالة (لنموذج الإسناد).</summary>
    Task<List<User>> AssignableUsersAsync(CancellationToken ct = default);
}

/// <summary>
/// وحدة المهام (ADR-037) — كل منطق العمل هنا، والـcontroller عرضٌ رفيع.
/// </summary>
public sealed class TaskService(
    AppDbContext db, ICurrentUser current, INumberingService numbering, IAuditService audit)
    : ITaskService
{
    private const string CounterType = "Task";

    // ─────────────────────────── قاعدة الرؤية ───────────────────────────

    /// <inheritdoc/>
    /// <remarks>
    /// 🔴 **عامّة عمداً** ليستدعيها <c>AttachmentService</c> بدل أن يكتب قاعدة رؤيةٍ ثانية.
    /// وهذا بالضبط ما كلّف المستودع عيبَين حقيقيَّين: قاعدة رؤية الوارد كُتبت في موضعين
    /// فتباعدا (فمُنع موظف القسم من مرفقات كتابٍ يراه)، ثم تكرّر في الصادر مع ADR-030.
    ///
    /// ⚠️ **والقارئ لا يبلغ هنا أصلاً** — يُحجب في <c>[RequireGrantedModule]</c> قبل الخدمة،
    /// وفي <c>ResolveModules</c> قبل ذلك. فليس في هذه الدالّة فرعٌ له.
    ///
    /// ⚠️ **والفلتر العام يتكفّل بالشركة والحذف الناعم** — لا يُعاد شرطُهما هنا.
    /// </remarks>
    public IQueryable<DmsTask> Query()
    {
        var q = db.DmsTasks.AsQueryable();

        // المدير فأعلى: كل مهام الشركة — اتساقاً مع الصادر (ADR-030) والوارد (ADR-015).
        // وقاعدةُ رؤيةٍ ثالثةٌ مختلفة تُنسى وتتباعد.
        if (current.Role is UserRole.SuperAdmin or UserRole.President or UserRole.Manager)
            return q;

        // 🔴 **وصاحبُ `CanManageTasks` كذلك** — عيبٌ كشفه التشغيل الحيّ: العلَم يفتح
        //    **إعادة الإسناد وإدارة مهام الآخرين**، وقاعدةُ الرؤية كانت تحجب عنه تلك المهام
        //    فيردّ الخادم **404 على نقطةٍ يملكها**. علَمٌ يمنح إدارةً بلا الرؤية التي تُمارَس
        //    بها **علَمٌ بلا أثر** — وهي العائلة التي كلّفت المشروع ADR-028 وADR-036.
        //    ⚠️ وهو نظير `CanViewAllIncoming`: طريقُ منحٍ صريح يوازي طريق الدور.
        if (current.CanManageTasks) return q;

        var uid = current.UserId;
        var dept = current.DepartmentId;

        // مهامّه · ما أنشأه · ومهامّ قسمه (مهمة القسم يراها كل موظفيه ويحدّثونها).
        return q.Where(t => t.AssignedToUserId == uid
                         || t.CreatedByUserId == uid
                         || (dept != null && t.DepartmentId == dept));
    }

    public async Task<(List<DmsTask> Items, int Total)> QueryAsync(
        TaskFilters f, int page, int pageSize, CancellationToken ct = default)
    {
        var q = Query();

        if (f.Status is { } st) q = q.Where(t => t.Status == st);
        if (f.Priority is { } pr) q = q.Where(t => t.Priority == pr);
        if (f.DepartmentId is { } dep) q = q.Where(t => t.DepartmentId == dep);
        if (f.AssignedToUserId is { } asg) q = q.Where(t => t.AssignedToUserId == asg);
        if (f.CreatedByUserId is { } crt) q = q.Where(t => t.CreatedByUserId == crt);
        if (f.DueFrom is { } df) q = q.Where(t => t.DueDate >= df.Date);
        if (f.DueTo is { } dt) q = q.Where(t => t.DueDate <= dt.Date);
        if (f.MineOnly) q = q.Where(t => t.AssignedToUserId == current.UserId);

        if (!string.IsNullOrWhiteSpace(f.Search))
        {
            var s = f.Search.Trim();
            q = q.Where(t => t.Title.Contains(s)
                          || (t.Description != null && t.Description.Contains(s))
                          || (t.TaskNumber != null && t.TaskNumber.Contains(s)));
        }

        // ⚠️ **«متأخرة» محسوبةٌ لا مخزَّنة** — والشرط يُترجَم إلى SQL بحدَّيه: نشِطةٌ ومضى
        //    يومُها. لا يُستعمل `TaskWorkflow.IsOverdue` هنا لأن EF لا يترجم دالّةً عاديّة،
        //    والقاعدة **واحدة** في المجال ومرآتُها هنا صريحة.
        if (f.IsOverdue is { } ov)
        {
            var today = LocalClock.Today;
            q = ov
                ? q.Where(t => t.DueDate < today && TaskWorkflow.ActiveStatuses.Contains(t.Status))
                : q.Where(t => !(t.DueDate < today && TaskWorkflow.ActiveStatuses.Contains(t.Status)));
        }

        var total = await q.CountAsync(ct);

        var items = await q
            .Include(t => t.AssignedToUser)
            .Include(t => t.CreatedByUser)
            .Include(t => t.Department)
            .Include(t => t.RelatedIncoming)
            .Include(t => t.RelatedOutgoing)
            .OrderByDescending(t => t.Priority)
            .ThenBy(t => t.DueDate)
            .ThenByDescending(t => t.TaskId)
            .Skip((Math.Max(page, 1) - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task<DmsTask> GetByIdAsync(int id, CancellationToken ct = default)
        => await Query()
               .Include(t => t.AssignedToUser)
               .Include(t => t.CreatedByUser)
               .Include(t => t.Department)
               .Include(t => t.RelatedIncoming)
               .Include(t => t.RelatedOutgoing)
               .FirstOrDefaultAsync(t => t.TaskId == id, ct)
           ?? throw new NotFoundException("المهمة غير موجودة أو لا تملك صلاحية رؤيتها.");

    /// <inheritdoc/>
    /// <remarks>
    /// 🔴 **يُستعلَم عن الجدول مباشرةً لا عبر خاصية التنقّل** — فهي مفلترةٌ على الحذف الناعم،
    /// فيختفي السجلّ في اللحظة التي يصير فيها أهمَّ ما يُقرأ (درس ADR-028 وADR-034).
    /// والعزل باقٍ بفلتر <c>CompanyId</c> العام على <c>DmsTaskUpdates</c>.
    /// ⚠️ **والرؤية تُفحَص أولاً** عبر <see cref="GetByIdAsync"/>: سجلُّ مهمةٍ لا تراها لا يُقرأ.
    /// </remarks>
    public async Task<List<DmsTaskUpdate>> GetUpdatesAsync(int id, CancellationToken ct = default)
    {
        _ = await GetByIdAsync(id, ct);

        // 🔴 **بلا `Include(u => u.UpdatedByUser)`** — والسبب عيبٌ كشفه التشغيل الحيّ لا
        //    المراجعة: `UpdatedByUser` خاصيةٌ **إلزامية**، فيولّد لها EF **`INNER JOIN`** على
        //    `db.Users`، وعليه الفلتر العام الذي **يستبعد السوبر أدمن غير المُسنَد لشركة**.
        //    فقيدٌ كتبه السوبر أدمن (إعادة فتحٍ مثلاً) **يسقط كلُّه** — لقطتُه وسببُه وتاريخُه
        //    معه — لا اسمُ فاعله وحده.
        //
        //    ⚠️ **وهو ADR-034 بعينه** (سجلّ تعديلات الرواتب كان يعود فارغاً للسبب نفسه).
        //    وحارسُ «كل قيدٍ يحمل اسم فاعله» **لا يكشفه**: الصفّ لا يُفرَّغ بل يُحذف.
        //
        //    ⇒ السطور تُقرأ أولاً، ثم الأسماء **باستعلامٍ ثانٍ** بـ`IgnoreQueryFilters()`
        //    مقصورٍ على حقل الاسم. **والسطر يبقى ولو تعذّر اسم فاعله.**
        var rows = await db.DmsTaskUpdates
            .Where(u => u.TaskId == id)
            .OrderByDescending(u => u.UpdatedAt)
            .ThenByDescending(u => u.UpdateId)
            .ToListAsync(ct);

        if (rows.Count == 0) return rows;

        var actorIds = rows.Select(r => r.UpdatedByUserId).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => actorIds.Contains(u.UserId))
            .Select(u => new { u.UserId, u.FullName })
            .ToDictionaryAsync(x => x.UserId, x => x.FullName, ct);

        foreach (var r in rows)
            r.UpdatedByUser = new User { UserId = r.UpdatedByUserId, FullName = names.GetValueOrDefault(r.UpdatedByUserId, "—") };

        return rows;
    }

    // ─────────────────────────── الإنشاء ───────────────────────────

    public async Task<DmsTask> CreateAsync(CreateTaskInput input, CancellationToken ct = default)
    {
        RequireEmployeeOrAbove();
        var companyId = ResolveCompanyId(input.CompanyId);

        if (string.IsNullOrWhiteSpace(input.Title))
            throw new ValidationException("عنوان المهمة مطلوب.");

        // ⚠️ **الماضي مرفوضٌ عند الإنشاء ومقبولٌ عند التعديل**: مهمةٌ تُنشأ متأخرةً أصلاً خطأُ
        //    إدخالٍ غالباً، أمّا التعديل فقد يكون **تصحيحاً** لتاريخٍ أُدخل خطأً.
        if (input.DueDate.Date < LocalClock.Today)
            throw new ValidationException("لا يمكن أن يكون موعد التسليم في الماضي.");

        var (departmentId, assignedToUserId) =
            await ResolveAssignmentAsync(companyId, input.TaskType, input.DepartmentId, input.AssignedToUserId, ct);

        await ValidateLinksAsync(input.RelatedIncomingId, input.RelatedOutgoingId, ct);
        ValidateRecurrence(input.IsRecurring, input.RecurrencePattern, input.RecurrenceInterval,
            input.RecurrenceEndDate, input.DueDate);

        // معاملة الترقيم — **مُغلَّفة بـ`CreateExecutionStrategy`** إلزاماً لأن
        // `EnableRetryOnFailure` مُفعّل (قاعدة `rules/coding-standards.md`).
        var strategy = db.Database.CreateExecutionStrategy();
        DmsTask task = null!;

        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            var year = input.DueDate.Year;
            var serial = await numbering.NextSerialAsync(companyId, year, CounterType, ct);
            var company = await db.Companies.FindAsync([companyId], ct);

            task = new DmsTask
            {
                CompanyId = companyId,
                Year = year,
                SerialNo = serial,
                TaskNumber = $"{company!.Prefix}-TSK-{year}-{serial:D5}",
                Title = input.Title.Trim(),
                Description = input.Description?.Trim(),
                TaskType = input.TaskType,
                Priority = input.Priority,
                Status = DmsTaskStatus.New,
                ProgressPercent = 0,
                DueDate = LocalClock.CalendarDate(input.DueDate),
                StartDate = LocalClock.CalendarDate(input.StartDate),
                DepartmentId = departmentId,
                AssignedToUserId = assignedToUserId,
                CreatedByUserId = current.UserId!.Value,
                RelatedIncomingId = input.RelatedIncomingId,
                RelatedOutgoingId = input.RelatedOutgoingId,
                IsRecurring = input.IsRecurring,
                RecurrencePattern = input.IsRecurring ? input.RecurrencePattern : null,
                RecurrenceInterval = input.IsRecurring ? (input.RecurrenceInterval ?? 1) : null,
                RecurrenceEndDate = input.IsRecurring ? LocalClock.CalendarDate(input.RecurrenceEndDate) : null,
                Notes = input.Notes?.Trim(),
                CreatedAt = DateTime.UtcNow,
            };

            db.DmsTasks.Add(task);
            await db.SaveChangesAsync(ct);

            AddUpdate(task, DmsTaskUpdateType.Created, null, null, null,
                $"أُنشئت المهمة ({task.TaskNumber})");
            audit.Add("Create", nameof(DmsTask), task.TaskId.ToString(),
                $"إنشاء مهمة {task.TaskNumber}", companyId);

            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });

        return task;
    }

    // ─────────────────────────── التعديل ───────────────────────────

    public async Task<DmsTask> UpdateAsync(int id, UpdateTaskInput input, CancellationToken ct = default)
    {
        var task = await GetForWriteAsync(id, ct);
        RequireCanEdit(task);

        if (string.IsNullOrWhiteSpace(input.Title))
            throw new ValidationException("عنوان المهمة مطلوب.");

        SetRowVersion(task, input.RowVersion);

        // ⚠️ **القسم يُتحقَّق منه ولا يُقلَب نوعُ المهمة**: تحويل فرديةٍ إلى مهمة قسم يغيّر
        //    **مَن يراها** — قرارُ إسنادٍ لا تحريرُ حقل، فمكانه إعادةُ الإسناد لا التعديل العام.
        if (input.DepartmentId != task.DepartmentId)
        {
            if (task.TaskType == DmsTaskType.Department && input.DepartmentId is null)
                throw new ValidationException("مهمة القسم لا تكون بلا قسم.");
            if (input.DepartmentId is { } d) await EnsureDepartmentAsync(task.CompanyId, d, ct);
        }

        await ValidateLinksAsync(input.RelatedIncomingId, input.RelatedOutgoingId, ct);

        var changes = new List<string>();
        if (task.Title != input.Title.Trim()) changes.Add("العنوان");
        if (task.Priority != input.Priority)
            changes.Add($"الأولوية ({TaskWorkflow.ArabicName(task.Priority)} ← {TaskWorkflow.ArabicName(input.Priority)})");
        if (task.DueDate.Date != input.DueDate.Date)
            changes.Add($"الموعد ({task.DueDate:yyyy-MM-dd} ← {input.DueDate:yyyy-MM-dd})");
        if (task.DepartmentId != input.DepartmentId) changes.Add("القسم");

        var oldPriority = task.Priority;
        var oldDue = task.DueDate;

        task.Title = input.Title.Trim();
        task.Description = input.Description?.Trim();
        task.Priority = input.Priority;
        task.DueDate = LocalClock.CalendarDate(input.DueDate);
        task.StartDate = LocalClock.CalendarDate(input.StartDate);
        task.DepartmentId = input.DepartmentId;
        task.RelatedIncomingId = input.RelatedIncomingId;
        task.RelatedOutgoingId = input.RelatedOutgoingId;
        task.Notes = input.Notes?.Trim();
        task.UpdatedAt = DateTime.UtcNow;

        // 🔴 **تأجيل الموعد يُصفّر ذاكرة التصعيد**: مهمةٌ صُعِّدت ثم مُدّد موعدها ليست متأخرةً
        //    بعد، وإبقاءُ المستوى يمنع تصعيدها ثانيةً لو تأخّرت فعلاً بعد التمديد.
        if (input.DueDate.Date > oldDue.Date) ResetEscalation(task);

        // أعلامٌ منفصلة لتغييرَين يقرأهما المستخدم بذاتهما لا ضمن «عُدّلت».
        if (oldPriority != input.Priority)
            AddUpdate(task, DmsTaskUpdateType.PriorityChange,
                TaskWorkflow.ArabicName(oldPriority), TaskWorkflow.ArabicName(input.Priority), null,
                $"تغيّرت الأولوية من ({TaskWorkflow.ArabicName(oldPriority)}) إلى ({TaskWorkflow.ArabicName(input.Priority)})");

        if (oldDue.Date != input.DueDate.Date)
            AddUpdate(task, DmsTaskUpdateType.DueDateChange,
                oldDue.ToString("yyyy-MM-dd"), input.DueDate.ToString("yyyy-MM-dd"), null,
                $"تغيّر موعد التسليم من {oldDue:yyyy-MM-dd} إلى {input.DueDate:yyyy-MM-dd}");

        if (changes.Count > 0)
            AddUpdate(task, DmsTaskUpdateType.Edited, null, null, null,
                $"عُدِّلت المهمة: {string.Join(" · ", changes)}");

        audit.Add("Update", nameof(DmsTask), task.TaskId.ToString(), null, task.CompanyId);
        await SaveGuardedAsync(ct);
        return task;
    }

    public async Task DeleteAsync(int id, CancellationToken ct = default)
    {
        var task = await GetForWriteAsync(id, ct);
        RequireCanEdit(task);

        // ⚠️ **حذف ناعم دائماً** (قاعدة المشروع) — والسجلّ يبقى مقروءاً بعده لأن
        //    `DmsTaskUpdates` بلا فلتر حذفٍ ناعم ويُستعلَم عنه مباشرةً.
        task.IsDeleted = true;
        task.DeletedByUserId = current.UserId;
        task.DeletedAt = DateTime.UtcNow;

        audit.Add("Delete", nameof(DmsTask), task.TaskId.ToString(),
            $"حذف مهمة {task.TaskNumber}", task.CompanyId);
        await SaveGuardedAsync(ct);
    }

    // ─────────────────────────── الحالة والتقدّم ───────────────────────────

    public async Task<DmsTask> ChangeStatusAsync(
        int id, DmsTaskStatus to, string? reason, CancellationToken ct = default)
    {
        var task = await GetForWriteAsync(id, ct);
        RequireCanWork(task);

        // ⚠️ **إعادة الفتح لا تمرّ من هنا**: لها حارسها (المدير فأعلى + سبب إلزامي).
        if (to == DmsTaskStatus.Reopened)
            throw new ValidationException("إعادة الفتح تتم من إجرائها الخاصّ بسببٍ إلزامي.");

        TaskWorkflow.EnsureTransitionAllowed(task.Status, to);

        var from = task.Status;
        task.Status = to;
        task.UpdatedAt = DateTime.UtcNow;

        // البدء يُسجَّل مرّةً واحدة — إعادةُ الاستئناف بعد تعليقٍ لا تُزيح تاريخ البدء.
        if (to == DmsTaskStatus.InProgress && task.StartDate is null)
            task.StartDate = LocalClock.Today;

        if (to == DmsTaskStatus.Completed)
        {
            task.CompletedDate = LocalClock.Today;
            // 🔴 **المكتملة لا تُصعَّد** — وذاكرةُ التصعيد تُصفَّر لتكون إعادةُ الفتح بدايةً نظيفة.
            ResetEscalation(task);
        }

        if (to == DmsTaskStatus.Cancelled) ResetEscalation(task);

        var desc = $"تغيّرت الحالة من ({TaskWorkflow.ArabicName(from)}) إلى ({TaskWorkflow.ArabicName(to)})";
        if (!string.IsNullOrWhiteSpace(reason)) desc += $" — {reason.Trim()}";

        AddUpdate(task, DmsTaskUpdateType.StatusChange,
            TaskWorkflow.ArabicName(from), TaskWorkflow.ArabicName(to), reason?.Trim(), desc);

        audit.Add("ChangeStatus", nameof(DmsTask), task.TaskId.ToString(), desc, task.CompanyId);
        await SaveGuardedAsync(ct);
        return task;
    }

    public async Task<DmsTask> UpdateProgressAsync(
        int id, int percent, string? comment, CancellationToken ct = default)
    {
        if (percent is < 0 or > 100)
            throw new ValidationException("نسبة الإنجاز يجب أن تكون بين 0 و100.");

        var task = await GetForWriteAsync(id, ct);
        RequireCanWork(task);

        if (!TaskWorkflow.IsActive(task.Status))
            throw new ValidationException(
                $"لا يمكن تحديث نسبة الإنجاز لمهمة في حالة ({TaskWorkflow.ArabicName(task.Status)}).");

        var old = task.ProgressPercent;
        task.ProgressPercent = percent;
        task.UpdatedAt = DateTime.UtcNow;

        // 🔴 **100% لا تُكمل المهمة تلقائياً** — الإكمال قرارٌ يُتّخذ صراحةً وله أثرٌ في
        //    التقرير وفي التصعيد. واشتقاقُ حالةٍ من رقمٍ يجعل نصفَ الحقيقة حكماً.
        var desc = $"تحدّثت نسبة الإنجاز من {old}% إلى {percent}%";
        if (!string.IsNullOrWhiteSpace(comment)) desc += $" — {comment.Trim()}";

        AddUpdate(task, DmsTaskUpdateType.ProgressUpdate,
            $"{old}%", $"{percent}%", comment?.Trim(), desc);

        await SaveGuardedAsync(ct);
        return task;
    }

    public async Task<DmsTask> ReassignAsync(int id, int assignedToUserId, CancellationToken ct = default)
    {
        if (!current.CanManageTasks)
            throw new ForbiddenException("لا تملك صلاحية إسناد المهام لغيرك.");

        var task = await GetForWriteAsync(id, ct);

        if (!TaskWorkflow.IsActive(task.Status))
            throw new ValidationException(
                $"لا يمكن إسناد مهمة في حالة ({TaskWorkflow.ArabicName(task.Status)}).");

        var target = await EnsureAssignableAsync(task.CompanyId, assignedToUserId, ct);
        var oldName = await UserNameAsync(task.AssignedToUserId, ct);

        task.AssignedToUserId = assignedToUserId;
        task.UpdatedAt = DateTime.UtcNow;

        // 🔴 **الإسناد الجديد يُصفّر ذاكرة التصعيد**: المسؤول الجديد لم يتأخّر بعد، وإبقاءُ
        //    المستوى يعني أن أول تصعيدٍ يقع عليه يذهب مباشرةً إلى الرئاسة.
        ResetEscalation(task);

        var desc = $"أُسندت المهمة من ({oldName}) إلى ({target.FullName})";
        AddUpdate(task, DmsTaskUpdateType.Reassign, oldName, target.FullName, null, desc);
        audit.Add("Reassign", nameof(DmsTask), task.TaskId.ToString(), desc, task.CompanyId);

        await SaveGuardedAsync(ct);
        return task;
    }

    public async Task<DmsTask> ReopenAsync(int id, string reason, CancellationToken ct = default)
    {
        // ⚠️ **المدير فأعلى** — إعادةُ الفتح تنقض إنجازاً مُعلَناً، فهي أقربُ إلى فكّ الأرشفة
        //    منها إلى تحديث حقل (سابقة ADR-021: حارسٌ مضاعف بالدور والسبب).
        RequireRole(UserRole.Manager);

        if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length < 5)
            throw new ValidationException("سبب إعادة الفتح مطلوب (٥ أحرف فأكثر).");

        var task = await GetForWriteAsync(id, ct);
        TaskWorkflow.EnsureTransitionAllowed(task.Status, DmsTaskStatus.Reopened);

        task.Status = DmsTaskStatus.Reopened;
        task.CompletedDate = null;
        task.UpdatedAt = DateTime.UtcNow;

        // 🔴 **وأعمدة التصعيد الثلاثة تُصفَّر**: المهمة تبدأ دورةً جديدة، ولو بقيت الذاكرة
        //    لما صُعِّدت ثانيةً مهما تأخّرت — وهو صمتٌ في الموضع الذي يجب أن يُنبَّه فيه.
        ResetEscalation(task);

        var desc = $"أُعيد فتح المهمة — {reason.Trim()}";
        AddUpdate(task, DmsTaskUpdateType.Reopen, TaskWorkflow.ArabicName(DmsTaskStatus.Completed),
            TaskWorkflow.ArabicName(DmsTaskStatus.Reopened), reason.Trim(), desc);
        audit.Add("Reopen", nameof(DmsTask), task.TaskId.ToString(), desc, task.CompanyId);

        await SaveGuardedAsync(ct);
        return task;
    }

    public async Task<DmsTaskUpdate> AddCommentAsync(int id, string text, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(text))
            throw new ValidationException("نصّ التعليق مطلوب.");

        var task = await GetForWriteAsync(id, ct);
        RequireCanWork(task);

        var row = AddUpdate(task, DmsTaskUpdateType.Comment, null, null, text.Trim(),
            $"علّق: {text.Trim()}");

        await db.SaveChangesAsync(ct);
        return row;
    }

    // ─────────────────────────── قراءات مشتقّة ───────────────────────────

    public async Task<List<DmsTask>> GetOverdueAsync(CancellationToken ct = default)
    {
        var today = LocalClock.Today;
        return await Query()
            .Include(t => t.AssignedToUser)
            .Include(t => t.Department)
            .Where(t => t.DueDate < today && TaskWorkflow.ActiveStatuses.Contains(t.Status))
            .OrderBy(t => t.DueDate)
            .ToListAsync(ct);
    }

    public async Task<TaskSummary> GetSummaryAsync(CancellationToken ct = default)
    {
        var today = LocalClock.Today;
        var monthStart = new DateTime(today.Year, today.Month, 1);
        var q = Query();

        return new TaskSummary(
            Total: await q.CountAsync(ct),
            Active: await q.CountAsync(t => TaskWorkflow.ActiveStatuses.Contains(t.Status), ct),
            Overdue: await q.CountAsync(t => t.DueDate < today && TaskWorkflow.ActiveStatuses.Contains(t.Status), ct),
            DueToday: await q.CountAsync(t => t.DueDate == today && TaskWorkflow.ActiveStatuses.Contains(t.Status), ct),
            CompletedThisMonth: await q.CountAsync(
                t => t.Status == DmsTaskStatus.Completed && t.CompletedDate >= monthStart, ct),
            MineActive: await q.CountAsync(
                t => t.AssignedToUserId == current.UserId && TaskWorkflow.ActiveStatuses.Contains(t.Status), ct));
    }

    /// <inheritdoc/>
    /// <remarks>
    /// المسؤول · المُنشئ · وكل موظفي القسم إن كانت مهمة قسم — **بلا تكرار وبلا الفاعل نفسه**
    /// (لا يُشعَر أحدٌ بفعلِ نفسه).
    /// </remarks>
    public async Task<List<int>> GetRecipientsAsync(DmsTask task, CancellationToken ct = default)
    {
        var ids = new HashSet<int>();
        if (task.AssignedToUserId is { } a) ids.Add(a);
        ids.Add(task.CreatedByUserId);

        if (task.TaskType == DmsTaskType.Department && task.DepartmentId is { } dep)
        {
            var members = await db.UserCompanies
                .Where(uc => uc.CompanyId == task.CompanyId && uc.DepartmentId == dep)
                .Select(uc => uc.UserId)
                .ToListAsync(ct);
            foreach (var m in members) ids.Add(m);
        }

        if (current.UserId is { } me) ids.Remove(me);
        return ids.ToList();
    }

    public async Task<List<User>> AssignableUsersAsync(CancellationToken ct = default)
    {
        if (!current.CanManageTasks)
            throw new ForbiddenException("لا تملك صلاحية إسناد المهام لغيرك.");

        var companyId = ResolveCompanyId(null);

        // 🔐 **القارئ خارج القائمة**: لا يرى الوحدة أصلاً، فإسنادُ مهمةٍ إليه يخلق عملاً
        //    لا يبلغه صاحبُه — والفلتر العام على `Users` يتكفّل بحدود الشركة.
        return await db.Users
            .Where(u => u.IsActive
                     && u.Role != UserRole.Reader
                     && u.AssignedCompanies.Any(c => c.CompanyId == companyId))
            .OrderBy(u => u.Role).ThenBy(u => u.FullName)
            .ToListAsync(ct);
    }

    // ─────────────────────────── مساعدات ───────────────────────────

    /// <summary>يجلب المهمة **بقاعدة الرؤية نفسها** بلا `Include` — للكتابة.</summary>
    private async Task<DmsTask> GetForWriteAsync(int id, CancellationToken ct)
        => await Query().FirstOrDefaultAsync(t => t.TaskId == id, ct)
           ?? throw new NotFoundException("المهمة غير موجودة أو لا تملك صلاحية رؤيتها.");

    /// <summary>مَن يعدّل بيانات المهمة نفسها: مُنشئها، أو صاحبُ علَم الإدارة، أو المدير فأعلى.</summary>
    private void RequireCanEdit(DmsTask task)
    {
        if (current.CanManageTasks) return;
        if (RoleHierarchy.IsManagerOrAbove(current.Role ?? UserRole.Reader)) return;
        if (task.CreatedByUserId == current.UserId) return;

        throw new ForbiddenException("لا تملك صلاحية تعديل هذه المهمة.");
    }

    /// <summary>
    /// مَن يعمل على المهمة (حالة · نسبة · تعليق): كلُّ من يراها.
    /// </summary>
    /// <remarks>
    /// ⚠️ **أوسعُ من <see cref="RequireCanEdit"/> عمداً**: مهمةُ القسم يحدّثها كل موظفيه
    /// (قرار المالك)، والرؤيةُ هنا **هي** الصلاحية — و<see cref="Query"/> ضمنها أصلاً.
    /// </remarks>
    private void RequireCanWork(DmsTask task)
    {
        _ = task;
        RequireEmployeeOrAbove();
    }

    /// <summary>يضبط <c>RowVersion</c> الأصلي ليكشف EF أي كتابةٍ فوق عمل الآخرين.</summary>
    private void SetRowVersion(DmsTask task, string? rowVersion)
    {
        if (string.IsNullOrWhiteSpace(rowVersion)) return;

        // ⚠️ **نصٌّ base64 لا مصفوفةُ أرقام** — `byte[]` يُسلسَل نصّاً في ASP.NET Core،
        //    وقراءتُه `List<int>` في العميل أسقطت شاشةً كاملة في وحدة الرواتب.
        byte[] bytes;
        try { bytes = Convert.FromBase64String(rowVersion); }
        catch (FormatException) { throw new ValidationException("طابع الإصدار غير صالح."); }

        db.Entry(task).Property(t => t.RowVersion).OriginalValue = bytes;
    }

    private async Task SaveGuardedAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException)
        {
            throw new ConflictException("عُدّلت المهمة من مستخدم آخر — أعد التحميل وحاول مجدداً.");
        }
    }

    private DmsTaskUpdate AddUpdate(
        DmsTask task, DmsTaskUpdateType type,
        string? oldValue, string? newValue, string? comment, string description)
    {
        var row = new DmsTaskUpdate
        {
            TaskId = task.TaskId,
            CompanyId = task.CompanyId,
            UpdateType = type,
            OldValue = Trim(oldValue, 500),
            NewValue = Trim(newValue, 500),
            Comment = Trim(comment, 2000),
            Description = Trim(description, 1000)!,
            UpdatedByUserId = current.UserId!.Value,
            UpdatedAt = DateTime.UtcNow,
        };
        db.DmsTaskUpdates.Add(row);
        return row;
    }

    private static string? Trim(string? s, int max)
        => s is null ? null : (s.Length <= max ? s : s[..max]);

    /// <summary>يُصفّر **ذاكرة الإشعار** لا الحالة — العمودان ليسا حالةَ المهمة.</summary>
    private static void ResetEscalation(DmsTask task)
    {
        task.LastEscalationLevel = 0;
        task.LastEscalatedAt = null;
        task.DueSoonNotifiedAt = null;
    }

    /// <summary>
    /// يحسم القسم والمسؤول — **وقلبُه قاعدةُ الإسناد القسري**.
    /// </summary>
    /// <remarks>
    /// 🔴 **بلا <c>CanManageTasks</c> يُسنَد المستخدم لنفسه قسراً، ولا يُرفض الطلب.** والفرق
    /// مقصود: الرفض يجعل النموذج يفشل بلا سبب مفهوم لمن لا يعرف أنه لا يملك العلَم، والقسر
    /// ينتج **مهمةً صحيحة** هي بالضبط ما يستطيعه — «الموظف يُنشئ لنفسه» (قرار المالك).
    /// </remarks>
    private async Task<(int? DepartmentId, int? AssignedToUserId)> ResolveAssignmentAsync(
        int companyId, DmsTaskType type, int? departmentId, int? assignedToUserId, CancellationToken ct)
    {
        if (type == DmsTaskType.Department)
        {
            if (departmentId is not { } dep)
                throw new ValidationException("مهمة القسم تحتاج تحديد القسم.");
            await EnsureDepartmentAsync(companyId, dep, ct);
        }
        else
        {
            departmentId = null;   // مهمةٌ فردية لا تحمل قسماً — وإلا رآها القسم كلُّه.
        }

        if (!current.CanManageTasks)
            return (departmentId, current.UserId);

        if (assignedToUserId is { } uid)
        {
            await EnsureAssignableAsync(companyId, uid, ct);
            return (departmentId, uid);
        }

        // مهمة قسمٍ بلا مسؤولٍ بعينه: مسموحة — القسم كلُّه مسؤول.
        return (departmentId, type == DmsTaskType.Department ? null : current.UserId);
    }

    private async Task EnsureDepartmentAsync(int companyId, int departmentId, CancellationToken ct)
    {
        if (!await db.Departments.AnyAsync(d => d.DepartmentId == departmentId && d.CompanyId == companyId, ct))
            throw new ValidationException("القسم غير موجود في هذه الشركة.");
    }

    private async Task<User> EnsureAssignableAsync(int companyId, int userId, CancellationToken ct)
    {
        var user = await db.Users
            .FirstOrDefaultAsync(u => u.UserId == userId
                                   && u.IsActive
                                   && u.AssignedCompanies.Any(c => c.CompanyId == companyId), ct)
            ?? throw new ValidationException("المستخدم غير موجود في هذه الشركة أو غير مفعّل.");

        // 🔐 القارئ محجوبٌ عن الوحدة، فإسنادُ مهمةٍ إليه يخلق عملاً لا يبلغه صاحبُه.
        if (user.Role == UserRole.Reader)
            throw new ValidationException("لا تُسنَد المهام لدور القارئ — لا يرى وحدة المهام.");

        return user;
    }

    /// <summary>
    /// يتحقّق من الكتابين المرتبطين — **والفلتر العام يكفي لحدّ الشركة**.
    /// </summary>
    private async Task ValidateLinksAsync(int? incomingId, int? outgoingId, CancellationToken ct)
    {
        if (incomingId is { } inc && !await db.IncomingBooks.AnyAsync(b => b.IncomingId == inc, ct))
            throw new NotFoundException("الكتاب الوارد المرتبط غير موجود.");

        if (outgoingId is { } outg && !await db.OutgoingBooks.AnyAsync(b => b.OutgoingId == outg, ct))
            throw new NotFoundException("الكتاب الصادر المرتبط غير موجود.");
    }

    private static void ValidateRecurrence(
        bool isRecurring, DmsRecurrencePattern? pattern, int? interval,
        DateTime? endDate, DateTime dueDate)
    {
        if (!isRecurring) return;

        if (pattern is null)
            throw new ValidationException("نمط التكرار مطلوب للمهمة المتكررة.");

        if (interval is { } i && i < 1)
            throw new ValidationException("فاصل التكرار يجب أن يكون 1 فأكثر.");

        if (endDate is { } e && e.Date < dueDate.Date)
            throw new ValidationException("نهاية التكرار قبل موعد المهمة الأولى.");
    }

    private async Task<string> UserNameAsync(int? userId, CancellationToken ct)
    {
        if (userId is not { } id) return "غير مُسنَدة";

        // ⚠️ **`IgnoreQueryFilters` على حقل الاسم وحده** (نمط ADR-031/034): الفلتر العام على
        //    `Users` يستبعد السوبر أدمن بلا شركة، فربطٌ داخليّ عليه **يمحو السطر لا الاسم**.
        var name = await db.Users.IgnoreQueryFilters()
            .Where(u => u.UserId == id).Select(u => u.FullName).FirstOrDefaultAsync(ct);
        return name ?? "—";
    }

    private int ResolveCompanyId(int? requested)
    {
        if (current.ActiveCompanyId is not null) return current.ActiveCompanyId.Value;
        if (current.IsSuperAdmin && requested is not null) return requested.Value;
        throw new ValidationException("تعذّر تحديد الشركة. حدّد الشركة الفعّالة.");
    }

    private void RequireEmployeeOrAbove()
    {
        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if (!RoleHierarchy.IsEmployeeOrAbove(role))
            throw new ForbiddenException("المهام غير متاحة لدور القارئ.");
    }

    private void RequireRole(UserRole minimumOrHigher)
    {
        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if ((int)role > (int)minimumOrHigher)
            throw new ForbiddenException("صلاحيتك لا تسمح بهذه العملية.");
    }
}
