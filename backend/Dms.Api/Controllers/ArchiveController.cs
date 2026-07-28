using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Archive)]
[Route("api/[controller]")]
public sealed class ArchiveController(
    IArchiveService svc,
    IAttachmentService attachments,
    AppDbContext db,
    IIncomingService incomingService,
    ICurrentUser current) : ControllerBase
{
    /// <summary>
    /// **عدسة الأرشيف**: عرض موحّد يجمع الوارد المؤرشف والأضابير الورقية، مرتّباً بالأحدث.
    /// </summary>
    /// <remarks>
    /// 🔐 **حدّ الصلاحية مزدوج على صفوف الوارد:** الوصول لهذه النقطة يتطلّب قسم «الأرشيف»
    /// (سِمة الصنف)، لكن صفوف الوارد المؤرشف **تتطلّب قسم «الوارد» أيضاً**. بدون هذا الشرط
    /// يصير الأرشيف **باباً خلفياً** يقرأ منه صاحبُ صلاحية الأرشيف كتبَ الوارد التي لا يملك
    /// رؤيتها — وهي بيانات محجوبة عنه في `/api/incoming` بحرّاسها.
    ///
    /// 🔐 **ورؤية الصفوف تُبنى على `IncomingService.Query()` نفسها** لا بإعادة كتابة الشرط:
    /// قاعدة الرؤية (ما استلمه · ما أُحيل لقسمه · ما أحاله بنفسه) تطوّرت مرّتين (ADR-015 ثم
    /// ADR-018)، ونسخةٌ ثانية منها هنا كانت ستتخلّف عن الأصل عند أي تعديل ثالث فتُسرّب أو تحجب.
    /// </remarks>
    [HttpGet("lens")]
    public async Task<ActionResult<List<ArchiveLensItem>>> Lens(
        [FromQuery] string? search, [FromQuery] int? year, [FromQuery] int? departmentId,
        CancellationToken ct = default)
    {
        var items = new List<ArchiveLensItem>();

        // ---- المصدر الأول: الوارد المؤرشف (يتطلّب قسم الوارد أيضاً) ----
        if (current.HasModule(AppModule.Incoming))
        {
            var q = incomingService.Query()
                .Where(b => b.Status == IncomingStatus.Archived)
                .Include(b => b.Entity)
                .Include(b => b.Assignments).ThenInclude(a => a.Department)
                .AsQueryable();

            if (!string.IsNullOrWhiteSpace(search))
                q = q.Where(b => (b.IncomingNumber != null && b.IncomingNumber.Contains(search))
                                 || b.Subject.Contains(search)
                                 || (b.Keywords != null && b.Keywords.Contains(search)));

            if (departmentId.HasValue)
                q = q.Where(b => b.Assignments.Any(a => a.DepartmentId == departmentId.Value));

            var books = await q.ToListAsync(ct);
            var typeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

            items.AddRange(books.Select(b =>
            {
                // Hint: `UpdatedAt` هو تاريخ الأرشفة فعلياً — التعديل ممنوع بعدها، فآخر
                //       تحديث للكتاب هو لحظة أرشفته. فلا حاجة لعمود جديد ولا مهاجرة.
                var archivedAt = b.UpdatedAt ?? b.CreatedAt;
                return new ArchiveLensItem(
                    ArchiveSource.Incoming, b.IncomingId, b.IncomingNumber ?? "—", b.Subject,
                    archivedAt, archivedAt.Year, archivedAt.Month,
                    b.Entity?.Name,
                    b.DocumentTypeId is not null && typeNames.TryGetValue(b.DocumentTypeId.Value, out var tn) ? tn : null,
                    b.Assignments.Select(a => a.Department?.Name ?? "—").ToList(),
                    b.Notes);
            }));
        }

        // ---- المصدر الثاني: الأضابير الورقية القديمة ----
        var docs = await svc.SearchAsync(new ArchiveSearchInput(search, null, null, null, null), ct);
        var docTypeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

        items.AddRange(docs
            .Where(a => !departmentId.HasValue || a.DepartmentId == departmentId.Value)
            .Select(a =>
            {
                // تاريخ الكتاب الأصلي أدقّ للأضبارة القديمة من تاريخ إدخالها في النظام.
                var at = a.BookDate ?? a.CreatedAt;
                return new ArchiveLensItem(
                    ArchiveSource.Paper, a.ArchiveId, a.ArchiveNumber, a.Title,
                    at, at.Year, at.Month, null,
                    a.DocumentTypeId is not null && docTypeNames.TryGetValue(a.DocumentTypeId.Value, out var tn) ? tn : null,
                    a.Department?.Name is null ? [] : [a.Department.Name],
                    a.Notes);
            }));

        if (year.HasValue) items = items.Where(i => i.Year == year.Value).ToList();

        return items.OrderByDescending(i => i.ArchivedAt).ToList();
    }

    [HttpGet]
    public async Task<ActionResult<List<ArchiveListItem>>> List(
        [FromQuery] string? search, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? documentTypeId, [FromQuery] int? entityId, CancellationToken ct = default)
    {
        var docs = await svc.SearchAsync(new ArchiveSearchInput(search, from, to, documentTypeId, entityId), ct);
        return docs.Select(a => new ArchiveListItem(
            a.ArchiveId, a.ArchiveNumber, a.Title, a.BookNumber, a.BookDate,
            a.DocumentTypeId, a.AmountInIqd, a.CreatedAt)).ToList();
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ArchiveDetail>> Get(int id, CancellationToken ct)
        => await DetailAsync(await svc.GetAsync(id, ct), ct);

    [HttpPost]
    public async Task<ActionResult<ArchiveDetail>> Create(ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.CreateAsync(new CreateArchiveInput(
            req.CompanyId, req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml,
            req.DepartmentId), ct);
        return await DetailAsync(doc, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ArchiveDetail>> Update(int id, ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.UpdateAsync(id, new UpdateArchiveInput(
            req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml,
            req.DepartmentId), ct);
        return await DetailAsync(doc, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await svc.SoftDeleteAsync(id, ct);
        return NoContent();
    }

    // ----- المرفقات -----
    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> ListAttachments(int id, CancellationToken ct)
    {
        var list = await attachments.ListAsync(OwnerType.Archive, id, ct);
        return list.Select(a => new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt)).ToList();
    }

    [HttpPost("{id:int}/attachments")]
    public async Task<ActionResult<AttachmentResponse>> AddAttachment(int id, IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) throw new ValidationException("الملف فارغ.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var a = await attachments.AddAsync(OwnerType.Archive, id, file.FileName, ms.ToArray(), ct);
        return new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt);
    }

    /// <summary>يحوّل المستند إلى DTO ويُحلّ اسمَي نوع المستند والقسم من معرّفيهما.</summary>
    private async Task<ArchiveDetail> DetailAsync(ArchiveDoc a, CancellationToken ct)
    {
        var typeName = a.DocumentTypeId is null
            ? null
            : await db.DocumentTypes.Where(t => t.DocumentTypeId == a.DocumentTypeId)
                .Select(t => t.Name).FirstOrDefaultAsync(ct);

        var deptName = a.DepartmentId is null
            ? null
            : await db.Departments.Where(d => d.DepartmentId == a.DepartmentId)
                .Select(d => d.Name).FirstOrDefaultAsync(ct);

        return new ArchiveDetail(
            a.ArchiveId, a.CompanyId, a.ArchiveNumber, a.Title, a.BookNumber, a.BookDate,
            a.FromEntityId, a.ToEntityId, a.DocumentTypeId,
            a.Amount, a.Currency, a.ExchangeRate, a.AmountInIqd, a.Keywords, a.Notes, a.BodyHtml, a.CreatedAt,
            typeName, a.DepartmentId, deptName);
    }
}
