using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Hr;

public sealed record LeaveInput(
    LeaveType LeaveType, DateTime FromDate, DateTime ToDate,
    bool RequiresApproval, bool DeductFromSalary, string? Notes);

public interface ILeaveService
{
    Task<List<EmployeeLeave>> ListAsync(int employeeId, CancellationToken ct = default);
    Task<EmployeeLeave> CreateAsync(int employeeId, LeaveInput input, CancellationToken ct = default);
    Task<EmployeeLeave> ReviewAsync(int leaveId, bool approve, string? notes, CancellationToken ct = default);
    Task DeleteAsync(int leaveId, CancellationToken ct = default);
    Task<List<EmployeeLog>> LogAsync(int employeeId, CancellationToken ct = default);
    Task<int> PendingCountAsync(CancellationToken ct = default);
    Task<List<PendingLeaveItem>> PendingAsync(CancellationToken ct = default);
}

/// <summary>إجازةٌ معلّقة **مع صاحبها** — لتُعرض في قائمةٍ واحدة بلا فتح كل موظف.</summary>
/// <remarks>
/// ⚠️ **لماذا كيانٌ خاصّ ولدينا `ListAsync` لكل موظف؟** لأن بطاقة لوحة التحكم كانت تعرض
/// **العدد** وتنقل إلى قائمة الموظفين بلا دلالة على **مَن** طلب — فمع مئة موظف لا سبيل
/// لمعرفة صاحب الطلب إلا بفتحهم واحداً واحداً (بلاغ المالك 2026-08-05).
/// </remarks>
public sealed record PendingLeaveItem(
    int LeaveId, int EmployeeId, string EmployeeName, string Position,
    LeaveType LeaveType, string LeaveTypeLabel,
    DateTime FromDate, DateTime ToDate, int DurationDays,
    bool DeductFromSalary, string? Notes, DateTime CreatedAt);

