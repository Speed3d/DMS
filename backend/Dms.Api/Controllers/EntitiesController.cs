using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public sealed class EntitiesController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<EntityResponse>>> List(CancellationToken ct)
        => await db.Entities.OrderBy(e => e.Name)
            .Select(e => new EntityResponse(e.EntityId, e.CompanyId, e.Name, e.Kind, e.Notes)).ToListAsync(ct);

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<EntityResponse>> Create(EntityRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم الجهة مطلوب.");
        var companyId = current.ActiveCompanyId ?? req.CompanyId ?? throw new ValidationException("حدّد الشركة.");
        var e = new Entity { CompanyId = companyId, Name = req.Name.Trim(), Kind = req.Kind, Notes = req.Notes };
        db.Entities.Add(e);
        audit.Add("Create", nameof(Entity), null, e.Name, companyId);
        await db.SaveChangesAsync(ct);
        return new EntityResponse(e.EntityId, e.CompanyId, e.Name, e.Kind, e.Notes);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<EntityResponse>> Update(int id, EntityRequest req, CancellationToken ct)
    {
        var e = await db.Entities.FirstOrDefaultAsync(x => x.EntityId == id, ct)
                ?? throw new NotFoundException("الجهة غير موجودة.");
        e.Name = req.Name.Trim();
        e.Kind = req.Kind;
        e.Notes = req.Notes;
        audit.Add("Update", nameof(Entity), id.ToString(), null, e.CompanyId);
        await db.SaveChangesAsync(ct);
        return new EntityResponse(e.EntityId, e.CompanyId, e.Name, e.Kind, e.Notes);
    }
}
