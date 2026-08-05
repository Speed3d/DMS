using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Hr;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

/// <summary>إعدادات وحدة الموظفين وملخّصها (ADR-023).</summary>
[ApiController]
[Authorize]
[RequireHrModule]
[Route("api/hr")]
public sealed class HrController(
    AppDbContext db, ICurrentUser current, IAuditService audit, ILeaveService leaves) : ControllerBase
{
    [HttpGet("settings")]
    public async Task<ActionResult<HrSettingsResponse>> Settings(CancellationToken ct)
    {
        var s = await db.HrSettings.FirstOrDefaultAsync(ct);
        return new HrSettingsResponse(
            s?.DefaultWorkingDaysMode ?? WorkingDaysMode.Fixed,
            s?.DefaultWorkingDays ?? PayrollCalculator.DefaultWorkingDays,
            s?.EndOfServiceEnabled ?? false,
            s?.EndOfServiceRatio ?? EndOfServiceRatio.MonthPerYear,
            s?.EndOfServiceCustomDays);
    }

    [HttpPut("settings")]
    public async Task<ActionResult<HrSettingsResponse>> UpdateSettings(HrSettingsRequest req, CancellationToken ct)
    {
        RequireWrite();
        var companyId = current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");
        if (req.DefaultWorkingDays is < 1 or > 31)
            throw new ValidationException("أيام العمل يجب أن تكون بين 1 و31.");

        var s = await db.HrSettings.FirstOrDefaultAsync(ct);
        if (s is null)
        {
            s = new HrSettings { CompanyId = companyId, CreatedAt = DateTime.UtcNow };
            db.HrSettings.Add(s);
        }
        else s.UpdatedAt = DateTime.UtcNow;

        if (req.EndOfServiceEnabled && req.EndOfServiceRatio == EndOfServiceRatio.CustomDays
            && req.EndOfServiceCustomDays is null or <= 0)
            throw new ValidationException("حدّد عدد الأيام المستحقّة عن كل سنة خدمة.");

        s.DefaultWorkingDaysMode = req.DefaultWorkingDaysMode;
        s.DefaultWorkingDays = req.DefaultWorkingDays;
        s.EndOfServiceEnabled = req.EndOfServiceEnabled;
        s.EndOfServiceRatio = req.EndOfServiceRatio;
        s.EndOfServiceCustomDays =
            req.EndOfServiceRatio == EndOfServiceRatio.CustomDays ? req.EndOfServiceCustomDays : null;

        audit.Add("Update", nameof(HrSettings), companyId.ToString(), null, companyId);
        await db.SaveChangesAsync(ct);
        return new HrSettingsResponse(
            s.DefaultWorkingDaysMode, s.DefaultWorkingDays,
            s.EndOfServiceEnabled, s.EndOfServiceRatio, s.EndOfServiceCustomDays);
    }

    /// <summary>الإجازات المعلّقة في الشركة الفعّالة **مع أصحابها**.</summary>
    /// <remarks>
    /// ⚠️ بطاقة لوحة التحكم كانت تعرض **العدد** وتنقل إلى قائمة الموظفين بلا دلالةٍ على
    /// **مَن** طلب — فمع مئة موظف لا سبيل لمعرفة صاحب الطلب إلا بفتحهم واحداً واحداً
    /// (بلاغ المالك 2026-08-05). و<c>/employees/{id}/leaves</c> لا تجيب لأنها تسأل عن موظفٍ
    /// بعينه، والسؤال هنا معكوس: **مَن ينتظر؟**
    /// </remarks>
    [HttpGet("leaves/pending")]
    public async Task<ActionResult<List<PendingLeaveResponse>>> PendingLeaves(CancellationToken ct)
        => (await leaves.PendingAsync(ct))
            .Select(l => new PendingLeaveResponse(
                l.LeaveId, l.EmployeeId, l.EmployeeName, l.Position,
                l.LeaveType, l.LeaveTypeLabel, l.FromDate, l.ToDate, l.DurationDays,
                l.DeductFromSalary, l.Notes, l.CreatedAt))
            .ToList();

    /// <summary>ملخّص للوحة التحكم — كل الأرقام مفلترة على الشركة الفعّالة تلقائياً.</summary>
    [HttpGet("summary")]
    public async Task<ActionResult<HrSummaryResponse>> Summary(CancellationToken ct)
    {
        var now = DateTime.UtcNow;

        var activeEmployees = await db.EmployeeCompanies
            .CountAsync(x => x.IsActive && x.TerminationDate == null, ct);

        var thisMonth = await db.PayrollEntries
            .Where(e => e.Period!.Year == now.Year && e.Period.Month == now.Month)
            .SumAsync(e => (decimal?)e.NetSalaryIqd, ct) ?? 0m;

        var thisYear = await db.PayrollEntries
            .Where(e => e.Period!.Year == now.Year)
            .SumAsync(e => (decimal?)e.NetSalaryIqd, ct) ?? 0m;

        var unpaidMonths = await db.PayrollPeriods
            .CountAsync(p => p.Status == PayrollStatus.Draft, ct);

        var pendingLeaves = await leaves.PendingCountAsync(ct);

        return new HrSummaryResponse(
            activeEmployees, thisMonth, thisYear, unpaidMonths, pendingLeaves);
    }

    private void RequireWrite()
    {
        if (!current.CanManageHR)
            throw new ForbiddenException("لا تملك صلاحية إدارة الموظفين والرواتب.");
    }
}
