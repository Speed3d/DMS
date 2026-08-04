namespace Dms.Domain;

/// <summary>
/// إجازة موظف في شركة بعينها (الدفعة ٢ من ADR-023).
/// </summary>
/// <remarks>
/// الإجازة **سجلٌّ إداريّ أولاً**: أكثرها لا يُحسم من الراتب، و<see cref="DeductFromSalary"/>
/// قرارٌ صريح لا افتراض. وربطُها بـ<see cref="EmployeeCompany"/> لا بالموظف لأن إجازته في
/// شركةٍ لا تخصّ الأخرى.
/// </remarks>
public class EmployeeLeave
{
    public int LeaveId { get; set; }
    public int EmployeeCompanyId { get; set; }

    /// <summary>منسوخ للفلترة المباشرة (نظير <see cref="PayrollEntry.CompanyId"/>).</summary>
    public int CompanyId { get; set; }

    public LeaveType LeaveType { get; set; }
    public DateTime FromDate { get; set; }
    public DateTime ToDate { get; set; }

    /// <summary>عدد الأيام شاملاً الطرفين — يُحسب على الخادم لا يُقبل من العميل.</summary>
    public int DurationDays { get; set; }

    /// <summary>هل تحتاج موافقة؟ إجازةٌ بلا موافقة تُسجَّل مقبولةً مباشرةً.</summary>
    public bool RequiresApproval { get; set; }

    public LeaveStatus Status { get; set; }

    /// <summary>تُحسم من الراتب؟ الحسم الفعلي يُطبَّق يدوياً في كشف الشهر المعني.</summary>
    public bool DeductFromSalary { get; set; }

    public string? Notes { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? ReviewedByUserId { get; set; }
    public DateTime? ReviewedAt { get; set; }
    public string? ReviewNotes { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    public EmployeeCompany? EmployeeCompany { get; set; }
}

/// <summary>
/// سطر في سجلّ تغييرات الموظف — **يُكتب ولا يُعدَّل ولا يُحذف**.
/// </summary>
/// <remarks>
/// لماذا لا يكفي سجلّ التدقيق العام؟ لأنه سجلّ **نظام** يقرأه المدقّق بلغة الكيانات، وهذا
/// سجلّ **موظف** يقرأه المحاسب بالعربية في ملفّه: «رُفع الراتب من كذا إلى كذا». الوصف
/// جاهزٌ للعرض لا يُركَّب عند القراءة.
/// </remarks>
public class EmployeeLog
{
    public int LogId { get; set; }
    public int EmployeeCompanyId { get; set; }
    public int CompanyId { get; set; }

    public EmployeeChangeType ChangeType { get; set; }

    /// <summary>نصّ عربي جاهز للعرض.</summary>
    public string Description { get; set; } = string.Empty;

    public string? OldValue { get; set; }
    public string? NewValue { get; set; }

    public int ChangedByUserId { get; set; }
    public DateTime ChangedAt { get; set; }

    public EmployeeCompany? EmployeeCompany { get; set; }
}
