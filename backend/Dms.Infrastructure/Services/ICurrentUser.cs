using Dms.Domain;

namespace Dms.Infrastructure.Services;

/// <summary>
/// المستخدم الحالي للطلب — يُشتق من الـ JWT في طبقة الـ API.
/// تستخدمه DbContext لفرض العزل الصفّي حسب الشركة.
/// </summary>
public interface ICurrentUser
{
    bool IsAuthenticated { get; }
    int? UserId { get; }
    UserRole? Role { get; }

    /// <summary>الشركة الفعّالة لهذا الطلب (null للسوبر أدمن عند رؤية الكل).</summary>
    int? ActiveCompanyId { get; }

    bool IsSuperAdmin { get; }

    /// <summary>هل يملك المستخدم علم صلاحية الاعتماد (من الـ JWT)؟</summary>
    bool CanApprove { get; }

    /// <summary>هل يملك المستخدم صلاحية إدارة حالات الكتب الواردة (من الـ JWT)؟</summary>
    bool CanManageIncoming { get; }

    /// <summary>
    /// هل يرى **كل** الوارد والأرشيف في الشركة الفعّالة متجاوزاً حدود القسم؟ (من الـ JWT)
    /// </summary>
    /// <remarks>قراءة خالصة — لا تمنح إحالةً ولا تغييرَ حالة.</remarks>
    bool CanViewAllIncoming { get; }

    /// <summary>هل يملك صلاحية **كتابة** بطاقات الموظفين في الشركة الفعّالة؟ (من الـ JWT)</summary>
    /// <remarks>القسم يفتح الرؤية وهذا يفتح الكتابة (ADR-025).</remarks>
    bool CanManageEmployees { get; }

    /// <summary>هل يملك صلاحية **كتابة** كشوف الرواتب في الشركة الفعّالة؟ (من الـ JWT)</summary>
    /// <remarks>
    /// ⚠️ **مفصولٌ عن <see cref="CanManageEmployees"/>** — مَن يُدخل بيانات الموظفين ليس
    /// بالضرورة مَن يصرف رواتبهم (ADR-025).
    /// </remarks>
    bool CanManagePayroll { get; }

    /// <summary>قسم المستخدم (من الـ JWT) — يحدّد أي كتب واردة محالة يراها. null إن لم يُسنَد لقسم.</summary>
    int? DepartmentId { get; }

    /// <summary>قائمة الشركات المسموح للمستخدم بالوصول إليها.</summary>
    List<int> AllowedCompanyIds { get; }

    /// <summary>الأقسام المسموح للمستخدم بالوصول إليها (السوبر أدمن ورئيس الشركة = الكل).</summary>
    AppModule AllowedModules { get; }

    /// <summary>هل يملك المستخدم صلاحية الوصول للقسم المحدّد؟</summary>
    bool HasModule(AppModule module) => (AllowedModules & module) == module;
}

/// <summary>تطبيق فارغ — لزمن التصميم (Migrations) وللعمليات الخلفية بلا مستخدم.</summary>
public sealed class SystemUser : ICurrentUser
{
    public bool IsAuthenticated => false;
    public int? UserId => null;
    public UserRole? Role => null;
    public int? ActiveCompanyId => null;
    public bool IsSuperAdmin => true; // النظام يرى الكل (لا فلترة)
    public bool CanApprove => true;
    public bool CanManageIncoming => true;
    public bool CanViewAllIncoming => true;   // النظام يرى الكل (لا فلترة)
    public bool CanManageEmployees => true;
    public bool CanManagePayroll => true;
    public int? DepartmentId => null;
    public List<int> AllowedCompanyIds => new();
    public AppModule AllowedModules => AppModule.AllWithHr;
}
