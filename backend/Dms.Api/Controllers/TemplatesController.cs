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
public sealed class TemplatesController(
    AppDbContext db, ICurrentUser current, IFileStorage storage, IAuditService audit) : ControllerBase
{
    private static readonly string[] AllowedImageTypes = ["image/png", "image/jpeg"];

    [HttpGet]
    public async Task<ActionResult<List<TemplateResponse>>> List(CancellationToken ct)
        => await db.Templates.OrderBy(t => t.Name).Select(Project).ToListAsync(ct);

    [HttpGet("{id:int}")]
    public async Task<ActionResult<TemplateResponse>> Get(int id, CancellationToken ct)
    {
        var t = await db.Templates.Where(x => x.TemplateId == id).Select(Project).FirstOrDefaultAsync(ct)
                ?? throw new NotFoundException("القالب غير موجود.");
        return t;
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<TemplateResponse>> Create(TemplateRequest req, CancellationToken ct)
    {
        var companyId = ResolveCompany(req.CompanyId);
        if (!await db.Companies.AnyAsync(c => c.CompanyId == companyId, ct))
            throw new ValidationException("الشركة غير موجودة.");

        var t = new Template
        {
            CompanyId = companyId,
            Name = req.Name.Trim(),
            WatermarkOpacity = Math.Clamp(req.WatermarkOpacity, 0, 100),
            MarginTop = req.MarginTop,
            MarginRight = req.MarginRight,
            MarginBottom = req.MarginBottom,
            MarginLeft = req.MarginLeft,
            PageSize = string.IsNullOrWhiteSpace(req.PageSize) ? "A4" : req.PageSize,
            FontFamily = string.IsNullOrWhiteSpace(req.FontFamily) ? "Amiri" : req.FontFamily,
            IsActive = req.IsActive,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
        };
        db.Templates.Add(t);
        audit.Add("Create", nameof(Template), null, $"قالب {t.Name}", companyId);
        await db.SaveChangesAsync(ct);
        return await Get(t.TemplateId, ct);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<TemplateResponse>> Update(int id, TemplateRequest req, CancellationToken ct)
    {
        var t = await db.Templates.FirstOrDefaultAsync(x => x.TemplateId == id, ct)
                ?? throw new NotFoundException("القالب غير موجود.");
        t.Name = req.Name.Trim();
        t.WatermarkOpacity = Math.Clamp(req.WatermarkOpacity, 0, 100);
        t.MarginTop = req.MarginTop;
        t.MarginRight = req.MarginRight;
        t.MarginBottom = req.MarginBottom;
        t.MarginLeft = req.MarginLeft;
        t.PageSize = string.IsNullOrWhiteSpace(req.PageSize) ? "A4" : req.PageSize;
        t.FontFamily = string.IsNullOrWhiteSpace(req.FontFamily) ? "Amiri" : req.FontFamily;
        t.IsActive = req.IsActive;
        t.UpdatedAt = DateTime.UtcNow;
        audit.Add("Update", nameof(Template), id.ToString(), null, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return await Get(id, ct);
    }

    [HttpPost("{id:int}/images/{kind}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> UploadImage(int id, string kind, IFormFile file, CancellationToken ct)
    {
        var t = await db.Templates.FirstOrDefaultAsync(x => x.TemplateId == id, ct)
                ?? throw new NotFoundException("القالب غير موجود.");
        if (file is null || file.Length == 0) throw new ValidationException("الملف فارغ.");
        if (!AllowedImageTypes.Contains(file.ContentType))
            throw new ValidationException("نوع الصورة يجب أن يكون PNG أو JPEG.");

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var key = await storage.SaveAsync($"tpl-{id}-{kind}{Path.GetExtension(file.FileName)}", ms.ToArray(), ct);

        switch (kind.ToLowerInvariant())
        {
            case "header": t.HeaderImageKey = key; break;
            case "footer": t.FooterImageKey = key; break;
            case "watermark": t.WatermarkImageKey = key; break;
            default: throw new ValidationException("نوع الصورة غير معروف (header/footer/watermark).");
        }
        t.UpdatedAt = DateTime.UtcNow;
        audit.Add("UploadImage", nameof(Template), id.ToString(), kind, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return Ok(new { key });
    }

    [HttpGet("{id:int}/images/{kind}")]
    public async Task<IActionResult> GetImage(int id, string kind, CancellationToken ct)
    {
        var t = await db.Templates.FirstOrDefaultAsync(x => x.TemplateId == id, ct)
                ?? throw new NotFoundException("القالب غير موجود.");
        var key = kind.ToLowerInvariant() switch
        {
            "header" => t.HeaderImageKey,
            "footer" => t.FooterImageKey,
            "watermark" => t.WatermarkImageKey,
            _ => throw new ValidationException("نوع الصورة غير معروف."),
        };
        if (key is null || !await storage.ExistsAsync(key, ct)) throw new NotFoundException("الصورة غير موجودة.");
        var bytes = await storage.ReadAsync(key, ct);
        return File(bytes, key.EndsWith(".png") ? "image/png" : "image/jpeg");
    }

    private int ResolveCompany(int? requested)
        => current.ActiveCompanyId ?? requested
           ?? throw new ValidationException("حدّد الشركة.");

    private static readonly System.Linq.Expressions.Expression<Func<Template, TemplateResponse>> Project =
        t => new TemplateResponse(
            t.TemplateId, t.CompanyId, t.Name, t.WatermarkOpacity,
            t.MarginTop, t.MarginRight, t.MarginBottom, t.MarginLeft,
            t.PageSize, t.FontFamily, t.IsActive,
            t.HeaderImageKey != null, t.FooterImageKey != null, t.WatermarkImageKey != null);
}
