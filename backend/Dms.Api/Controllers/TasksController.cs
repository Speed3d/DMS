using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

/// <summary>
/// وحدة المهام (ADR-037). <see cref="RequireGrantedModuleAttribute"/> يفرض **القسم + دورٌ فوق
/// القارئ**، ومنطق العمل كلُّه في <see cref="ITaskService"/> — هذا عرضٌ رفيع.
/// </summary>
[ApiController]
[Route("api/tasks")]
[Authorize]
[RequireGrantedModule(AppModule.Tasks)]
public sealed class TasksController(
    ITaskService tasks, IAttachmentService attachmentService,
    ITaskJobRunner jobs, IWebHostEnvironment env) : ControllerBase
{
    /// <summary>
    /// يُشغّل دورة المهام الخلفية **مرّةً واحدة** — للتحقّق لا للتشغيل.
    /// </summary>
    /// <remarks>
    /// 🔴 **حارسان لا واحد: السوبر أدمن وحده، وبيئة التطوير وحدها** (سابقة
    /// <c>reset-db</c> حرفياً). فنقطةٌ تُطلق التصعيد يدوياً في الإنتاج تعني **إشعاراتٍ
    /// تُرسَل بأمرِ من يضغط** لا بحلول موعدها.
    ///
    /// ⚠️ **ولماذا أصلاً؟** لأن «انتظر ساعةً ثم تحقّق» **ليست خطة تحقّق**: لا تُعاد ولا
    /// تُدرَج في سكربت، والدورة التي لا تُختبَر تُكتشف أخطاؤها في الإنتاج.
    /// </remarks>
    [HttpPost("run-jobs")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<ActionResult<TaskJobResult>> RunJobs(
        [FromQuery] bool purge = false, CancellationToken ct = default)
    {
        if (!env.IsDevelopment())
            throw new ForbiddenException("تشغيل الدورة يدوياً غير متاح في بيئة الإنتاج.");

        return await jobs.RunOnceAsync(purge, ct);
    }

    // ─────────────────────────── قراءة ───────────────────────────

    [HttpGet]
    public async Task<ActionResult<TaskListResponse>> List(
        [FromQuery] DmsTaskStatus? status, [FromQuery] DmsTaskPriority? priority,
        [FromQuery] int? departmentId, [FromQuery] int? assignedTo, [FromQuery] int? createdBy,
        [FromQuery] DateTime? dueFrom, [FromQuery] DateTime? dueTo,
        [FromQuery] bool? isOverdue, [FromQuery] bool mineOnly = false,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
        CancellationToken ct = default)
    {
        var filters = new TaskFilters(status, priority, departmentId, assignedTo, createdBy,
            dueFrom, dueTo, isOverdue, mineOnly, search);

        var (items, total) = await tasks.QueryAsync(
            filters, Math.Max(page, 1), Math.Clamp(pageSize, 1, 200), ct);

        // عدد المرفقات لكل مهمة — **استعلامٌ واحد** لا واحدٌ لكل صفّ.
        var counts = await attachmentService.CountByOwnersAsync(
            OwnerType.Task, items.Select(t => t.TaskId).ToList(), ct);

        return new TaskListResponse(
            items.Select(t => MapListItem(t, counts.GetValueOrDefault(t.TaskId))).ToList(),
            total, Math.Max(page, 1), Math.Clamp(pageSize, 1, 200));
    }

    [HttpGet("my")]
    public async Task<ActionResult<TaskListResponse>> Mine(
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default)
        => await List(null, null, null, null, null, null, null, null, true, null, page, pageSize, ct);

    [HttpGet("overdue")]
    public async Task<ActionResult<List<TaskListItemResponse>>> Overdue(CancellationToken ct)
    {
        var items = await tasks.GetOverdueAsync(ct);
        var counts = await attachmentService.CountByOwnersAsync(
            OwnerType.Task, items.Select(t => t.TaskId).ToList(), ct);
        return items.Select(t => MapListItem(t, counts.GetValueOrDefault(t.TaskId))).ToList();
    }

    [HttpGet("summary")]
    public async Task<ActionResult<TaskSummaryResponse>> Summary(CancellationToken ct)
    {
        var s = await tasks.GetSummaryAsync(ct);
        return new TaskSummaryResponse(
            s.Total, s.Active, s.Overdue, s.DueToday, s.CompletedThisMonth, s.MineActive);
    }

    /// <summary>مَن يصلح مسؤولاً — للنموذج. مقصورٌ على صاحب <c>CanManageTasks</c>.</summary>
    [HttpGet("assignable-users")]
    public async Task<ActionResult<List<AssignableUserResponse>>> AssignableUsers(CancellationToken ct)
        => (await tasks.AssignableUsersAsync(ct))
            .Select(u => new AssignableUserResponse(u.UserId, u.FullName, u.Username, u.Role))
            .ToList();

    [HttpGet("{id:int}")]
    public async Task<ActionResult<TaskResponse>> Get(int id, CancellationToken ct)
        => Map(await tasks.GetByIdAsync(id, ct));

    [HttpGet("{id:int}/updates")]
    public async Task<ActionResult<List<TaskUpdateResponse>>> Updates(int id, CancellationToken ct)
        => (await tasks.GetUpdatesAsync(id, ct)).Select(MapUpdate).ToList();

    // ─────────────────────────── كتابة ───────────────────────────

    [HttpPost]
    public async Task<ActionResult<TaskResponse>> Create(CreateTaskRequest r, CancellationToken ct)
    {
        var input = new CreateTaskInput(
            r.Title, r.Description, r.TaskType, r.Priority, r.DueDate, r.StartDate,
            r.DepartmentId, r.AssignedToUserId, r.RelatedIncomingId, r.RelatedOutgoingId,
            r.IsRecurring, r.RecurrencePattern, r.RecurrenceInterval, r.RecurrenceEndDate,
            r.Notes, r.CompanyId);

        var created = await tasks.CreateAsync(input, ct);

        // يُعاد جلبها بالـ`Include` ليصل العميلَ **كلُّ حقلٍ مشتقّ** لا معرّفاتٌ عارية.
        return Map(await tasks.GetByIdAsync(created.TaskId, ct));
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<TaskResponse>> Update(int id, UpdateTaskRequest r, CancellationToken ct)
    {
        var input = new UpdateTaskInput(
            r.Title, r.Description, r.Priority, r.DueDate, r.StartDate,
            r.DepartmentId, r.RelatedIncomingId, r.RelatedOutgoingId, r.Notes, r.RowVersion,
            r.Reason);

        await tasks.UpdateAsync(id, input, ct);
        return Map(await tasks.GetByIdAsync(id, ct));
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await tasks.DeleteAsync(id, ct);
        return NoContent();
    }

    [HttpPost("{id:int}/status")]
    public async Task<ActionResult<TaskResponse>> ChangeStatus(
        int id, ChangeTaskStatusRequest r, CancellationToken ct)
    {
        await tasks.ChangeStatusAsync(id, r.NewStatus, r.Reason, ct);
        return Map(await tasks.GetByIdAsync(id, ct));
    }

    [HttpPost("{id:int}/progress")]
    public async Task<ActionResult<TaskResponse>> Progress(
        int id, TaskProgressRequest r, CancellationToken ct)
    {
        await tasks.UpdateProgressAsync(id, r.Percent, r.Comment, r.Reason, ct);
        return Map(await tasks.GetByIdAsync(id, ct));
    }

    [HttpPost("{id:int}/reassign")]
    public async Task<ActionResult<TaskResponse>> Reassign(
        int id, ReassignTaskRequest r, CancellationToken ct)
    {
        await tasks.ReassignAsync(id, r.AssignedToUserId, r.KeepPreviousAsParticipant, ct);
        return Map(await tasks.GetByIdAsync(id, ct));
    }

    // ── المشاركون: مَن يرى المهمة غير مسؤولها (ADR-037) ──

    [HttpGet("{id:int}/participants")]
    public async Task<ActionResult<List<TaskParticipantResponse>>> Participants(
        int id, CancellationToken ct)
        => (await tasks.GetParticipantsAsync(id, ct)).Select(MapParticipant).ToList();

    [HttpPost("{id:int}/participants")]
    public async Task<ActionResult<List<TaskParticipantResponse>>> AddParticipant(
        int id, AddParticipantRequest r, CancellationToken ct)
    {
        await tasks.AddParticipantAsync(id, r.UserId, r.DepartmentId, r.Note, ct);
        return (await tasks.GetParticipantsAsync(id, ct)).Select(MapParticipant).ToList();
    }

    [HttpDelete("{id:int}/participants/{participantId:int}")]
    public async Task<IActionResult> RemoveParticipant(
        int id, int participantId, CancellationToken ct)
    {
        await tasks.RemoveParticipantAsync(id, participantId, ct);
        return NoContent();
    }

    [HttpPost("{id:int}/reopen")]
    public async Task<ActionResult<TaskResponse>> Reopen(
        int id, ReopenTaskRequest r, CancellationToken ct)
    {
        await tasks.ReopenAsync(id, r.Reason, ct);
        return Map(await tasks.GetByIdAsync(id, ct));
    }

    [HttpPost("{id:int}/comment")]
    public async Task<ActionResult<TaskUpdateResponse>> Comment(
        int id, TaskCommentRequest r, CancellationToken ct)
        => MapUpdate(await tasks.AddCommentAsync(id, r.Text, ct));

    // ─────────────────────────── المرفقات ───────────────────────────
    // نمط `EmployeesController` نفسه: الوصول والصلاحية يُفحصان داخل `AttachmentService`،
    // وهو يستدعي `ITaskService.Query()` **ولا ينسخ قاعدة الرؤية**.

    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> Attachments(int id, CancellationToken ct)
        => (await attachmentService.ListAsync(OwnerType.Task, id, ct))
            .Select(a => new AttachmentResponse(
                a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt))
            .ToList();

    [HttpPost("{id:int}/attachments")]
    public async Task<ActionResult<AttachmentResponse>> UploadAttachment(
        int id, IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) throw new ValidationException("الملف مطلوب.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var att = await attachmentService.AddAsync(OwnerType.Task, id, file.FileName, ms.ToArray(), ct);
        return new AttachmentResponse(
            att.AttachmentId, att.FileName, att.FileType, att.FileSize, att.UploadedAt);
    }

    [HttpGet("{id:int}/attachments/{attachmentId:int}/download")]
    public async Task<IActionResult> DownloadAttachment(
        int id, int attachmentId, bool inline, CancellationToken ct)
    {
        var (meta, content) = await attachmentService.GetAsync(attachmentId, ct);

        // ⚠️ `inline=true` ⇒ النوع الحقيقي وبلا اسم ملف، وإلا صارت الاستجابة «تنزيلاً»
        //    فيختطفها مدير التحميل ولا تُعرض (مبدأ ADR-019).
        if (inline) return File(content, MimeTypes.For(meta.FileName));
        return File(content, "application/octet-stream", meta.FileName);
    }

    // ─────────────────────────── التحويل ───────────────────────────

    private TaskResponse Map(DmsTask t) => new(
        t.TaskId, t.TaskNumber, t.Title, t.Description,
        t.TaskType, TaskWorkflow.ArabicName(t.TaskType),
        t.Priority, TaskWorkflow.ArabicName(t.Priority),
        t.Status, TaskWorkflow.ArabicName(t.Status),
        t.ProgressPercent,
        t.DueDate, t.StartDate, t.CompletedDate,
        TaskWorkflow.IsOverdue(t.Status, t.DueDate),
        LocalClock.DaysOverdue(t.DueDate),
        DaysRemaining(t.DueDate),
        t.DepartmentId, t.Department?.Name,
        t.AssignedToUserId, t.AssignedToUser?.FullName,
        t.CreatedByUserId, t.CreatedByUser?.FullName ?? "—",
        t.RelatedIncomingId, t.RelatedIncoming?.IncomingNumber,
        t.RelatedOutgoingId, t.RelatedOutgoing?.Number,
        t.IsRecurring, t.RecurrencePattern, t.RecurrenceInterval,
        t.RecurrenceEndDate, t.ParentRecurringTaskId,
        t.Notes, t.CreatedAt, t.UpdatedAt,
        RowVersionString(t.RowVersion),
        TaskWorkflow.NextStatuses(t.Status).ToList(),
        CanEdit(t));

    private static TaskListItemResponse MapListItem(DmsTask t, int attachmentCount) => new(
        t.TaskId, t.TaskNumber, t.Title,
        t.TaskType, t.Priority, TaskWorkflow.ArabicName(t.Priority),
        t.Status, TaskWorkflow.ArabicName(t.Status),
        t.ProgressPercent, t.DueDate,
        TaskWorkflow.IsOverdue(t.Status, t.DueDate),
        LocalClock.DaysOverdue(t.DueDate),
        DaysRemaining(t.DueDate),
        t.DepartmentId, t.Department?.Name,
        t.AssignedToUserId, t.AssignedToUser?.FullName,
        attachmentCount);

    /// <summary>يحوّل المشاركين — **والأسماء محلولةٌ في الخدمة** لا هنا.</summary>
    private static TaskParticipantResponse MapParticipant(DmsTaskParticipant p)
    {
        var userName = p.User?.FullName;
        var deptName = p.Department?.Name;

        return new TaskParticipantResponse(
            p.ParticipantId,
            p.UserId, userName,
            p.DepartmentId, deptName,
            // اسمٌ واحدٌ جاهزٌ للعرض — فلا يركّبه كلُّ عميلٍ بطريقته.
            userName ?? $"قسم {deptName ?? "—"}",
            p.Note,
            p.AddedByUserId, p.AddedByUserName ?? "—", p.AddedAt,
            p.IsRemoved, p.RemovedAt);
    }

    private static TaskUpdateResponse MapUpdate(DmsTaskUpdate u) => new(
        u.UpdateId, u.UpdateType, u.Description, u.OldValue, u.NewValue, u.Comment,
        u.UpdatedByUserId, u.UpdatedByUser?.FullName ?? "—", u.UpdatedAt);

    /// <summary>الأيام المتبقّية — **سالبةٌ للمتأخّرة**، وصفرٌ ليوم الاستحقاق نفسه.</summary>
    private static int DaysRemaining(DateTime due) => (due.Date - LocalClock.Today).Days;

    /// <summary>
    /// ⚠️ **نصٌّ base64 لا مصفوفةُ أرقام** — `byte[]` يُسلسَل نصّاً في ASP.NET Core،
    /// وقراءتُه <c>List&lt;int&gt;</c> في العميل أسقطت شاشةً كاملة في وحدة الرواتب.
    /// </summary>
    private static string RowVersionString(byte[]? rv)
        => rv is null ? string.Empty : Convert.ToBase64String(rv);

    /// <summary>مرآةُ <c>TaskService.RequireCanEdit</c> — فلا تُعرض أزرارٌ تردّ 403.</summary>
    private bool CanEdit(DmsTask t)
    {
        var current = HttpContext.RequestServices
            .GetRequiredService<Dms.Infrastructure.Services.ICurrentUser>();

        if (current.CanManageTasks) return true;
        if (current.Role is { } r && RoleHierarchy.IsManagerOrAbove(r)) return true;
        return t.CreatedByUserId == current.UserId;
    }
}
