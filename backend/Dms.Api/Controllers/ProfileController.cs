using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Hr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

/// <summary>
/// البروفايل الشخصي — **بياناتُ صاحب الجلسة وحده** (ADR-033).
/// </summary>
/// <remarks>
/// 🔐 **<c>[Authorize]</c> وحده، بلا <c>[RequireModule]</c> ولا <c>[RequireHrModule]</c> —
/// وهذا مقصودٌ لا سهو:**
/// <list type="bullet">
/// <item>قسم «الرواتب» يفتح رواتب **الشركة**؛ وهذا المسار يفتح **راتبك أنت**. اشتراطُ الأول
/// للثاني يعني ألّا يرى الموظف راتبه إلا إذا رأى رواتب زملائه.</item>
/// <item>حدّ «فوق القارئ» في <see cref="Dms.Api.Auth.RequireHrModuleAttribute"/> يحمي بيانات
/// **الغير** — ولا معنى لحجب بيانات المرء عن نفسه بسبب دوره.</item>
/// </list>
///
/// 🔴 **والحارس كلُّه في <c>ProfileService</c>**: كل نقطةٍ هنا تشتقّ الموظف من
/// <c>Employee.UserId == current.UserId</c>، ولا تقبل معرّف موظفٍ من العميل. المعرّفات
/// المقبولة (<c>leaveId</c> · <c>periodId</c>) **تُفلتَر بإسناد صاحب الجلسة** قبل قراءة
/// أيّ شيء منها. أيّ نقطةٍ تُضاف هنا وتخرق ذلك تُبطل الوحدة كلَّها.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/profile")]
public sealed class ProfileController(IProfileService profile) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<MyProfileResponse>> Me(CancellationToken ct)
    {
        var m = await profile.IdentityAsync(ct);
        return new MyProfileResponse(
            m.UserId, m.FullName, m.Username, m.Role, m.CompanyName, m.DepartmentName,
            m.EmployeeId, m.EmployeeFullName, m.EmployeeFullNameEn, m.Position, m.HireDate,
            m.NationalId, m.Phone, m.Address, m.HasPhoto);
    }

    /// <summary>صورتي — نفسُ صورة بطاقتي، تُقرأ ولا تُرفع من هنا.</summary>
    /// <remarks>
    /// ⚠️ **لا نقطةَ رفعٍ في البروفايل** (قرار المالك: «صورةٌ واحدة للشخص» على البطاقة):
    /// الصورة تُرفع من ملفّ الموظف بيد مَن يملك <c>CanManageEmployees</c>، فتبقى صورةً
    /// رسميةً في ملفٍّ لا صورةَ حسابٍ يغيّرها صاحبها.
    /// </remarks>
    [HttpGet("photo")]
    public async Task<IActionResult> Photo(CancellationToken ct)
    {
        var (content, fileName) = await profile.PhotoAsync(ct);
        return File(content, MimeTypes.For(fileName), fileName);
    }

    [HttpGet("leaves")]
    public async Task<ActionResult<List<LeaveResponse>>> MyLeaves(CancellationToken ct)
        => (await profile.MyLeavesAsync(ct)).Select(MapLeave).ToList();

    [HttpPost("leaves")]
    public async Task<ActionResult<LeaveResponse>> RequestLeave(
        MyLeaveRequest req, CancellationToken ct)
        => MapLeave(await profile.RequestLeaveAsync(
            new LeaveRequestInput(req.LeaveType, req.FromDate, req.ToDate, req.Notes), ct));

    [HttpDelete("leaves/{leaveId:int}")]
    public async Task<IActionResult> CancelLeave(int leaveId, CancellationToken ct)
    {
        await profile.CancelLeaveRequestAsync(leaveId, ct);
        return NoContent();
    }

    [HttpGet("payslips")]
    public async Task<ActionResult<List<MyPayslipResponse>>> MyPayslips(
        [FromQuery] int? year, CancellationToken ct)
        => (await profile.MyPayslipsAsync(year, ct))
            .Select(p => new MyPayslipResponse(
                p.PeriodId, p.Year, p.Month, p.MonthLabel,
                p.BaseSalary, p.EligibleDays, p.WorkingDays, p.AbsenceDays,
                p.AbsenceDeduction, p.BonusAmount, p.DeductionAmount,
                p.NetSalary, p.NetSalaryIqd, p.Currency,
                p.PaymentStatus, p.PaymentStatusLabel, p.PaidAt))
            .ToList();

    [HttpGet("payslips/{periodId:int}/receipt")]
    public async Task<IActionResult> MyReceipt(int periodId, CancellationToken ct)
        => File(await profile.MyReceiptAsync(periodId, ct), MimeTypes.For(".pdf"));

    private static LeaveResponse MapLeave(EmployeeLeave l) => new(
        l.LeaveId, l.LeaveType, l.LeaveType.ArabicLabel(), l.FromDate, l.ToDate,
        l.DurationDays, l.RequiresApproval, l.Status, l.DeductFromSalary,
        l.Notes, l.CreatedAt, l.ReviewedAt, l.ReviewNotes, l.IsSelfRequested);
}