/// <summary>الإجازات وسجلّ التغييرات (الدفعة ٢ من ADR-023).</summary>
public sealed class LeaveService(
    AppDbContext db, ICurrentUser current, IAuditService audit) : ILeaveService
{
    public async Task<List<EmployeeLeave>> ListAsync(int employeeId, CancellationToken ct = default)
    {
        await RequireVisibleAsync(employeeId, ct);
        return await db.EmployeeLeaves
            .Where(l => l.EmployeeCompany!.EmployeeId == employeeId)
            .OrderByDescending(l => l.FromDate)
            .ToListAsync(ct);
    }

    public async Task<EmployeeLeave> CreateAsync(
        int employeeId, LeaveInput input, CancellationToken ct = default)
    {
        RequireWrite();
        var link = await RequireLinkAsync(employeeId, ct);

        if (input.ToDate.Date < input.FromDate.Date)
            throw new ValidationException("تاريخ نهاية الإجازة لا يسبق بدايتها.");

        var days = (input.ToDate.Date - input.FromDate.Date).Days + 1;

        // تداخل مع إجازة قائمة غير مرفوضة ⇒ رفض. إجازتان في اليوم نفسه خطأ إدخال لا حالة عمل.
        var overlaps = await db.EmployeeLeaves.AnyAsync(l =>
            l.EmployeeCompanyId == link.EmployeeCompanyId &&
            l.Status != LeaveStatus.Rejected &&
            l.FromDate <= input.ToDate.Date && l.ToDate >= input.FromDate.Date, ct);
        if (overlaps)
            throw new ConflictException("توجد إجازة مسجَّلة تتداخل مع هذه المدّة.");

        var leave = new EmployeeLeave
        {
            EmployeeCompanyId = link.EmployeeCompanyId,
            CompanyId = link.CompanyId,
            LeaveType = input.LeaveType,
            FromDate = input.FromDate.Date,
            ToDate = input.ToDate.Date,
            DurationDays = days,
            RequiresApproval = input.RequiresApproval,
            // بلا موافقة ⇒ مقبولة فور تسجيلها؛ فحالة «معلّقة» بلا مراجعٍ تبقى معلّقة للأبد.
            Status = input.RequiresApproval ? LeaveStatus.Pending : LeaveStatus.Approved,
            DeductFromSalary = input.DeductFromSalary,
            Notes = string.IsNullOrWhiteSpace(input.Notes) ? null : input.Notes.Trim(),
            CreatedByUserId = current.UserId ?? 0,
            CreatedAt = DateTime.UtcNow,
        };
        db.EmployeeLeaves.Add(leave);

        AddLog(link, EmployeeChangeType.LeaveRecorded,
            $"إجازة {ArabicLeave(input.LeaveType)} {days} يوماً " +
            $"({input.FromDate:yyyy-MM-dd} → {input.ToDate:yyyy-MM-dd})");

        audit.Add("CreateLeave", nameof(EmployeeLeave), employeeId.ToString(),
            $"{ArabicLeave(input.LeaveType)} {days} يوماً", link.CompanyId);
        await db.SaveChangesAsync(ct);
        return leave;
    }

    public async Task<EmployeeLeave> ReviewAsync(
        int leaveId, bool approve, string? notes, CancellationToken ct = default)
    {
        RequireWrite();
        var leave = await db.EmployeeLeaves.Include(l => l.EmployeeCompany)
                        .FirstOrDefaultAsync(l => l.LeaveId == leaveId, ct)
                    ?? throw new NotFoundException("الإجازة غير موجودة.");

        if (leave.Status != LeaveStatus.Pending)
            throw new ConflictException("الإجازة روجعت من قبل — لا يمكن تغيير قرارها.");

        leave.Status = approve ? LeaveStatus.Approved : LeaveStatus.Rejected;
        leave.ReviewedByUserId = current.UserId;
        leave.ReviewedAt = DateTime.UtcNow;
        leave.ReviewNotes = string.IsNullOrWhiteSpace(notes) ? null : notes.Trim();

        if (leave.EmployeeCompany is { } link)
            AddLog(link, EmployeeChangeType.LeaveRecorded,
                $"{(approve ? "قُبلت" : "رُفضت")} إجازة {ArabicLeave(leave.LeaveType)} " +
                $"({leave.FromDate:yyyy-MM-dd} → {leave.ToDate:yyyy-MM-dd})");

        audit.Add("ReviewLeave", nameof(EmployeeLeave), leaveId.ToString(),
            approve ? "موافقة" : "رفض", leave.CompanyId);
        await db.SaveChangesAsync(ct);
        return leave;
    }

    public async Task DeleteAsync(int leaveId, CancellationToken ct = default)
    {
        RequireWrite();
        var leave = await db.EmployeeLeaves.FirstOrDefaultAsync(l => l.LeaveId == leaveId, ct)
                    ?? throw new NotFoundException("الإجازة غير موجودة.");

        leave.IsDeleted = true;
        leave.DeletedByUserId = current.UserId;
        leave.DeletedAt = DateTime.UtcNow;

        audit.Add("DeleteLeave", nameof(EmployeeLeave), leaveId.ToString(), null, leave.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task<List<EmployeeLog>> LogAsync(int employeeId, CancellationToken ct = default)
    {
        await RequireVisibleAsync(employeeId, ct);
        return await db.EmployeeLogs
            .Where(l => l.EmployeeCompany!.EmployeeId == employeeId)
            .OrderByDescending(l => l.ChangedAt)
            .Take(200)
            .ToListAsync(ct);
    }

    public Task<int> PendingCountAsync(CancellationToken ct = default) =>
        db.EmployeeLeaves.CountAsync(l => l.Status == LeaveStatus.Pending, ct);

    /// <summary>الإجازات المعلّقة في الشركة الفعّالة **مع أصحابها**، الأقدم طلباً أولاً.</summary>
    /// <remarks>
    /// ⚠️ **بلا `IgnoreQueryFilters`**: العزل يأتي من الفلتر العام على `EmployeeLeaves` نفسه
    /// كبقية الوحدة، فلا تُكشف إجازةُ موظفٍ في شركة أخرى. ولا حاجة لـ<c>RequireWrite</c> —
    /// هذه **قراءة**، ومن يرى الوحدة يرى ما ينتظر بتّه فيها.
    /// </remarks>
    public Task<List<PendingLeaveItem>> PendingAsync(CancellationToken ct = default) =>
        db.EmployeeLeaves
            .Where(l => l.Status == LeaveStatus.Pending)
            .OrderBy(l => l.CreatedAt)
            .Select(l => new PendingLeaveItem(
                l.LeaveId,
                l.EmployeeCompany!.EmployeeId,
                l.EmployeeCompany.Employee!.FullName,
                l.EmployeeCompany.Position,
                l.LeaveType,
                l.LeaveType.ArabicLabel(),
                l.FromDate, l.ToDate, l.DurationDays,
                l.DeductFromSalary, l.Notes, l.CreatedAt))
            .ToListAsync(ct);

    // ─────────────────────────── مساعدات ───────────────────────────

    private void AddLog(EmployeeCompany link, EmployeeChangeType type, string description,
        string? oldValue = null, string? newValue = null)
    {
        db.EmployeeLogs.Add(new EmployeeLog
        {
            EmployeeCompanyId = link.EmployeeCompanyId,
            CompanyId = link.CompanyId,
            ChangeType = type,
            Description = description,
            OldValue = oldValue,
            NewValue = newValue,
            ChangedByUserId = current.UserId ?? 0,
            ChangedAt = DateTime.UtcNow,
        });
    }

    /// <summary>الفلتر العام يحجب موظفي الشركات الأخرى — الغياب هنا يعني «لا تراه».</summary>
    private async Task RequireVisibleAsync(int employeeId, CancellationToken ct)
    {
        var visible = await db.Employees.AnyAsync(e => e.EmployeeId == employeeId, ct);
        if (!visible) throw new NotFoundException("الموظف غير موجود أو لا تملك صلاحية رؤيته.");
    }

    private async Task<EmployeeCompany> RequireLinkAsync(int employeeId, CancellationToken ct)
    {
        var companyId = current.ActiveCompanyId
                        ?? throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");
        return await db.EmployeeCompanies
                   .FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.CompanyId == companyId, ct)
               ?? throw new NotFoundException("الموظف غير مُسنَد لهذه الشركة.");
    }

    private void RequireWrite()
    {
        if (!current.CanManageHR)
            throw new ForbiddenException("لا تملك صلاحية إدارة الموظفين والرواتب.");
    }

    internal static string ArabicLeave(LeaveType t) => t switch
    {
        LeaveType.Annual => "اعتيادية",
        LeaveType.Sick => "مرضية",
        LeaveType.Administrative => "إدارية",
        LeaveType.Unpaid => "بلا راتب",
        _ => "أخرى",
    };
}
