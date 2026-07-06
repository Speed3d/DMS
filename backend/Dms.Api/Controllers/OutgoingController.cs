using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Outgoing;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public sealed class OutgoingController(IOutgoingService svc, AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<OutgoingListItem>>> List(
        [FromQuery] BookStatus? status, [FromQuery] string? search, CancellationToken ct = default)
    {
        var q = svc.Query();
        if (status is not null) q = q.Where(b => b.Status == status);
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(b => b.Subject.Contains(search) || (b.Number != null && b.Number.Contains(search)));

        return await q.OrderByDescending(b => b.CreatedAt)
            .Select(b => new OutgoingListItem(
                b.OutgoingId, b.Number, b.Date, b.Subject, b.Entity!.Name,
                b.Status, b.AmountInIqd, b.CreatedAt))
            .ToListAsync(ct);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<OutgoingDetail>> Get(int id, CancellationToken ct)
    {
        var book = await svc.GetAsync(id, ct);
        var entityName = await db.Entities.Where(e => e.EntityId == book.EntityId)
            .Select(e => e.Name).FirstOrDefaultAsync(ct) ?? "";
        return Detail(book, entityName);
    }

    [HttpPost]
    public async Task<ActionResult<OutgoingDetail>> Create(CreateOutgoingRequest req, CancellationToken ct)
    {
        var book = await svc.CreateDraftAsync(new CreateOutgoingInput(
            req.CompanyId, req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate), ct);
        return await Get(book.OutgoingId, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<OutgoingDetail>> Update(int id, UpdateOutgoingRequest req, CancellationToken ct)
    {
        await svc.UpdateDraftAsync(id, new UpdateOutgoingInput(
            req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate), ct);
        return await Get(id, ct);
    }

    [HttpPost("{id:int}/approve")]
    public async Task<ActionResult<OutgoingDetail>> Approve(int id, CancellationToken ct)
    {
        await svc.ApproveAsync(id, ct);
        return await Get(id, ct);
    }

    [HttpPut("{id:int}/edit-approved")]
    public async Task<ActionResult<OutgoingDetail>> EditApproved(int id, EditApprovedRequest req, CancellationToken ct)
    {
        await svc.EditAfterApprovalAsync(id, new EditApprovedInput(
            req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate,
            Convert.FromBase64String(req.RowVersion), req.ChangeNote), ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await svc.SoftDeleteAsync(id, ct);
        return NoContent();
    }

    [HttpGet("{id:int}/versions")]
    public async Task<ActionResult<List<VersionResponse>>> Versions(int id, CancellationToken ct)
    {
        await svc.GetAsync(id, ct); // يتحقق من الرؤية
        return await db.DocumentVersions
            .Where(v => v.DocType == OwnerType.Outgoing && v.DocId == id)
            .OrderByDescending(v => v.VersionNo)
            .Select(v => new VersionResponse(v.VersionNo, v.ChangedAt, v.ChangedByUserId, v.ChangeNote))
            .ToListAsync(ct);
    }

    [HttpGet("{id:int}/pdf")]
    public async Task<IActionResult> Pdf(int id, CancellationToken ct)
    {
        var bytes = await svc.GetPdfAsync(id, ct);
        return File(bytes, "application/pdf");
    }

    [HttpPost("preview")]
    public async Task<IActionResult> Preview(CreateOutgoingRequest req, CancellationToken ct)
    {
        var bytes = await svc.PreviewPdfAsync(new CreateOutgoingInput(
            req.CompanyId, req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate), ct);
        return File(bytes, "application/pdf");
    }

    [HttpGet("{id:int}/word")]
    public async Task<IActionResult> Word(int id, CancellationToken ct)
    {
        var bytes = await svc.GetWordAsync(id, ct);
        return File(bytes, "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            $"outgoing-{id}.docx");
    }

    private static OutgoingDetail Detail(OutgoingBook b, string entityName) => new(
        b.OutgoingId, b.CompanyId, b.Number, b.Year, b.SerialNo, b.Date,
        b.EntityId, entityName, b.TemplateId, b.HeaderPhrase, b.SignatoryName, b.SignatoryTitle, b.Subject, b.BodyHtml,
        b.Status, b.Amount, b.Currency, b.ExchangeRate, b.AmountInIqd,
        b.QrContent, b.GeneratedPdfBlobKey != null, b.ApprovedByUserId, b.ApprovedAt,
        b.CreatedAt, b.UpdatedAt, b.RowVersion is null ? "" : Convert.ToBase64String(b.RowVersion));
}
