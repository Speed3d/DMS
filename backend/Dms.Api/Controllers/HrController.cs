using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
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
public sealed class HrController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet("settings")]
    public async Task<ActionResult<HrSettingsResponse>> Settings(CancellationToken ct)
    {
        var s = await db.HrSettings.FirstOrDefaultAsync(ct);
        return new HrSettingsResponse(
            s?.DefaultWorkingDaysMode ?? WorkingDaysMode.Fixed,
            s?.DefaultWorkingDays ?? PayrollCalculator.DefaultWorkingDays);
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

        s.DefaultWorkingDaysMode = req.DefaultWorkingDaysMode;
        s.DefaultWorkingDays = req.DefaultWorkingDays;

        audit.Add("Update", nameof(HrSettings), companyId.ToString(), null, companyId);
        await db.SaveChangesAsync(ct);
        return new HrSettingsResponse(s.DefaultWorkingDaysMode, s.DefaultWorkingDays);
    }

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

        return new HrSummaryResponse(activeEmployees, thisMonth, thisYear, unpaidMonths);
    }

    private void RequireWrite()
    {
        if (!current.CanManageHR)
            throw new ForbiddenException("لا تملك صلاحية إدارة الموظفين والرواتب.");
    }
}
