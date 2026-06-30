using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Users;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin,President,Manager")]
[Route("api/[controller]")]
public sealed class DelegationsController(IDelegationService delegations) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<DelegationResponse>>> List(CancellationToken ct)
        => (await delegations.ListAsync(ct)).Select(Map).ToList();

    [HttpPost]
    public async Task<ActionResult<DelegationResponse>> Create(CreateDelegationRequest req, CancellationToken ct)
    {
        var d = await delegations.CreateAsync(new CreateDelegationInput(req.ToUserId, req.StartDate, req.EndDate), ct);
        return Map(d);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Revoke(int id, CancellationToken ct)
    {
        await delegations.RevokeAsync(id, ct);
        return NoContent();
    }

    private static DelegationResponse Map(ApprovalDelegation d) =>
        new(d.DelegationId, d.FromUserId, d.ToUserId, d.StartDate, d.EndDate, d.IsActive);
}
