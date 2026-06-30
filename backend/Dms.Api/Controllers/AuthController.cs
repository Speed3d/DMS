using Dms.Api.Dtos;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class AuthController(IAuthService auth, ICurrentUser current) : ControllerBase
{
    [AllowAnonymous]
    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest req, CancellationToken ct)
    {
        var r = await auth.LoginAsync(req.Username, req.Password, ct);
        return Map(r);
    }

    [AllowAnonymous]
    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest req, CancellationToken ct)
    {
        var r = await auth.RefreshAsync(req.RefreshToken, ct);
        return Map(r);
    }

    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(RefreshRequest req, CancellationToken ct)
    {
        await auth.LogoutAsync(req.RefreshToken, ct);
        return NoContent();
    }

    [Authorize]
    [HttpGet("me")]
    public ActionResult<MeResponse> Me()
        => new MeResponse(current.UserId!.Value, User.Identity!.Name ?? "",
            User.Identity!.Name ?? "", current.Role!.Value, current.ActiveCompanyId, current.CanApprove);

    [Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest req, CancellationToken ct)
    {
        await auth.ChangePasswordAsync(current.UserId!.Value, req.CurrentPassword, req.NewPassword, ct);
        return NoContent();
    }

    private static AuthResponse Map(AuthResult r) => new(
        r.AccessToken, r.AccessExpires, r.RefreshToken, r.UserId, r.FullName,
        r.Username, r.Role, r.CompanyId, r.CanApprove, r.MustChangePassword);
}
