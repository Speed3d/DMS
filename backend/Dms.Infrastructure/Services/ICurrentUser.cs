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
    public List<int> AllowedCompanyIds => new();
    public AppModule AllowedModules => AppModule.All;
}
