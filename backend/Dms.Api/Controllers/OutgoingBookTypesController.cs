using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

/// <summary>
/// أنواع الكتاب الصادر (ADR-057) — كتاب رسمي · فاتورة · عرض سعر · وما يضيفه المالك.
/// </summary>
/// <remarks>
/// 🔑 **نظيرُ <see cref="DocumentTypesController"/> حرفاً بحرف** (القراءة لكل مصادَق · الكتابة للسوبر أدمن والرئيس
/// والمدير · اسمٌ فريدٌ في الشركة · الحذف يُرفض إن كان مستعملاً) — والقائمة منفصلةٌ بقرار المالك.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/outgoing-book-types")]
public sealed class OutgoingBookTypesController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<OutgoingBookTypeResponse>>> List(CancellationToken ct)
        => await db.OutgoingBookTypes.OrderBy(t => t.OutgoingBookTypeId)
            .Select(t => new OutgoingBookTypeResponse(t.OutgoingBookTypeId, t.CompanyId, t.Name)).ToListAsync(ct);

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<OutgoingBookTypeResponse>> Create(OutgoingBookTypeRequest req, CancellationToken ct)
    {
        var name = RequireName(req.Name);
        var companyId = current.ActiveCompanyId ?? req.CompanyId ?? throw new ValidationException("حدّد الشركة.");
        if (await db.OutgoingBookTypes.AnyAsync(t => t.CompanyId == companyId && t.Name == name, ct))
            throw new ConflictException($"يوجد نوع كتابٍ صادر بالاسم «{name}» في هذه الشركة.");

        var t = new OutgoingBookType { CompanyId = companyId, Name = name };
        db.OutgoingBookTypes.Add(t);
        audit.Add("Create", nameof(OutgoingBookType), null, t.Name, companyId);
        await db.SaveChangesAsync(ct);
        return new OutgoingBookTypeResponse(t.OutgoingBookTypeId, t.CompanyId, t.Name);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<OutgoingBookTypeResponse>> Update(int id, OutgoingBookTypeRequest req, CancellationToken ct)
    {
        var t = await db.OutgoingBookTypes.FirstOrDefaultAsync(x => x.OutgoingBookTypeId == id, ct)
                ?? throw new NotFoundException("النوع غير موجود.");
        var name = RequireName(req.Name);
        if (await db.OutgoingBookTypes.AnyAsync(x => x.CompanyId == t.CompanyId && x.Name == name && x.OutgoingBookTypeId != id, ct))
            throw new ConflictException($"يوجد نوع كتابٍ صادر آخر بالاسم «{name}».");

        var old = t.Name;
        t.Name = name;
        audit.Add("Update", nameof(OutgoingBookType), id.ToString(), $"{old} ⟵ {name}", t.CompanyId);
        await db.SaveChangesAsync(ct);
        return new OutgoingBookTypeResponse(t.OutgoingBookTypeId, t.CompanyId, t.Name);
    }

    /// <summary>حذفُ نوعٍ — مسموحٌ إن لم يُستعمل في أيّ كتابٍ صادر قائم (المحذوف ناعماً لا يمنع).</summary>
    /// <remarks>
    /// ⚠️ **والمحذوف ناعماً**: المفتاح الأجنبيّ <c>Restrict</c> يمنع حذف النوع ما دام صفُّ كتابٍ محذوفٍ يشير إليه —
    /// فيُفكّ ارتباطه أوّلاً (يصير بلا نوع)، وإلا بقي النوع مقفولاً «إلى الأبد» بكتابٍ لا يراه أحد (درس DocumentType).
    /// </remarks>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var t = await db.OutgoingBookTypes.FirstOrDefaultAsync(x => x.OutgoingBookTypeId == id, ct)
                ?? throw new NotFoundException("النوع غير موجود.");

        var used = await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(b => b.OutgoingBookTypeId == id && !b.IsDeleted, ct);
        if (used > 0)
            throw new ConflictException($"لا يمكن حذف النوع «{t.Name}» لأنه مستخدَم في {used} كتاب صادر. عدّل اسمه بدل حذفه.");

        await db.OutgoingBooks.IgnoreQueryFilters()
            .Where(b => b.OutgoingBookTypeId == id && b.IsDeleted)
            .ExecuteUpdateAsync(s => s.SetProperty(b => b.OutgoingBookTypeId, (int?)null), ct);
        db.OutgoingBookTypes.Remove(t);
        audit.Add("Delete", nameof(OutgoingBookType), id.ToString(), t.Name, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }

    private static string RequireName(string? name) =>
        string.IsNullOrWhiteSpace(name) ? throw new ValidationException("اسم النوع مطلوب.")
        : name.Trim().Length > 200 ? throw new ValidationException("اسم النوع أطول من 200 حرف.")
        : name.Trim();
}
