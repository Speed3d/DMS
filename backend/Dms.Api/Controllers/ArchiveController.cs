using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Attachments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Archive)]
[Route("api/[controller]")]
public sealed class ArchiveController(IArchiveService svc, IAttachmentService attachments) : ControllerBase
{
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
        => Detail(await svc.GetAsync(id, ct));

    [HttpPost]
    public async Task<ActionResult<ArchiveDetail>> Create(ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.CreateAsync(new CreateArchiveInput(
            req.CompanyId, req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml), ct);
        return Detail(doc);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ArchiveDetail>> Update(int id, ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.UpdateAsync(id, new UpdateArchiveInput(
            req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml), ct);
        return Detail(doc);
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

    private static ArchiveDetail Detail(ArchiveDoc a) => new(
        a.ArchiveId, a.CompanyId, a.ArchiveNumber, a.Title, a.BookNumber, a.BookDate,
        a.FromEntityId, a.ToEntityId, a.DocumentTypeId,
        a.Amount, a.Currency, a.ExchangeRate, a.AmountInIqd, a.Keywords, a.Notes, a.BodyHtml, a.CreatedAt);
}
