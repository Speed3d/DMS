using Dms.Domain;

namespace Dms.Infrastructure.Services;

/// <summary>
/// **لقطةٌ ثابتة من المستخدم الحالي** — تحملها العملية الخلفية بعد أن ينتهي الطلب الذي بدأها.
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **لماذا؟** <c>HttpCurrentUser</c> يقرأ من <c>HttpContext</c>، والعملية الخلفية تعيش
/// **بعد** انتهاء الطلب — فيعود <c>HttpContext</c> فارغاً (أو أسوأ: كائناً أُعيد تدويره لطلبٍ
/// آخر). والنتيجة بلا هذه اللقطة: سطرُ تدقيقٍ **بلا فاعل**، وفلترُ شركةٍ **معطَّل** (غير المصادَق
/// بلا فلترة)، وفحصُ «الشركة الفعّالة» يقرأ لا شيء.
/// </para>
/// <para>
/// ⚠️ **تُؤخذ في لحظة بدء العملية** — فما يراه المنفّذ هو ما كان يملكه حين ضغط الزرّ، لا ما
/// صار له بعده. وهو السلوك نفسه لطلبٍ متزامنٍ طويل.
/// </para>
/// </remarks>
public sealed class CurrentUserSnapshot : ICurrentUser
{
    public bool IsAuthenticated { get; init; }
    public int? UserId { get; init; }
    public UserRole? Role { get; init; }
    public int? ActiveCompanyId { get; init; }
    public bool IsSuperAdmin { get; init; }
    public bool CanApprove { get; init; }
    public bool CanManageIncoming { get; init; }
    public bool CanViewAllIncoming { get; init; }
    public bool CanManageEmployees { get; init; }
    public bool CanManagePayroll { get; init; }
    public bool CanAmendPaidPayroll { get; init; }
    public bool CanManageTasks { get; init; }
    public int? DepartmentId { get; init; }
    public List<int> AllowedCompanyIds { get; init; } = new();
    public AppModule AllowedModules { get; init; }

    public static CurrentUserSnapshot From(ICurrentUser c) => new()
    {
        IsAuthenticated = c.IsAuthenticated,
        UserId = c.UserId,
        Role = c.Role,
        ActiveCompanyId = c.ActiveCompanyId,
        IsSuperAdmin = c.IsSuperAdmin,
        CanApprove = c.CanApprove,
        CanManageIncoming = c.CanManageIncoming,
        CanViewAllIncoming = c.CanViewAllIncoming,
        CanManageEmployees = c.CanManageEmployees,
        CanManagePayroll = c.CanManagePayroll,
        CanAmendPaidPayroll = c.CanAmendPaidPayroll,
        CanManageTasks = c.CanManageTasks,
        DepartmentId = c.DepartmentId,
        AllowedCompanyIds = c.AllowedCompanyIds.ToList(),
        AllowedModules = c.AllowedModules,
    };
}

/// <summary>
/// حاملٌ **لكل نطاق DI** يسمح باستبدال المستخدم الحالي قبل حلّ أيّ خدمة (للعمليات الخلفية).
/// </summary>
/// <remarks>
/// ⚠️ **يُضبط أوّلاً ثم تُحلّ الخدمات** — فـ<c>AppDbContext</c> يقرأ المستخدم في مُنشئه لبناء
/// فلتر الشركة، وضبطُه بعد ذلك لا يغيّر فلتراً بُني.
/// </remarks>
public sealed class CurrentUserOverride
{
    public ICurrentUser? User { get; set; }
}
