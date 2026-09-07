using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Reports;
using Dms.Infrastructure.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Reports)]
[Route("api/[controller]")]
public sealed class ReportsController(IReportService reports) : ControllerBase
{
    /// <summary>التقرير المالي لفترة (يجمع الصادر المعتمد + الأرشيف بالدينار). source: All/Outgoing/Archive.</summary>
    [HttpGet("financial")]
    public async Task<ActionResult<FinancialReportDto>> Financial(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var r = await reports.FinancialAsync(from, to, entityId, source, ct);
        return new FinancialReportDto(r.From, r.To,
            r.Rows.Select(x => new FinancialRowDto(x.Source, x.Number, x.Date, x.EntityName, x.Amount, x.Currency, x.AmountInIqd)).ToList(),
            r.TotalIqd, r.Count);
    }

    [HttpGet("financial/pdf")]
    public async Task<IActionResult> FinancialPdf(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var bytes = await reports.FinancialPdfAsync(from, to, entityId, source, ct);
        // بلا اسم ملف عمداً: العميل يجلب البايتات بـXHR ويسمّي الملف بنفسه، وترويسةُ
        // «تنزيل» تجعل مديري التحميل يختطفون الطلب فلا يصل ردّ (نفس علّة ADR-019).
        return File(bytes, "application/pdf");
    }

    [HttpGet("financial/excel")]
    public async Task<IActionResult> FinancialExcel(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var bytes = await reports.FinancialExcelAsync(from, to, entityId, source, ct);
        // بلا اسم ملف عمداً — انظر التعليق في FinancialPdf.
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    }

    // ══════════════════ تقرير النشاط ══════════════════
    //
    // 🔐 **حارسٌ مزدوج مقصود: قسم التقارير (على الصنف) + دور السوبر أدمن (هنا).**
    //    سجلّ التدقيق يكشف مواضيع الصادر وأرقامه والأرشيف والمستخدمين — أي **بيانات كل
    //    الأقسام**، ويكشف معها **مَن فعل ماذا**، وهي معلومةٌ عن الأشخاص لا عن الوثائق.
    //
    // 🔄 **ضُيّق من «رئيس الشركة فأعلى» إلى «السوبر أدمن وحده» بقرار المالك (2026-08-12).**
    //    مبرّرُه أن التقرير **رقابةٌ على المستخدمين أنفسهم** — بمن فيهم رئيس الشركة — فمن
    //    يُراقَب لا يملك أداة المراقبة. والقاعدة الجديدة: **كل من دون السوبر أدمن محجوب**،
    //    رئيساً كان أو مديراً أو موظفاً أو قارئاً.
    //
    // ⚠️ **و`AuditController` ضُيّق معه في الدفعة نفسها** — البابان يقودان إلى البيان نفسه،
    //    وبابان بحارسين مختلفين أسوأ من بابٍ واحدٍ مفتوح لأنه يُوهم بالإغلاق.

