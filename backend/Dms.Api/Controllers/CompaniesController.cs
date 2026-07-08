using Dms.Api.Dtos;
using Dms.Documents.Storage;
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
public sealed class CompaniesController(AppDbContext db, IAuditService audit, IFileStorage storage, ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<CompanyResponse>>> List(CancellationToken ct)
    {
        var q = db.Companies.AsQueryable();
        if (currentUser.IsSuperAdmin) q = q.IgnoreQueryFilters();

        return await q.OrderBy(c => c.Name)
            .Select(c => new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey))
            .ToListAsync(ct);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CompanyResponse>> Get(int id, CancellationToken ct)
    {
        var q = db.Companies.AsQueryable();
        if (currentUser.IsSuperAdmin) q = q.IgnoreQueryFilters();

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
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
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
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
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
    }

    [HttpPost("{id:int}/logo")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> UploadLogo(int id, IFormFile file, CancellationToken ct)
    {
        var c = await db.Companies.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");

        var allowedTypes = new[] { "image/png", "image/jpeg" };
        if (!allowedTypes.Contains(file.ContentType.ToLowerInvariant()))
            throw new ValidationException("يُسمح فقط بملفات PNG و JPG.");
        if (file.Length > 2 * 1024 * 1024)
            throw new ValidationException("حجم الصورة يجب ألا يتجاوز 2 ميغابايت.");

        if (!string.IsNullOrEmpty(c.LogoImageKey))
            await storage.DeleteAsync(c.LogoImageKey, ct);

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var key = await storage.SaveAsync($"company_{id}_logo_{Guid.NewGuid():N}.img", ms.ToArray(), ct);

        c.LogoImageKey = key;
        audit.Add("UploadLogo", nameof(Company), id.ToString(), null, id);
        await db.SaveChangesAsync(ct);

        return Ok();
    }

    [HttpGet("{id:int}/logo")]
    [AllowAnonymous]
    public async Task<IActionResult> GetLogo(int id, CancellationToken ct)
    {
        var c = await db.Companies.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.CompanyId == id, ct);
        if (c == null || string.IsNullOrEmpty(c.LogoImageKey))
            return NotFound();

        var bytes = await storage.ReadAsync(c.LogoImageKey, ct);
        if (bytes == null || bytes.Length == 0) return NotFound();

        return File(bytes, "image/png");
    }
}
