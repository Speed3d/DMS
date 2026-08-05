using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Hr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

/// <summary>
/// الموظفون (ADR-023). <see cref="RequireHrModuleAttribute"/> يفرض **القسم + المدير فأعلى**،
/// والخدمة تفرض فوقهما <c>CanManageHR</c> على كل كتابة.
/// </summary>
[ApiController]
[Authorize]
[RequireHrModule(AppModule.Employees)]
[Route("api/employees")]
public sealed class EmployeesController(
    IEmployeeService employees, ILeaveService leaves,
    IAttachmentService attachmentService) : ControllerBase
{
    // ─────────────────────── الإجازات وسجلّ التغييرات (الدفعة ٢) ───────────────────────

    [HttpGet("{id:int}/leaves")]
    public async Task<ActionResult<List<LeaveResponse>>> Leaves(int id, CancellationToken ct)
        => (await leaves.ListAsync(id, ct)).Select(MapLeave).ToList();

    [HttpPost("{id:int}/leaves")]
    public async Task<ActionResult<LeaveResponse>> AddLeave(
        int id, LeaveRequest req, CancellationToken ct)
        => MapLeave(await leaves.CreateAsync(id,
            new LeaveInput(req.LeaveType, req.FromDate, req.ToDate,
                req.RequiresApproval, req.DeductFromSalary, req.Notes), ct));

    [HttpPatch("leaves/{leaveId:int}")]
    public async Task<ActionResult<LeaveResponse>> ReviewLeave(
        int leaveId, ReviewLeaveRequest req, CancellationToken ct)
        => MapLeave(await leaves.ReviewAsync(leaveId, req.Approve, req.Notes, ct));

    [HttpDelete("leaves/{leaveId:int}")]
    public async Task<IActionResult> DeleteLeave(int leaveId, CancellationToken ct)
    {
        await leaves.DeleteAsync(leaveId, ct);
        return NoContent();
    }

    [HttpGet("{id:int}/log")]
    public async Task<ActionResult<List<EmployeeLogResponse>>> Log(int id, CancellationToken ct)
        => (await leaves.LogAsync(id, ct))
            .Select(l => new EmployeeLogResponse(
                l.LogId, l.ChangeType, l.Description, l.OldValue, l.NewValue, l.ChangedAt))
            .ToList();

    private static LeaveResponse MapLeave(EmployeeLeave l) => new(
        l.LeaveId, l.LeaveType, l.LeaveType.ArabicLabel(), l.FromDate, l.ToDate,
        l.DurationDays, l.RequiresApproval, l.Status, l.DeductFromSalary,
        l.Notes, l.CreatedAt, l.ReviewedAt, l.ReviewNotes);

    [HttpGet]
    public async Task<ActionResult<List<EmployeeListItem>>> List(
        [FromQuery] bool? activeOnly, [FromQuery] string? search, CancellationToken ct)
    {
        var rows = await employees.ListAsync(activeOnly, search, ct);
        return rows.Select(x => new EmployeeListItem(
            x.EmployeeId, x.EmployeeCompanyId,
            x.Employee?.FullName ?? "—", x.Employee?.FullNameEn, x.Employee?.NationalId,
            x.Employee?.Phone, !string.IsNullOrEmpty(x.Employee?.PhotoBlobKey),
            x.Position, x.HireDate, x.TerminationDate,
            x.SalaryCurrency, x.BaseSalary, x.DisplayOrder, x.IsActive)).ToList();
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<EmployeeDetailResponse>> Get(int id, CancellationToken ct)
        => Map(await employees.GetAsync(id, ct));

    [HttpPost]
    public async Task<ActionResult<EmployeeDetailResponse>> Create(CreateEmployeeRequest req, CancellationToken ct)
        => Map(await employees.CreateAsync(ToProfile(req.Profile), ToEmployment(req.Employment), ct));

    [HttpPut("{id:int}")]
    public async Task<ActionResult<EmployeeDetailResponse>> Update(
        int id, EmployeeProfileRequest req, CancellationToken ct)
        => Map(await employees.UpdateProfileAsync(id, ToProfile(req), ct));

    /// <summary>
    /// إسناد الموظف للشركة **الفعّالة** أو تحديث شروط عمله فيها.
    /// </summary>
    /// <remarks>لا يقبل معرّف شركة من العميل — من أراد شركةً أخرى بدّل شركته الفعّالة.</remarks>
    [HttpPut("{id:int}/employment")]
    public async Task<ActionResult<EmploymentResponse>> Employment(
        int id, EmploymentRequest req, CancellationToken ct)
        => MapEmployment(await employees.UpsertEmploymentAsync(id, ToEmployment(req), ct));

    [HttpPost("{id:int}/terminate")]
    public async Task<IActionResult> Terminate(int id, TerminateRequest req, CancellationToken ct)
    {
        await employees.TerminateAsync(id, new TerminationInput(req.TerminationDate, req.Reason, req.Notes), ct);
        return NoContent();
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await employees.DeleteAsync(id, ct);
        return NoContent();
    }

    /// <summary>البحث عن موظف قائم برقم هويته قبل إنشاء ملف ثانٍ له (ADR-023).</summary>
    [HttpGet("lookup")]
    public async Task<ActionResult<ExistingEmployeeResponse?>> Lookup(
        [FromQuery] string nationalId, CancellationToken ct)
    {
        var hint = await employees.LookupByNationalIdAsync(nationalId, ct);
        return hint is null
            ? Ok(null)
            : Ok(new ExistingEmployeeResponse(hint.EmployeeId, hint.FullName, hint.AlreadyInThisCompany));
    }

    [HttpPost("{id:int}/photo")]
    public async Task<IActionResult> UploadPhoto(int id, IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) throw new ValidationException("الملف مطلوب.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        await employees.SetPhotoAsync(id, file.FileName, ms.ToArray(), ct);
        return NoContent();
    }

    /// <summary>صورة الموظف — **بلا اسم ملف** عمداً (مبدأ ADR-019).</summary>
    /// <remarks>
    /// تمرير اسم الملف يُنتج <c>Content-Disposition: attachment</c> فيعاملها المتصفّح تنزيلاً
    /// **ويختطفها مديرو التحميل** بدل أن تُعرض. النوع الصحيح وحده يجعلها عرضاً.
    /// </remarks>
    [HttpGet("{id:int}/photo")]
    public async Task<IActionResult> GetPhoto(int id, CancellationToken ct)
    {
        var (content, fileName) = await employees.GetPhotoAsync(id, ct);
        return File(content, MimeTypes.For(fileName));
    }

    // ─────────────────────── المستمسكات (هوية · عقد · شهادات) ───────────────────────
    //
    // ⚠️ **`OwnerType.Employee` كان موجوداً منذ الدفعة ١ وحارسُه مكتوبٌ بعناية في
    //    `AttachmentService`، ولم تكن له نقطتا رفعٍ وقائمة قطّ** — فماتت الميزة صامتةً
    //    (بلاغ المالك ٧، وهو رابع تكرارٍ لنمط «ميزة بلا مدخل» بعد G7 وG8 وG10).
    //    الوصول والصلاحية يُفحصان داخل `AttachmentService` كبقية الأنواع.

    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> Attachments(
        int id, CancellationToken ct)
        => (await attachmentService.ListAsync(OwnerType.Employee, id, ct))
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
        var att = await attachmentService.AddAsync(
            OwnerType.Employee, id, file.FileName, ms.ToArray(), ct);
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

    [HttpGet("{id:int}/salary-history")]
    public async Task<ActionResult<List<SalaryHistoryItem>>> SalaryHistory(
        int id, [FromQuery] int take = 12, CancellationToken ct = default)
    {
        var rows = await employees.SalaryHistoryAsync(id, Math.Clamp(take, 1, 60), ct);

        // عدد الإيصالات الموقَّعة لكل سطر — **استعلامٌ واحد** لا واحدٌ لكل شهر.
        var ids = rows.Select(r => r.EntryId).ToList();
        var receipts = await attachmentService.CountByOwnersAsync(OwnerType.PayrollEntry, ids, ct);

        return rows.Select(e => new SalaryHistoryItem(
            e.EntryId,
            e.Period!.Year, e.Period.Month, PayrollCalculator.ArabicMonth(e.Period.Month),
            e.NetSalary, e.SnapshotCurrency, e.NetSalaryIqd,
            e.Period.Status, e.PaymentStatus,
            receipts.TryGetValue(e.EntryId, out var n) ? n : 0)).ToList();
    }

    // ─────────────────────────── تحويلات ───────────────────────────

    private static EmployeeProfileInput ToProfile(EmployeeProfileRequest r) =>
        new(r.FullName, r.FullNameEn, r.NationalId, r.Phone, r.Address, r.Notes, r.ReceiptLanguage);

    private static EmploymentInput ToEmployment(EmploymentRequest r) =>
        new(r.Position, r.PositionEn, r.HireDate, r.SalaryCurrency, r.BaseSalary, r.DisplayOrder, r.IsActive);

    private static EmployeeDetailResponse Map(Employee e) =>
        new(e.EmployeeId, e.FullName, e.FullNameEn, e.NationalId, e.Phone, e.Address, e.Notes,
            e.ReceiptLanguage, !string.IsNullOrEmpty(e.PhotoBlobKey),
            e.Companies.Select(MapEmployment).ToList());

    private static EmploymentResponse MapEmployment(EmployeeCompany c) =>
        new(c.EmployeeCompanyId, c.CompanyId, c.Position, c.PositionEn, c.HireDate,
            c.TerminationDate, c.TerminationReason, c.TerminationNotes,
            c.SalaryCurrency, c.BaseSalary, c.DisplayOrder, c.IsActive);
}