    /// <summary>تقرير النشاط من سجل التدقيق — سطورٌ مترجَمة + تجميعٌ بالفعل وبالمستخدم.</summary>
    [HttpGet("activity")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<ActionResult<ActivityReportDto>> Activity(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? userId,
        [FromQuery] string? action, [FromQuery] string? entityType, [FromQuery] int take = 500,
        CancellationToken ct = default)
    {
        var r = await reports.ActivityAsync(new ActivityFilter(from, to, userId, action, entityType, take), ct);
        return new ActivityReportDto(r.From, r.To,
            r.Rows.Select(x => new ActivityRowDto(
                x.Timestamp, x.UserId, x.UserName, x.Action, x.ActionLabel,
                x.EntityType, x.EntityLabel, x.EntityId, x.Details)).ToList(),
            r.TotalCount,
            r.ByAction.Select(c => new CountRowDto(c.Label, c.Count)).ToList(),
            r.ByUser.Select(c => new CountRowDto(c.Label, c.Count)).ToList());
    }

    [HttpGet("activity/pdf")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ActivityPdf(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? userId,
        [FromQuery] string? action, [FromQuery] string? entityType, [FromQuery] int take = 500,
        CancellationToken ct = default)
    {
        var bytes = await reports.ActivityPdfAsync(new ActivityFilter(from, to, userId, action, entityType, take), ct);
        // بلا اسم ملف عمداً — انظر التعليق في FinancialPdf.
        return File(bytes, "application/pdf");
    }

    [HttpGet("activity/excel")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ActivityExcel(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? userId,
        [FromQuery] string? action, [FromQuery] string? entityType, [FromQuery] int take = 500,
        CancellationToken ct = default)
    {
        var bytes = await reports.ActivityExcelAsync(new ActivityFilter(from, to, userId, action, entityType, take), ct);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    }

    // ══════════════════ التقارير التفصيلية ══════════════════
    //
    // 🔐 **حدٌّ مزدوج هنا أيضاً — لكن بالقسم لا بالدور:** `[RequireModule(Reports)]` على الصنف
    //    **مع قسم الوحدة نفسها** على كل نقطة. بدونه يصير التقرير **باباً خلفياً**: مَن مُنح
    //    «التقارير» ليقرأ المالي كان سيقرأ **مواضيع الصادر وعناوين الأرشيف** وهي محجوبة عنه
    //    في `/api/outgoing` و`/api/archive` بحرّاسهما.
    //    ⚠️ **كشفَ هذا فحصُ الصلاحيات بعد الكتابة لا قبلها** — النقطتان كُتبتا بحارس التقارير
    //    وحده أولاً، وهو بالضبط نمط «الباب الخلفي» الذي عالجته ADR-021 في الأرشيف والوارد.
    //
    // وأمّا **رؤية الصفوف** فتُحسم داخل `Query()`/`LensAsync` بقواعد الوحدتين نفسها — فمَن يرى
    // الكتاب على الشاشة يراه في تقريره، ومَن لا يراه لا يجده (ADR-030).

    /// <summary>الصادر التفصيلي: كتبٌ بحالتها ومُنشئها ومعتمِدها. `status`: `Draft`/`Final`.</summary>
    [HttpGet("outgoing-detail")]
    [RequireModule(AppModule.Outgoing)]
    public async Task<ActionResult<OutgoingDetailReportDto>> OutgoingDetail(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] BookStatus? status, CancellationToken ct = default)
    {
        var r = await reports.OutgoingDetailAsync(new OutgoingDetailFilter(from, to, entityId, status), ct);
        return new OutgoingDetailReportDto(
            r.Rows.Select(x => new OutgoingDetailRowDto(
                x.OutgoingId, x.Number, x.Date, x.Subject, x.EntityName, x.Status, x.StatusLabel,
                x.CreatedBy, x.ApprovedBy, x.ApprovedAt, x.Amount, x.Currency, x.AmountInIqd)).ToList(),
            r.Count, r.Drafts, r.Approved, r.ApprovedTotalIqd);
    }

    [HttpGet("outgoing-detail/pdf")]
    [RequireModule(AppModule.Outgoing)]
    public async Task<IActionResult> OutgoingDetailPdf(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] BookStatus? status, CancellationToken ct = default)
        => File(await reports.OutgoingDetailPdfAsync(new OutgoingDetailFilter(from, to, entityId, status), ct),
                "application/pdf");

    [HttpGet("outgoing-detail/excel")]
    [RequireModule(AppModule.Outgoing)]
    public async Task<IActionResult> OutgoingDetailExcel(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] BookStatus? status, CancellationToken ct = default)
        => File(await reports.OutgoingDetailExcelAsync(new OutgoingDetailFilter(from, to, entityId, status), ct),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");

    /// <summary>الأرشيف التفصيلي — **من عدسة الأرشيف نفسها** (وارد مؤرشف + أضابير).</summary>
    /// <remarks>
    /// 🔐 وحدُّ الوارد المزدوج محفوظ داخل `LensAsync`: مَن لا يملك قسم «الوارد» **لا تظهر له
    /// صفوفُ الوارد المؤرشف** في هذا التقرير ولا في الشاشة — الباب واحد والحارس واحد.
    /// </remarks>
    [HttpGet("archive-detail")]
    [RequireModule(AppModule.Archive)]
    public async Task<ActionResult<ArchiveDetailReportDto>> ArchiveDetail(
        [FromQuery] string? search, [FromQuery] int? year, [FromQuery] int? month,
        [FromQuery] int? departmentId, [FromQuery] string? source, CancellationToken ct = default)
    {
        var r = await reports.ArchiveDetailAsync(new ArchiveLensFilter(search, year, month, departmentId, source), ct);
        return new ArchiveDetailReportDto(
            r.Rows.Select(x => new ArchiveDetailRowDto(
                x.IsIncoming, x.SourceLabel, x.Number, x.Date, x.Title,
                x.EntityName, x.DocumentType, x.Departments, x.AmountInIqd)).ToList(),
            r.Count, r.IncomingCount, r.PaperCount, r.TotalIqd);
    }

    [HttpGet("archive-detail/pdf")]
    [RequireModule(AppModule.Archive)]
    public async Task<IActionResult> ArchiveDetailPdf(
        [FromQuery] string? search, [FromQuery] int? year, [FromQuery] int? month,
        [FromQuery] int? departmentId, [FromQuery] string? source, CancellationToken ct = default)
        => File(await reports.ArchiveDetailPdfAsync(new ArchiveLensFilter(search, year, month, departmentId, source), ct),
                "application/pdf");

    [HttpGet("archive-detail/excel")]
    [RequireModule(AppModule.Archive)]
    public async Task<IActionResult> ArchiveDetailExcel(
        [FromQuery] string? search, [FromQuery] int? year, [FromQuery] int? month,
        [FromQuery] int? departmentId, [FromQuery] string? source, CancellationToken ct = default)
        => File(await reports.ArchiveDetailExcelAsync(new ArchiveLensFilter(search, year, month, departmentId, source), ct),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");

    // ══════════════════ تقرير المهام (الدفعة ٧) ══════════════════
    //
    // 🔐 **حدٌّ مزدوج كنظيرَيه**: قسم **التقارير** من الصنف، وقسم **المهام** من الوسم أدناه.
    //    وهو `RequireGrantedModule` لا `RequireModule` لأن المهام قسمٌ **يُمنح صراحةً ولا
    //    يبلغه القارئ** (ADR-037) — فحارسُ التقارير وحده كان سيفتح مهامّ الشركة لقارئٍ
    //    يملك التقارير. **وهذا بعينه «الباب الخلفي» الذي عالجته ADR-031.**
    //
    // 🔴 **ورؤية الصفوف تُحسم داخل `tasks.Filtered()`** — بقاعدة الرؤية نفسها التي تغذّي
    //    الشاشة (ADR-037)، فمَن يرى المهمة على الشاشة يجدها في تقريره ولا يجد سواها.

    /// <summary>تقرير المهام التفصيلي — بفلاتر الشاشة نفسها.</summary>
    [HttpGet("tasks-detail")]
    [RequireGrantedModule(AppModule.Tasks)]
    public async Task<ActionResult<TaskDetailReportDto>> TasksDetail(
        [FromQuery] DmsTaskStatus? status, [FromQuery] DmsTaskPriority? priority,
        [FromQuery] int? departmentId, [FromQuery] int? assignedTo, [FromQuery] int? createdBy,
        [FromQuery] DateTime? dueFrom, [FromQuery] DateTime? dueTo,
        [FromQuery] bool? isOverdue, [FromQuery] bool mineOnly = false,
        [FromQuery] string? search = null, CancellationToken ct = default)
    {
        var r = await reports.TaskDetailAsync(
            TaskReportFilter(status, priority, departmentId, assignedTo, createdBy,
                dueFrom, dueTo, isOverdue, mineOnly, search), ct);

        return new TaskDetailReportDto(
            r.Rows.Select(x => new TaskDetailRowDto(
                x.TaskId, x.Number, x.Title, x.TypeLabel, x.PriorityLabel,
                x.Status, x.StatusLabel, x.ProgressPercent, x.DueDate,
                x.DepartmentName, x.AssignedTo, x.CreatedBy,
                x.IsOverdue, x.DaysOverdue, x.CompletedDate)).ToList(),
            r.Count, r.Active, r.Overdue, r.Completed, r.AverageProgress,
            r.ByStatus.Select(s => new CountRowDto(s.Label, s.Count)).ToList());
    }

    [HttpGet("tasks-detail/pdf")]
    [RequireGrantedModule(AppModule.Tasks)]
    public async Task<IActionResult> TasksDetailPdf(
        [FromQuery] DmsTaskStatus? status, [FromQuery] DmsTaskPriority? priority,
        [FromQuery] int? departmentId, [FromQuery] int? assignedTo, [FromQuery] int? createdBy,
        [FromQuery] DateTime? dueFrom, [FromQuery] DateTime? dueTo,
        [FromQuery] bool? isOverdue, [FromQuery] bool mineOnly = false,
        [FromQuery] string? search = null, CancellationToken ct = default)
        => File(await reports.TaskDetailPdfAsync(
                    TaskReportFilter(status, priority, departmentId, assignedTo, createdBy,
                        dueFrom, dueTo, isOverdue, mineOnly, search), ct),
                "application/pdf");

    [HttpGet("tasks-detail/excel")]
    [RequireGrantedModule(AppModule.Tasks)]
    public async Task<IActionResult> TasksDetailExcel(
        [FromQuery] DmsTaskStatus? status, [FromQuery] DmsTaskPriority? priority,
        [FromQuery] int? departmentId, [FromQuery] int? assignedTo, [FromQuery] int? createdBy,
        [FromQuery] DateTime? dueFrom, [FromQuery] DateTime? dueTo,
        [FromQuery] bool? isOverdue, [FromQuery] bool mineOnly = false,
        [FromQuery] string? search = null, CancellationToken ct = default)
        => File(await reports.TaskDetailExcelAsync(
                    TaskReportFilter(status, priority, departmentId, assignedTo, createdBy,
                        dueFrom, dueTo, isOverdue, mineOnly, search), ct),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");

    /// <summary>الفلتر نفسه للنقاط الثلاث — **مصدرٌ واحد** فلا تتباعد الشاشةُ عن مطبوعتها.</summary>
    private static TaskFilters TaskReportFilter(
        DmsTaskStatus? status, DmsTaskPriority? priority, int? departmentId, int? assignedTo,
        int? createdBy, DateTime? dueFrom, DateTime? dueTo, bool? isOverdue,
        bool mineOnly, string? search)
        => new(status, priority, departmentId, assignedTo, createdBy,
               dueFrom, dueTo, isOverdue, mineOnly, search);

    /// <summary>مفردات سجلّ التدقيق (الأفعال والأنواع) بعربيّتها — لتملأ قوائم الفلترة.</summary>
    /// <remarks>
    /// 🔴 **تُقرأ من `AuditLabels` لا من القاعدة**: قائمةٌ مبنيّة على `DISTINCT` من السجلّ
    /// **تخلو ممّا لم يقع بعد**، فيبحث المالك عن «استعادة نسخة» فلا يجدها لأنها لم تحدث —
    /// فيظنّ الفلتر ناقصاً. والمصدر الواحد يُبقي العربية في مكانٍ واحد.
    /// </remarks>
    [HttpGet("activity/vocabulary")]
    [Authorize(Roles = "SuperAdmin")]
    public ActionResult<AuditVocabularyDto> ActivityVocabulary()
        => new AuditVocabularyDto(
            AuditLabels.Actions.Select(kv => new LabeledValueDto(kv.Key, kv.Value))
                .OrderBy(x => x.Label, StringComparer.Ordinal).ToList(),
            AuditLabels.Entities.Select(kv => new LabeledValueDto(kv.Key, kv.Value))
                .OrderBy(x => x.Label, StringComparer.Ordinal).ToList());
}
