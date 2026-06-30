namespace Dms.Domain;

/// <summary>مستخدم النظام. الدور هرمي، والوصول معزول حسب الشركة (عدا SuperAdmin).</summary>
public class User
{
    public int UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public UserRole Role { get; set; }

    /// <summary>شركة المستخدم. null للسوبر أدمن (يرى الكل).</summary>
    public int? CompanyId { get; set; }

    /// <summary>صلاحية اعتماد الكتب (المدير فأعلى افتراضياً، أو بتفويض).</summary>
    public bool CanApprove { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>إجبار تغيير كلمة المرور عند أول دخول (لحساب الـ Seed).</summary>
    public bool MustChangePassword { get; set; }

    // حماية ضد التخمين
    public int FailedLoginCount { get; set; }
    public DateTime? LockedUntil { get; set; }

    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }

    /// <summary>شركات إضافية مُسندة (لرئيس الشركة على أكثر من شركة).</summary>
    public ICollection<UserCompany> AssignedCompanies { get; set; } = new List<UserCompany>();
}

/// <summary>إسناد مستخدم لشركة إضافية (خاصة برئيس الشركة).</summary>
public class UserCompany
{
    public int UserCompanyId { get; set; }
    public int UserId { get; set; }
    public int CompanyId { get; set; }

    public User? User { get; set; }
}
