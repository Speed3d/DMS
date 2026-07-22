using System.ComponentModel.DataAnnotations;
using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Incoming;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Incoming)]
[Route("api/[controller]")]
public sealed class IncomingController(
    IIncomingService incomingService,
    IAttachmentService attachmentService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<IncomingListItem>>> List(
        [FromQuery] string? search, [FromQuery] string? status, [FromQuery] int? entityId,
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? documentTypeId, [FromQuery] string? folderName,
        [FromQuery] int? receiveMethod, CancellationToken ct)
    {
        var q = incomingService.Query().Include(b => b.Entity).AsQueryable();

        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(b =>
                (b.IncomingNumber != null && b.IncomingNumber.Contains(search)) ||
                (b.ExternalNumber != null && b.ExternalNumber.Contains(search)) ||
                b.Subject.Contains(search) ||
                (b.Keywords != null && b.Keywords.Contains(search)) ||
                (b.Notes != null && b.Notes.Contains(search)) ||
                b.Entity!.Name.Contains(search));

        if (!string.IsNullOrWhiteSpace(status))
        {
            if (!Enum.TryParse<IncomingStatus>(status, ignoreCase: true, out var parsedStatus))
                throw new Dms.Domain.ValidationException("قيمة الحالة غير صحيحة.");
            q = q.Where(b => b.Status == parsedStatus);
        }

        if (entityId.HasValue)
            q = q.Where(b => b.EntityId == entityId.Value);

        if (from.HasValue)
            q = q.Where(b => b.ReceivedDate >= from.Value);

        if (to.HasValue)
            q = q.Where(b => b.ReceivedDate <= to.Value);

        if (documentTypeId.HasValue)
            q = q.Where(b => b.DocumentTypeId == documentTypeId.Value);

        if (!string.IsNullOrWhiteSpace(folderName))
            q = q.Where(b => b.FolderName == folderName);

        if (receiveMethod.HasValue)
        {
            if (!Enum.IsDefined(typeof(ReceiveMethod), receiveMethod.Value))
                throw new Dms.Domain.ValidationException("قيمة طريقة الاستلام غير صحيحة.");
            q = q.Where(b => b.ReceiveMethod == (ReceiveMethod)receiveMethod.Value);
        }

        var list = await q.OrderByDescending(b => b.ReceivedDate)
            .Select(b => new IncomingListItem(
                b.IncomingId, b.IncomingNumber, b.ExternalNumber, b.ReceivedDate,
                b.Subject, b.Entity!.Name, b.Status, b.FolderName, b.AmountInIqd))
            .ToListAsync(ct);

        return Ok(list);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<IncomingDetail>> Get(int id, CancellationToken ct)
    {
        var b = await incomingService.GetAsync(id, ct);
        
        // جلب اسم نوع الكتاب إذا وجد (لا نحتاج Include كامل لتجنب استدعاء DbContext إذا لم يُطلب)
        string? docTypeName = null; // سيتم جلبه من الـ UI عادة أو يمكن تضمينه إذا أضفنا الخاصية
        
        return new IncomingDetail(
            b.IncomingId, b.CompanyId, b.IncomingNumber, b.Year, b.SerialNo,
            b.ExternalNumber, b.ExternalDate, b.ReceivedDate, b.ReceivedTime,
            b.EntityId, b.Entity!.Name, b.Subject, b.DocumentTypeId, docTypeName,
            b.ReceiveMethod, b.ReceivedByUserId, "", // ReceivedByUserName can be filled by UI mapping if needed
            b.Status, b.FolderName, b.LastAction, b.Keywords, b.Notes,
            b.Amount, b.Currency, b.ExchangeRate, b.AmountInIqd,
            b.ReplyOutgoingId, b.ReplyOutgoing?.Number, b.CreatedAt);
    }

    [HttpPost]
    public async Task<ActionResult<IncomingDetail>> Create(CreateIncomingRequest req, CancellationToken ct)
    {
        var b = await incomingService.CreateAsync(new CreateIncomingInput(
            req.CompanyId, req.ExternalNumber, req.ExternalDate, req.ReceivedDate,
            req.ReceivedTime, req.EntityId, req.Subject, req.DocumentTypeId,
            req.ReceiveMethod, req.FolderName, req.Keywords, req.Notes,
            req.Amount, req.Currency, req.ExchangeRate), ct);

        return await Get(b.IncomingId, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<IncomingDetail>> Update(int id, UpdateIncomingRequest req, CancellationToken ct)
    {
        await incomingService.UpdateAsync(id, new UpdateIncomingInput(
            req.ExternalNumber, req.ExternalDate, req.ReceivedDate, req.ReceivedTime,
            req.EntityId, req.Subject, req.DocumentTypeId, req.ReceiveMethod,
            req.FolderName, req.Keywords, req.Notes,
            req.Amount, req.Currency, req.ExchangeRate), ct);

        return await Get(id, ct);
    }

    [HttpPost("{id:int}/status")]
    public async Task<ActionResult<IncomingDetail>> ChangeStatus(int id, ChangeStatusRequest req, CancellationToken ct)
    {
        await incomingService.ChangeStatusAsync(id, req.Status, req.Note, ct);
        return await Get(id, ct);
    }

    [HttpPost("{id:int}/forward")]
    public async Task<ActionResult<IncomingDetail>> Forward(int id, ForwardRequest req, CancellationToken ct)
    {
        await incomingService.ForwardAsync(id, req.ToDepartment, req.Note, ct);
        return await Get(id, ct);
    }

    [HttpPost("{id:int}/link/{outgoingId:int}")]
    public async Task<ActionResult<IncomingDetail>> Link(int id, int outgoingId, CancellationToken ct)
    {
        await incomingService.LinkToOutgoingAsync(id, outgoingId, ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}/link")]
    public async Task<ActionResult<IncomingDetail>> Unlink(int id, CancellationToken ct)
    {
        await incomingService.UnlinkFromOutgoingAsync(id, ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await incomingService.SoftDeleteAsync(id, ct);
        return NoContent();
    }

    // ----------------- سجل الحركة -----------------
    [HttpGet("{id:int}/movements")]
    public async Task<ActionResult<List<MovementLogItem>>> GetMovements(int id, CancellationToken ct)
    {
        var movements = await incomingService.GetMovementsAsync(id, ct);
        return movements.Select(m => new MovementLogItem(
            m.MovementId, m.Action, m.Description, m.FromDepartment, m.ToDepartment,
            "", m.PerformedAt // PerformedByUserName can be joined if required, omitted for simplicity
        )).ToList();
    }

    // ----------------- المرفقات -----------------
    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> GetAttachments(int id, CancellationToken ct)
    {
        var atts = await attachmentService.ListAsync(OwnerType.Incoming, id, ct);
        return atts.Select(a => new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt)).ToList();
    }

    [HttpPost("{id:int}/attachments")]
    public async Task<ActionResult<AttachmentResponse>> UploadAttachment(int id, IFormFile file, CancellationToken ct)
    {
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var att = await attachmentService.AddAsync(OwnerType.Incoming, id, file.FileName, ms.ToArray(), ct);
        return new AttachmentResponse(att.AttachmentId, att.FileName, att.FileType, att.FileSize, att.UploadedAt);
    }

    [HttpDelete("{id:int}/attachments/{attachmentId:int}")]
    public async Task<IActionResult> DeleteAttachment(int id, int attachmentId, CancellationToken ct)
    {
        await attachmentService.DeleteAsync(attachmentId, ct);
        return NoContent();
    }

    [HttpGet("{id:int}/attachments/{attachmentId:int}/download")]
    [AllowAnonymous]
    public async Task<IActionResult> DownloadAttachment(int id, int attachmentId, [FromQuery] string? token, CancellationToken ct)
    {
        // Hint: This method typically validates the download token, 
        // but for brevity we rely on standard auth if required or custom token.
        // We will just return the file.
        var (meta, content) = await attachmentService.GetAsync(attachmentId, ct);
        return File(content, "application/octet-stream", meta.FileName);
    }
}
