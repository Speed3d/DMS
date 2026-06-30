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

    public int? ActiveCompanyId
    {
        get
        {
            // المستخدم العادي مقيّد بشركته (claim) — لا يتجاوزها بترويسة.
            if (int.TryParse(_user?.FindFirstValue(DmsClaims.CompanyId), out var cid))
                return cid;
            // السوبر أدمن: شركة فعّالة اختيارية من الترويسة (null = يرى الكل).
            return IsSuperAdmin ? _headerCompanyId : null;
        }
    }
}
