namespace Dms.Domain;

/// <summary>مستخدم النظام. الدور هرمي، والوصول معزول حسب الشركة (عدا SuperAdmin).</summary>
public class User
{
    public int UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public UserRole Role { get; set; }

    /// <summary>
    /// الشركة **الرئيسية** — دورها افتراضٌ عند غياب ترويسة <c>X-Company-Id</c> فقط. null للسوبر أدمن.
    /// </summary>
    public int? CompanyId { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>إجبار تغيير كلمة المرور عند أول دخول (لحساب الـ Seed).</summary>
    public bool MustChangePassword { get; set; }

    // حماية ضد التخمين
    public int FailedLoginCount { get; set; }
    public DateTime? LockedUntil { get; set; }

    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }

    /// <summary>الشركات المُسندة — وكلٌّ منها يحمل صلاحيات المستخدم وقسمه **في تلك الشركة**.</summary>
    public ICollection<UserCompany> AssignedCompanies { get; set; } = new List<UserCompany>();
}

/// <summary>
/// إسناد مستخدم لشركة، **وحاملُ صلاحياته وقسمه فيها** (ADR-017).
/// </summary>
/// <remarks>
/// Hint: كانت هذه الحقول على <see cref="User"/> بقيمة واحدة تسري على كل شركاته، فتعذّر أن يدير
/// الصادر في شركة والتقارير في أخرى، أو أن يكون في «المالية» هنا و«الإدارة» هناك. نقلها إلى
/// الإسناد يجعل كل شركة عالماً مستقلاً — وهو ما تعنيه «متعدد الشركات» فعلاً.
/// </remarks>
public class UserCompany
{
    public int UserCompanyId { get; set; }
    public int UserId { get; set; }
    public int CompanyId { get; set; }

    /// <summary>أقسام النظام المسموحة في هذه الشركة (افتراضي: الكل). السوبر أدمن ورئيس الشركة معفيان.</summary>
    public AppModule Modules { get; set; } = AppModule.All;

    /// <summary>قسم عمل المستخدم في هذه الشركة. Hint: يحدّد أي كتب واردة محالة يراها هنا.</summary>
    public int? DepartmentId { get; set; }

    /// <summary>صلاحية اعتماد الصادر في هذه الشركة (المدير فأعلى يملكها بحكم دوره).</summary>
    public bool CanApprove { get; set; }

    /// <summary>
    /// صلاحية إدارة حالات الوارد في هذه الشركة — كل الانتقالات عدا الأرشفة (نمط CanApprove).
    /// </summary>
    public bool CanManageIncoming { get; set; }

    /// <summary>
    /// **يرى كل الوارد والأرشيف في هذه الشركة — متجاوزاً حدود القسم.**
    /// </summary>
    /// <remarks>
    /// ⚠️ **هذه الصلاحية تُلغي عزل الأقسام لمن تُمنح له**: موظف «المتابعة» بها يقرأ كتب
    /// «القانونية» و«المالية» كلها. ووحدةُ الأقسام (ADR-015 + ADR-018) بُنيت لتمنع هذا
    /// بالضبط — فهي **استثناء مقصود لا توسعة عامة**، وتُمنح لمن يحتاج نظرة شاملة
    /// (مدير متابعة · مدقّق) لا للجميع.
    ///
    /// **قراءة خالصة:** لا تمنح إحالةً ولا تغييرَ حالة — تلك تبقى لـ<see cref="CanManageIncoming"/>.
    /// صلاحيةٌ تفعل شيئين تصير غامضة، ولا يُعرف بعد أشهر لماذا مُنحت.
    ///
    /// ⚠️ **ولا تتجاوز العزل بين الشركات إطلاقاً:** الفلتر العام على `CompanyId` يبقى نافذاً،
    /// فصاحبها يرى كل وارد **شركته الفعّالة** وحدها. وهي لكل شركة على حدة (ADR-017).
    /// </remarks>
    public bool CanViewAllIncoming { get; set; }

    public User? User { get; set; }
    public Department? Department { get; set; }
}
