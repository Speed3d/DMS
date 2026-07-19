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

    public bool CanApprove => _user?.FindFirstValue(DmsClaims.CanApprove) == "1";

    public AppModule AllowedModules
    {
        get
        {
            // السوبر أدمن ورئيس الشركة معفيان — وصول كامل لكل الأقسام.
            if (Role is UserRole.SuperAdmin or UserRole.President) return AppModule.All;
            return int.TryParse(_user?.FindFirstValue(DmsClaims.Modules), out var m) ? (AppModule)m : AppModule.None;
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
