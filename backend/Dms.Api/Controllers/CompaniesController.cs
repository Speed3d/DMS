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
public sealed class CompaniesController(AppDbContext db, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<CompanyResponse>>> List(CancellationToken ct)
        => await db.Companies.OrderBy(c => c.Name)
            .Select(c => new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle))
            .ToListAsync(ct);

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CompanyResponse>> Get(int id, CancellationToken ct)
    {
        var c = await db.Companies.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle);
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<ActionResult<CompanyResponse>> Create(CompanyRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || string.IsNullOrWhiteSpace(req.Prefix))
            throw new ValidationException("الاسم والرمز مطلوبان.");
        if (await db.Companies.IgnoreQueryFilters().AnyAsync(c => c.Prefix == req.Prefix, ct))
            throw new ConflictException("رمز الترقيم مستخدم بالفعل.");

        var c = new Company
        {
            Name = req.Name.Trim(),
            Prefix = req.Prefix.Trim().ToUpperInvariant(),
            IsActive = req.IsActive,
            DefaultSignatoryName = req.DefaultSignatoryName,
            DefaultSignatoryTitle = req.DefaultSignatoryTitle,
            CreatedAt = DateTime.UtcNow,
        };
        db.Companies.Add(c);
        audit.Add("Create", nameof(Company), null, $"إنشاء شركة {c.Name}", null);
        await db.SaveChangesAsync(ct);
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President")]
    public async Task<ActionResult<CompanyResponse>> Update(int id, CompanyRequest req, CancellationToken ct)
    {
        var c = await db.Companies.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        if (await db.Companies.IgnoreQueryFilters().AnyAsync(x => x.Prefix == req.Prefix && x.CompanyId != id, ct))
            throw new ConflictException("رمز الترقيم مستخدم بالفعل.");

        c.Name = req.Name.Trim();
        c.Prefix = req.Prefix.Trim().ToUpperInvariant();
        c.IsActive = req.IsActive;
        c.DefaultSignatoryName = req.DefaultSignatoryName;
        c.DefaultSignatoryTitle = req.DefaultSignatoryTitle;
        audit.Add("Update", nameof(Company), id.ToString(), null, id);
        await db.SaveChangesAsync(ct);
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle);
    }
}
