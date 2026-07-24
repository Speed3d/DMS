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
    [Authorize(Roles = "SuperAdmin,President,Manager,Employee")]
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

    /// <summary>
    /// حذف جهة — مسموح فقط إن لم تكن مستخدَمة في أي سجلّ.
    /// Hint: الجهة مرتبطة بكتب رسمية (صادر/وارد/أرشيف)؛ حذفها مع وجودها يُفقِد اسم الجهة من سجلات
    ///       لا يجوز المساس بها. نرفض بـ 409 ورسالة تُبيّن أين تُستخدم بدل خطأ قاعدة بيانات غامض.
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var e = await db.Entities.FirstOrDefaultAsync(x => x.EntityId == id, ct)
                ?? throw new NotFoundException("الجهة غير موجودة.");

        // الفحص يشمل المحذوف ناعماً أيضاً (IgnoreQueryFilters) — السجل يبقى ويجب أن يبقى اسم جهته.
        var inOutgoing = await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id, ct);
        var inIncoming = await db.IncomingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id, ct);
        var inArchive = await db.ArchiveDocs.IgnoreQueryFilters()
            .CountAsync(a => a.FromEntityId == id || a.ToEntityId == id, ct);

        if (inOutgoing + inIncoming + inArchive > 0)
        {
            var used = new List<string>();
            if (inOutgoing > 0) used.Add($"{inOutgoing} صادر");
            if (inIncoming > 0) used.Add($"{inIncoming} وارد");
            if (inArchive > 0) used.Add($"{inArchive} أرشيف");
            throw new ConflictException(
                $"لا يمكن حذف الجهة «{e.Name}» لأنها مستخدَمة في: {string.Join(" · ", used)}.");
        }

        db.Entities.Remove(e);
        audit.Add("Delete", nameof(Entity), id.ToString(), e.Name, e.CompanyId);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}
