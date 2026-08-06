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

/// <summary>إعدادات وحدة الرواتب وملخّص الوحدتين (ADR-023 + ADR-025).</summary>
/// <remarks>
/// ⚠️ **الحارس هنا على مستوى النقطة لا الصنف** — خلافاً لـ`EmployeesController`
/// و`PayrollController`. لأن هذا المسار **يخلط القسمين**: الإعدادات قواعدُ حسابٍ ماليّ
/// (رواتب)، والإجازات المعلّقة شأنُ موظفين، والملخّص يخدم الاثنين. وحارسٌ صنفيّ واحد كان
/// إمّا يمنع صاحبَ قسمٍ من نقطته، أو يفتح له نقطة القسم الآخر.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/hr")]
public sealed class HrController(
    AppDbContext db, ICurrentUser current, IAuditService audit, ILeaveService leaves) : ControllerBase
{
    [RequireHrModule(AppModule.Payroll)]
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

    [RequireHrModule(AppModule.Payroll)]
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
    [RequireHrModule(AppModule.Employees)]
    [HttpGet("leaves/pending")]
    public async Task<ActionResult<List<PendingLeaveResponse>>> PendingLeaves(CancellationToken ct)
        => (await leaves.PendingAsync(ct))
            .Select(l => new PendingLeaveResponse(
                l.LeaveId, l.EmployeeId, l.EmployeeName, l.Position,
                l.LeaveType, l.LeaveTypeLabel, l.FromDate, l.ToDate, l.DurationDays,
                l.DeductFromSalary, l.Notes, l.CreatedAt))
            .ToList();

    /// <summary>ملخّص للوحة التحكم — كل الأرقام مفلترة على الشركة الفعّالة تلقائياً.</summary>
    /// <remarks>
    /// 🔐 **يخدم القسمين، فيُخفي عن كلٍّ ما لا يخصّه** (ADR-025): صاحبُ «الموظفين» وحده
    /// يأخذ عدد الفعّالين والإجازات المعلّقة **و`null` في الأرقام المالية**، والعكس بالعكس.
    ///
    /// ⚠️ **و`null` لا صفر:** الصفر يُقرأ «الشركة بلا رواتب هذا الشهر» وهي معلومة **كاذبة**،
    /// و`null` يُقرأ «لا تراه» فتُخفي الواجهة البطاقة. وهذا الدرس نفسه سبق أن كلّف لوحةَ
    /// التحكم بطاقاتٍ بصفرٍ كاذب قبل ADR-017 — **معلومة ناقصة أهون من معلومة كاذبة**.
    /// </remarks>
    [RequireHrModule(AppModule.Employees, AppModule.Payroll)]
    [HttpGet("summary")]
    public async Task<ActionResult<HrSummaryResponse>> Summary(CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var seesEmployees = current.HasModule(AppModule.Employees);
        var seesPayroll = current.HasModule(AppModule.Payroll);

        int? activeEmployees = seesEmployees
            ? await db.EmployeeCompanies.CountAsync(x => x.IsActive && x.TerminationDate == null, ct)
            : null;

        int? pendingLeaves = seesEmployees ? await leaves.PendingCountAsync(ct) : null;

        // 🔴 **بطاقتا لوحة التحكم تعرضان ما دفعته الشركة، لا ما ظهر في الكشوف** (ADR-028).
        //    كانتا تجمعان كل السطور — فانتفخت «رواتب هذه السنة» في قاعدة المالك بمبالغ
        //    صرفتها شركةٌ أخرى، وهي أوّل رقمٍ تقع عليه العين عند فتح النظام.
        decimal? thisMonth = seesPayroll
            ? await db.PayrollEntries
                .Where(PayrollPayable.Predicate)
                .Where(e => e.Period!.Year == now.Year && e.Period.Month == now.Month)
                .SumAsync(e => (decimal?)e.NetSalaryIqd, ct) ?? 0m
            : null;

        decimal? thisYear = seesPayroll
            ? await db.PayrollEntries
                .Where(PayrollPayable.Predicate)
                .Where(e => e.Period!.Year == now.Year)
                .SumAsync(e => (decimal?)e.NetSalaryIqd, ct) ?? 0m
            : null;

        int? unpaidMonths = seesPayroll
            ? await db.PayrollPeriods.CountAsync(p => p.Status == PayrollStatus.Draft, ct)
            : null;

        return new HrSummaryResponse(
            activeEmployees, thisMonth, thisYear, unpaidMonths, pendingLeaves);
    }

    /// <remarks>
    /// ⚠️ **إعدادات الوحدة تتبع «الرواتب»**: محتواها كلّه أيامُ عمل ومكافأةُ نهاية خدمة —
    /// أي قواعدُ حسابٍ ماليّ. فلا يغيّرها مَن يملك بطاقات الموظفين وحدها.
    /// </remarks>
    private void RequireWrite()
    {
        if (!current.CanManagePayroll)
            throw new ForbiddenException("لا تملك صلاحية إدارة كشوف الرواتب.");
    }
}
