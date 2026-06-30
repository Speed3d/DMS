using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Users;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin,President,Manager")]
[Route("api/[controller]")]
public sealed class UsersController(IUserService users) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<UserResponse>>> List(CancellationToken ct)
        => (await users.ListAsync(ct)).Select(Map).ToList();

    [HttpPost]
    public async Task<ActionResult<UserResponse>> Create(CreateUserRequest req, CancellationToken ct)
    {
        var u = await users.CreateAsync(
            new CreateUserInput(req.FullName, req.Username, req.Password, req.Role, req.CompanyId, req.CanApprove), ct);
        return Map(u);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<UserResponse>> Update(int id, UpdateUserRequest req, CancellationToken ct)
    {
        var u = await users.UpdateAsync(id,
            new UpdateUserInput(req.FullName, req.Role, req.IsActive, req.CanApprove), ct);
        return Map(u);
    }

    [HttpPost("{id:int}/reset-password")]
    public async Task<IActionResult> ResetPassword(int id, ResetPasswordRequest req, CancellationToken ct)
    {
        await users.ResetPasswordAsync(id, req.NewPassword, ct);
        return NoContent();
    }

    private static UserResponse Map(User u) =>
        new(u.UserId, u.FullName, u.Username, u.Role, u.CompanyId, u.CanApprove, u.IsActive, u.MustChangePassword);
}
