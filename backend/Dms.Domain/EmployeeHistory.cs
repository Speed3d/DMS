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
    /// <remarks>
    /// ⚠️ **في الطلب الذاتيّ يقرّرها المراجع لا الطالب** (ADR-033): الموظف يطلب إجازةً،
    /// و**الحسمُ قرارُ مَن يوافق** — فلو تركناه للطالب لاختار «بلا حسم» دائماً.
    /// تُكتب <c>false</c> عند الطلب وتُحسم عند المراجعة.
    /// </remarks>
    public bool DeductFromSalary { get; set; }

    /// <summary>
    /// طلبها الموظف بنفسه من بروفايله؟ (ADR-033)
    /// </summary>
    /// <remarks>
    /// 🔴 **ليست حقلَ زينة**: المراجع يجب أن يعرف أن هذه إجازةٌ **لم يُحسم حسمُها بعد** —
    /// فسطرٌ سجّله كاتب الشؤون جاء بقرار الحسم معه، وسطرٌ طلبه الموظف يأتي بلا قرار
    /// وينتظره. بدون هذا العلَم يوافق المراجع على طلبٍ ظانّاً أن حسمه مقرَّر، فيمرّ
    /// <c>false</c> الافتراضيّ صامتاً ⇒ إجازةُ شهرٍ بلا راتبٍ تُحتسب مدفوعة.
    /// </remarks>
    public bool IsSelfRequested { get; set; }

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
/// بتٌّ في حسم إجازةٍ من كشف شهرٍ بعينه — **سطرٌ لكل (إجازة × شهر)** (ADR-036).
/// </summary>
/// <remarks>
/// 🔴 **لماذا جدولٌ مستقلّ لا عمودان على <see cref="EmployeeLeave"/>؟** لأن الإجازة تُقسَم
/// بالأيام على الشهور (قرار المالك)، فإجازةُ ٢٨ آب ← ٣ أيلول **تُبتّ مرّتين**: أربعة أيام
/// في كشف آب وثلاثة في كشف أيلول. وعمودٌ واحد على الإجازة لا يسع حالتين.
///
/// 🔴 **وغيابُ السطر هو «لم يُبتّ»** — وهو ما يُظهر التنبيه. أمّا <see cref="Applied"/>:
/// <list type="bullet">
/// <item><c>true</c> = طُبّق الحسم على سطر الراتب.</item>
/// <item><c>false</c> = **صُرف النظر** عن الحسم هذا الشهر بقرارٍ صريح.</item>
/// </list>
/// فالحالتان **بتٌّ** يُسكت التنبيه، والفرق بينهما يبقى مقروءاً في السجلّ.
///
/// ⚠️ **ولا يُعدَّل قرار الإجازة نفسه**: <c>LeaveService.ReviewAsync</c> يرفض إعادة المراجعة
/// بعد البتّ (409). فالتراجع يقع **هنا** — في الكشف — لا في سجلّ الإجازة، فيبقى ما بُتّ
/// محفوظاً كما كان ويبقى الأثر الماليّ قابلاً للتصحيح.
/// </remarks>
public class EmployeeLeaveSettlement
{
    public int SettlementId { get; set; }

    public int LeaveId { get; set; }

    /// <summary>الشهر الذي **تخصّه هذه الأيام** — لا الكشف الذي بُتّ فيه.</summary>
    /// <remarks>
    /// 🔴 **المفتاح هو هذا لا <see cref="PeriodId"/>:** إجازةٌ مرحَّلة من آب تُبتّ في كشف
    /// أيلول، وإجازةُ أيلول تُبتّ فيه أيضاً — فلو كان المفتاح الكشفَ لاصطدمتا وبدت إحداهما
    /// مبتوتةً وهي لم تُمسّ.
    /// </remarks>
    public int LeaveYear { get; set; }

    /// <inheritdoc cref="LeaveYear"/>
    public int LeaveMonth { get; set; }

    /// <summary>الكشف الذي بُتّ فيه فعلاً — قد يكون **غير شهر الإجازة** إن رُحِّلت.</summary>
    public int PeriodId { get; set; }

    /// <summary>منسوخ للفلترة المباشرة (نظير <see cref="EmployeeLeave.CompanyId"/>).</summary>
    public int CompanyId { get; set; }

    /// <summary>أيام هذه الإجازة الواقعة في ذلك الشهر — بـ<c>LeaveDeduction.DaysInMonth</c>.</summary>
    public int Days { get; set; }

    /// <summary>طُبّق الحسم؟ <c>false</c> = صُرف النظر عنه صراحةً.</summary>
    public bool Applied { get; set; }

    public int? SettledByUserId { get; set; }
    public DateTime SettledAt { get; set; }
    public string? Notes { get; set; }

    public EmployeeLeave? Leave { get; set; }
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
