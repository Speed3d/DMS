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

        var name = req.Name.Trim();
        if (await db.DocumentTypes.AnyAsync(t => t.CompanyId == companyId && t.Name == name, ct))
            throw new ConflictException($"يوجد نوع مستند بالاسم «{name}» في هذه الشركة.");

        var t = new DocumentType { CompanyId = companyId, Name = name };
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
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم النوع مطلوب.");

        var name = req.Name.Trim();
        if (await db.DocumentTypes.AnyAsync(x => x.CompanyId == t.CompanyId && x.Name == name && x.DocumentTypeId != id, ct))
            throw new ConflictException($"يوجد نوع مستند آخر بالاسم «{name}».");

        t.Name = name;
        audit.Add("Update", nameof(DocumentType), id.ToString(), null, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return new DocumentTypeResponse(t.DocumentTypeId, t.CompanyId, t.Name);
    }

    /// <summary>
    /// حذف نوع مستند — مسموح فقط إن لم يكن مستخدَماً في أي كتاب وارد أو مستند أرشيف.
    /// </summary>
    /// <remarks>
    /// Hint: النوع ليس له علَم تعطيل (بخلاف القسم)، والحذف مع وجود مراجع كان سيترك
    /// `DocumentTypeId` يشير إلى صفٍّ محذوف ⇒ يظهر «—» في كتب قديمة بلا تفسير.
    /// نرفض بـ409 ونذكر العدد بدقّة ليعرف المالك حجم الارتباط قبل أن يقرّر.
    /// **`IgnoreQueryFilters` مقصود:** العدّ يجب أن يشمل كل الشركات — سوبر أدمن يحذف نوعاً
    /// من شركة غير فعّالة لديه يجب أن يُمنع أيضاً.
    ///
    /// ⚠️ **لكنه يُلغي فلتر الحذف الناعم كذلك** — ولهذا نستثني المحذوف يدوياً (`!IsDeleted`).
    /// بدونه يبقى كتابٌ حذفه المستخدم قافلاً للنوع **إلى الأبد** بلا أي وسيلة لمعرفة السبب:
    /// الحارس يقول «مستخدَم في كتاب» والمستخدم لا يرى ذلك الكتاب في أي قائمة.
    /// </remarks>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var t = await db.DocumentTypes.FirstOrDefaultAsync(x => x.DocumentTypeId == id, ct)
                ?? throw new NotFoundException("النوع غير موجود.");

        var usedInIncoming = await db.IncomingBooks.IgnoreQueryFilters()
            .CountAsync(b => b.DocumentTypeId == id && !b.IsDeleted, ct);
        var usedInArchive = await db.ArchiveDocs.IgnoreQueryFilters()
            .CountAsync(a => a.DocumentTypeId == id && !a.IsDeleted, ct);
        var used = usedInIncoming + usedInArchive;
        if (used > 0)
            throw new ConflictException(
                $"لا يمكن حذف النوع «{t.Name}» لأنه مستخدَم في {used} سجلّ " +
                $"({usedInIncoming} وارد، {usedInArchive} أرشيف). عدّل اسمه بدل حذفه.");

        db.DocumentTypes.Remove(t);
        audit.Add("Delete", nameof(DocumentType), id.ToString(), t.Name, t.CompanyId);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}
