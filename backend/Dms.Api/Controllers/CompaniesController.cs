using Dms.Api.Auth;
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
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        return await q.OrderBy(c => c.Name)
            .Select(c => new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey))
            .ToListAsync(ct);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CompanyResponse>> Get(int id, CancellationToken ct)
    {
        // متسق مع List/Update: غير السوبر أدمن يرى أي شركة مسموحة له (لا الشركة النشطة فقط).
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");
        return new CompanyResponse(c.CompanyId, c.Name, c.Prefix, c.IsActive, c.DefaultSignatoryName, c.DefaultSignatoryTitle, c.LogoImageKey);
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
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
    [RequireModule(AppModule.Settings)]
    public async Task<ActionResult<CompanyResponse>> Update(int id, CompanyRequest req, CancellationToken ct)
    {
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
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
    [RequireModule(AppModule.Settings)]
    public async Task<IActionResult> UploadLogo(int id, IFormFile file, CancellationToken ct)
    {
        var q = db.Companies.IgnoreQueryFilters().AsQueryable();
        if (!currentUser.IsSuperAdmin)
        {
            var allowed = currentUser.AllowedCompanyIds;
            q = q.Where(c => allowed.Contains(c.CompanyId));
        }

        var c = await q.FirstOrDefaultAsync(x => x.CompanyId == id, ct)
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

    /// <summary>
    /// حذف جذري للشركة — SuperAdmin فقط، ومحروس: يُمنع إن كان للشركة كتاب صادر معتمد أو أرشيف
    /// (سجلات رسمية). للتوقّف عن استخدام شركة دون فقدان بيانات، استخدم «تعطيل» (IsActive=false).
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin")]
    [RequireModule(AppModule.Settings)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var c = await db.Companies.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.CompanyId == id, ct)
                ?? throw new NotFoundException("الشركة غير موجودة.");

        // تحقّق مسبق: لا يجوز محو سجلات رسمية (كتب معتمدة أو أرشيف). المسودات تُحذف مع الشركة.
        var hasApproved = await db.OutgoingBooks.IgnoreQueryFilters()
            .AnyAsync(b => b.CompanyId == id && b.Status == BookStatus.Final, ct);
        var hasArchive = await db.ArchiveDocs.IgnoreQueryFilters()
            .AnyAsync(a => a.CompanyId == id, ct);
        if (hasApproved || hasArchive)
            throw new ConflictException("لا يمكن حذف شركة لها كتب صادرة معتمدة أو أرشيف. عطّل الشركة بدل حذفها.");

        // اجمع كل مفاتيح التخزين قبل الحذف لتنظيفها بعد نجاح المعاملة (شعار/صور قوالب/مسودات PDF/مرفقات).
        var blobKeys = new List<string>();
        if (!string.IsNullOrEmpty(c.LogoImageKey)) blobKeys.Add(c.LogoImageKey);

        var templateKeys = await db.Templates.IgnoreQueryFilters().Where(t => t.CompanyId == id)
            .Select(t => new { t.HeaderImageKey, t.FooterImageKey, t.WatermarkImageKey }).ToListAsync(ct);
        foreach (var t in templateKeys)
        {
            if (!string.IsNullOrEmpty(t.HeaderImageKey)) blobKeys.Add(t.HeaderImageKey);
            if (!string.IsNullOrEmpty(t.FooterImageKey)) blobKeys.Add(t.FooterImageKey);
            if (!string.IsNullOrEmpty(t.WatermarkImageKey)) blobKeys.Add(t.WatermarkImageKey);
        }

        var bookIds = await db.OutgoingBooks.IgnoreQueryFilters().Where(b => b.CompanyId == id)
            .Select(b => b.OutgoingId).ToListAsync(ct);
        blobKeys.AddRange(await db.OutgoingBooks.IgnoreQueryFilters()
            .Where(b => b.CompanyId == id && b.GeneratedPdfBlobKey != null)
            .Select(b => b.GeneratedPdfBlobKey!).ToListAsync(ct));
        blobKeys.AddRange(await db.Attachments
            .Where(a => a.OwnerType == OwnerType.Outgoing && bookIds.Contains(a.OwnerId))
            .Select(a => a.BlobKey).ToListAsync(ct));

        // العملية كوحدة قابلة لإعادة المحاولة (ADR-008 — EnableRetryOnFailure مُفعّل).
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            db.Attachments.RemoveRange(db.Attachments.Where(a => a.OwnerType == OwnerType.Outgoing && bookIds.Contains(a.OwnerId)));
            db.DocumentVersions.RemoveRange(db.DocumentVersions.Where(v => v.DocType == OwnerType.Outgoing && bookIds.Contains(v.DocId)));
            db.OutgoingBooks.RemoveRange(db.OutgoingBooks.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.UserCompanies.RemoveRange(db.UserCompanies.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.ApprovalDelegations.RemoveRange(db.ApprovalDelegations.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Templates.RemoveRange(db.Templates.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Entities.RemoveRange(db.Entities.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.DocumentTypes.RemoveRange(db.DocumentTypes.IgnoreQueryFilters().Where(x => x.CompanyId == id));
            db.Counters.RemoveRange(db.Counters.Where(x => x.CompanyId == id));

            // فكّ ربط المستخدمين الذين شركتهم الرئيسية هي هذه الشركة.
            var primaryUsers = await db.Users.IgnoreQueryFilters().Where(u => u.CompanyId == id).ToListAsync(ct);
            foreach (var u in primaryUsers) u.CompanyId = null;

            db.Companies.Remove(c);
            audit.Add("Delete", nameof(Company), id.ToString(), $"حذف الشركة (بلا سجلات رسمية): {c.Name}", null);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });

        // تنظيف التخزين بعد ثبات الـ DB (فشل حذف ملف مفقود لا يُفشل العملية).
        foreach (var key in blobKeys.Distinct())
        {
            try { await storage.DeleteAsync(key, ct); }
            catch { /* تجاهل — الملف قد يكون محذوفاً مسبقاً */ }
        }

        return NoContent();
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
