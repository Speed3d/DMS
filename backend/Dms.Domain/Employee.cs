namespace Dms.Domain;

/// <summary>
/// الموظف — كيان **عابر للشركات** (بلا <c>CompanyId</c>) على نمط <see cref="User"/>، لأن
/// الشخص الواحد قد يعمل في شركتين للمالك نفسه بشروط مختلفة (ADR-023).
/// </summary>
/// <remarks>
/// ⚠️ **العزل لا يأتي من غياب <c>CompanyId</c> بل من فلتر عام عبر <see cref="Companies"/>**
/// (انظر <c>AppDbContext.OnModelCreating</c>). الفلتر مرآةٌ حرفية لفلتر <see cref="User"/>:
/// بدونه يُعيد <c>GET /api/employees/{id}</c> أي موظف في القاعدة — هويةً وهاتفاً وعنواناً —
/// حتى لمن لا يعمل في شركة الطالب أصلاً. **كيانٌ بلا <c>CompanyId</c> ليس كياناً بلا عزل.**
///
/// وبياناته هنا **شخصية لا وظيفية**: الراتب والصفة وتاريخ التعيين تخصّ الشركة، فموضعها
/// <see cref="EmployeeCompany"/> لا هنا.
/// </remarks>
public class Employee
{
    public int EmployeeId { get; set; }

    /// <summary>الاسم الكامل بالعربية — يظهر في الكشف والإيصال العربي.</summary>
    public string FullName { get; set; } = string.Empty;

    /// <summary>الاسم بالإنجليزية — إلزامي عملياً لمن لغة إيصاله إنجليزية (عمال أجانب).</summary>
    public string? FullNameEn { get; set; }

    public string? NationalId { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }

    /// <summary>مفتاح صورة الموظف في <c>IFileStorage</c> — لا تُكشف مباشرةً بل عبر نقطة API.</summary>
    public string? PhotoBlobKey { get; set; }

    public string? Notes { get; set; }

    /// <summary>
    /// حساب النظام الذي يخصّ هذا الموظف — **مفتاح البروفايل الشخصي** (ADR-033).
    /// <c>null</c> يعني موظفاً بلا حساب (عامل لا يستعمل النظام)، والعكس بالعكس.
    /// </summary>
    /// <remarks>
    /// 🔴 **الربط يمنح رؤية راتب** — فهو قرارُ صلاحيةٍ لا حقلَ بياناتٍ عاديّ: من رُبط بهذه
    /// البطاقة يقرأ صافي رواتبه وإجازاته بلا أن يملك قسم الرواتب ولا قسم الموظفين. لذلك
    /// يُسجَّل في سجلّ التدقيق **وفي سجلّ تغييرات الموظف** معاً، ويملكه مَن يملك
    /// <c>CanManageEmployees</c> وحده.
    ///
    /// ⚠️ **وفهرسٌ فريد مُرشَّح يحرسه في الاتجاهين**: لا مستخدمان لبطاقةٍ واحدة (فيقرأ أحدهما
    /// راتب الآخر)، ولا بطاقتان لمستخدمٍ واحد (فلا يُعرف أيّهما راتبه). الفهرس يستثني
    /// <c>NULL</c> والمحذوف ناعماً — فالموظفون بلا حساب كثيرون وكلّهم <c>null</c>.
    ///
    /// ⚠️ **وهو على <see cref="Employee"/> لا على <see cref="EmployeeCompany"/>**: الشخص واحد
    /// وحسابُه واحد ولو عمل في شركتين — نظيرُ <c>NationalId</c> تماماً. ولو وُضع على الإسناد
    /// لصار للشخص الواحد حسابان في شركتين، وهو ما يناقض <c>User</c> نفسه (ADR-011).
    /// </remarks>
    public int? UserId { get; set; }

    /// <summary>لغة إيصال استلام الراتب.</summary>
    public ReceiptLanguage ReceiptLanguage { get; set; }

    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }

    // حذف ناعم (قاعدة المشروع: لا حذف فعلي)
    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    /// <summary>الشركات التي يعمل فيها — **وحاملةُ شروط عمله في كلٍّ منها**.</summary>
    public ICollection<EmployeeCompany> Companies { get; set; } = new List<EmployeeCompany>();
}

/// <summary>
/// إسناد موظف لشركة، **وحاملُ شروط عمله فيها** (الصفة · تاريخ التعيين · العملة · الراتب).
/// نظير <see cref="UserCompany"/> تماماً — ولنفس السبب: كل شركة عالمٌ مستقل (ADR-017).
/// </summary>
public class EmployeeCompany
{
    public int EmployeeCompanyId { get; set; }
    public int EmployeeId { get; set; }
    public int CompanyId { get; set; }

    /// <summary>الصفة الوظيفية بالعربية (مهندس · سائق · محاسب).</summary>
    public string Position { get; set; } = string.Empty;
    public string? PositionEn { get; set; }

    public DateTime HireDate { get; set; }

    /// <summary>تاريخ إنهاء الخدمة — وجوده يجعل الشهور بعده غير مستحقّة، والشهرَ نفسه جزئياً.</summary>
    public DateTime? TerminationDate { get; set; }
    public TerminationReason? TerminationReason { get; set; }
    public string? TerminationNotes { get; set; }

    /// <summary>عملة الراتب. **المكافأة والخصم يتبعانها دائماً** — فلا عمود عملة مستقلاً لهما.</summary>
    public Currency SalaryCurrency { get; set; }

    public decimal BaseSalary { get; set; }

    /// <summary>ترتيب ظهوره في كشف الرواتب (المالك يرتّب موظفيه كما اعتاد).</summary>
    public int DisplayOrder { get; set; }

    /// <summary>على رأس عمله؟ غير الفعّال لا يُدرَج في كشوف الشهور الجديدة.</summary>
    public bool IsActive { get; set; } = true;

    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    public Employee? Employee { get; set; }
}
