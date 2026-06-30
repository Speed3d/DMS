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
[Route("api/document-types")]
public sealed class DocumentTypesController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<DocumentTypeResponse>>> List(CancellationToken ct)
        => await db.DocumentTypes.OrderBy(t => t.Name)
            .Select(t => new DocumentTypeResponse(t.DocumentTypeId, t.CompanyId, t.Name)).ToListAsync(ct);

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<DocumentTypeResponse>> Create(DocumentTypeRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم النوع مطلوب.");
        var companyId = current.ActiveCompanyId ?? req.CompanyId ?? throw new ValidationException("حدّد الشركة.");
        var t = new DocumentType { CompanyId = companyId, Name = req.Name.Trim() };
        db.DocumentTypes.Add(t);
        audit.Add("Create", nameof(DocumentType), null, t.Name, companyId);
        await db.SaveChangesAsync(ct);
        return new DocumentTypeResponse(t.DocumentTypeId, t.CompanyId, t.Name);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<DocumentTypeResponse>> Update(int id, DocumentTypeRequest req, CancellationToken ct)
    {
        var t = await db.DocumentTypes.FirstOrDefaultAsync(x => x.DocumentTypeId == id, ct)
                ?? throw new NotFoundException("النوع غير موجود.");
        t.Name = req.Name.Trim();
        audit.Add("Update", nameof(DocumentType), id.ToString(), null, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return new DocumentTypeResponse(t.DocumentTypeId, t.CompanyId, t.Name);
    }
}
