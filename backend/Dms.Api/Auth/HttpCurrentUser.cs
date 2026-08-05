using System.Security.Claims;
using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Services;

namespace Dms.Api.Auth;

/// <summary>
/// المستخدم الحالي مشتقاً من الـ JWT.
/// الشركة الفعّالة: من claim الشركة للمستخدم العادي؛ للسوبر أدمن من ترويسة X-Company-Id (اختياري).
/// </summary>
public sealed class HttpCurrentUser : ICurrentUser
{
    private readonly ClaimsPrincipal? _user;
    private readonly int? _headerCompanyId;

    public HttpCurrentUser(IHttpContextAccessor accessor)
    {
        var ctx = accessor.HttpContext;
        _user = ctx?.User;
        if (ctx is not null && ctx.Request.Headers.TryGetValue("X-Company-Id", out var raw)
            && int.TryParse(raw, out var cid))
            _headerCompanyId = cid;
    }

    public bool IsAuthenticated => _user?.Identity?.IsAuthenticated ?? false;

    public int? UserId =>
        int.TryParse(_user?.FindFirstValue(DmsClaims.UserId), out var id) ? id : null;

    public UserRole? Role =>
        Enum.TryParse<UserRole>(_user?.FindFirstValue(DmsClaims.Role), out var r) ? r : null;

    public bool IsSuperAdmin => Role == UserRole.SuperAdmin;

    // ── الصلاحيات والقسم: قيمة **كل شركة على حدة** (ADR-017) ──
    // تُقرأ من خريطة في الـclaim وتُنتقى بالشركة الفعّالة. شركة خارج الخريطة ⇒ لا صلاحية
    // ولا قسم (فشل مغلق، كما نصّت ADR-012).

    private int? PerCompany(string claim) =>
        PerCompanyClaim.Read(_user?.FindFirstValue(claim), ActiveCompanyId);

    public bool CanApprove => PerCompany(DmsClaims.CanApprove) == 1;

    public bool CanManageIncoming => PerCompany(DmsClaims.CanManageIncoming) == 1;

    public bool CanViewAllIncoming => PerCompany(DmsClaims.CanViewAllIncoming) == 1;

    /// <summary>كتابة بطاقات الموظفين: **السوبر أدمن ورئيس الشركة دائماً**، وغيرهما بالعلَم.</summary>
    /// <remarks>
    /// ⚠️ الإعفاء بالدور **داخل الخاصية نفسها** (كما في <see cref="AllowedModules"/> أدناه)
    /// لا في كل خدمة على حدة: السوبر أدمن قد يكون **بلا إسناد لأي شركة**، فلا يحمل توكنه
    /// خريطةَ العلَم أصلاً وتعود القراءة `null` ⇒ يُحجب عن وحدةٍ يملكها بحكم دوره.
    /// (وهذا ما جعل `/me` يُرجع `canManageHR=false` لحساب الأدمن في أول تشغيل حيّ.)
    ///
    /// و**رئيس الشركة فأعلى** لا «المدير فأعلى» — خلافاً لنمط <c>EffectiveCanApprove</c>:
    /// لو أُعفي المدير بدوره لما بقي للعلَم معنى، وهو الفرق بين مَن **يرى** ومَن **يحرّر**.
    /// </remarks>
    public bool CanManageEmployees =>
        Role is UserRole.SuperAdmin or UserRole.President
        || PerCompany(DmsClaims.CanManageEmployees) == 1;

    /// <summary>كتابة كشوف الرواتب — علَمٌ مستقلّ (ADR-025)، والإعفاء بالدور نفسه.</summary>
    public bool CanManagePayroll =>
        Role is UserRole.SuperAdmin or UserRole.President
        || PerCompany(DmsClaims.CanManagePayroll) == 1;

    /// <summary>**تعديل شهرٍ مُسدَّد** — بالدور (سوبر أدمن/رئيس) أو بالعلَم (ADR-026).</summary>
    /// <remarks>
    /// ⚠️ **«خياران» بقرار المالك**: طريقٌ بالدور لا يحتاج منحاً، وطريقٌ بالمنح لمديرٍ
    /// يحتاجها. ولولا الأول لاحتاج السوبر أدمن نفسه منحاً — وهو قد يكون بلا إسنادٍ لأي
    /// شركة فلا يحمل توكنه الخريطة أصلاً (العيب الذي انكشف حيّاً في `canManageHR`).
    /// </remarks>
    public bool CanAmendPaidPayroll =>
        Role is UserRole.SuperAdmin or UserRole.President
        || PerCompany(DmsClaims.CanAmendPaidPayroll) == 1;

    public int? DepartmentId => PerCompany(DmsClaims.DepartmentId);

    public AppModule AllowedModules
    {
        get
        {
            // السوبر أدمن ورئيس الشركة معفيان — وصول كامل في كل شركاتهم، **بما فيه HR**.
            // (`AllWithHr` لا `All`: الأخيرة تعمّدت استثناء HR لأنها الافتراض في مواضع صامتة.)
            if (Role is UserRole.SuperAdmin or UserRole.President) return AppModule.AllWithHr;
            return PerCompany(DmsClaims.Modules) is { } m ? (AppModule)m : AppModule.None;
        }
    }

    public List<int> AllowedCompanyIds
    {
        get
        {
            var claim = _user?.FindFirstValue(DmsClaims.CompanyIds);
            if (string.IsNullOrWhiteSpace(claim)) return new List<int>();
            return claim.Split(',').Select(s => int.TryParse(s, out var i) ? i : 0).Where(i => i != 0).ToList();
        }
    }

    public int? ActiveCompanyId
    {
        get
        {
            if (IsSuperAdmin) return _headerCompanyId; // السوبر أدمن: شركة فعّالة اختيارية (null = يرى الكل).
            
            // المستخدم العادي: يجب أن يختار شركة من الشركات المسموحة له.
            var allowed = AllowedCompanyIds;
            if (_headerCompanyId.HasValue && allowed.Contains(_headerCompanyId.Value))
                return _headerCompanyId.Value;
            
            // إذا لم يحدد شركة في الهيدر، أو اختار شركة لا يملكها، نعطيه أول شركة مسموحة افتراضياً.
            return allowed.Any() ? allowed.First() : null;
        }
    }
}
