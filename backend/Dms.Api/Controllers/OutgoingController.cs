using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Security;
using Dms.Infrastructure.Documents;
using Dms.Domain;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Outgoing;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Outgoing)]
[Route("api/[controller]")]
public sealed class OutgoingController(
    IOutgoingService svc, IIncomingService incoming, AppDbContext db,
    IOptions<QrSigningOptions> qrOptions) : ControllerBase
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
        // الربط العكسي: الكتب الواردة التي يردّ عليها هذا الصادر (ADR-045).
        // 🔐 **يمرّ بـ`IIncomingService.Query()` لا بـ`db.IncomingBooks`** — وهو تصحيحُ
        //    تسريبٍ كان قائماً: القراءة المباشرة كانت تكشف رقم واردٍ **محجوبٍ بحدّ القسم**
        //    لكلّ من يرى الصادر، والكلُّ يراه (ADR-030). ومع تعدّد الردود كانت ستصير قائمةً.
        var repliesTo = await db.BookReplies
            .Where(r => r.OutgoingId == id)
            .OrderBy(r => r.LinkedAt)
            .Join(incoming.Query(), r => r.IncomingId, i => i.IncomingId,
                (r, i) => new ReplyLinkDto(i.IncomingId, i.IncomingNumber, i.ReceivedDate, i.Subject, r.LinkedAt))
            .ToListAsync(ct);

        return Detail(book, entityName, svc.CanCurrentUserApprove(), repliesTo);
    }

    [HttpPost]
    public async Task<ActionResult<OutgoingDetail>> Create(CreateOutgoingRequest req, CancellationToken ct)
    {
        var book = await svc.CreateDraftAsync(new CreateOutgoingInput(
            req.CompanyId, req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate, req.BodyJson), ct);
        return await Get(book.OutgoingId, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<OutgoingDetail>> Update(int id, UpdateOutgoingRequest req, CancellationToken ct)
    {
        await svc.UpdateDraftAsync(id, new UpdateOutgoingInput(
            req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate, req.BodyJson), ct);
        return await Get(id, ct);
    }

    [HttpPost("{id:int}/approve")]
    public async Task<ActionResult<OutgoingDetail>> Approve(
        int id, [FromBody] ApproveOutgoingRequest? req, CancellationToken ct)
    {
        await svc.ApproveAsync(id, ct);

        // ⚠️ **بعد الاعتماد لا قبله** — الربط يشترط صادراً `Final`، والاعتماد هو ما يجعله كذلك.
        // ⚠️ **وكلُّ واردٍ يمرّ بـ`Query()` داخل الخدمة**، فلا يُربط ما لا يراه المعتمِد.
        if (req?.ReplyToIncomingIds is { Count: > 0 } ids)
            await incoming.LinkOutgoingToManyAsync(id, ids, ct);

        return await Get(id, ct);
    }

    [HttpPut("{id:int}/edit-approved")]
    public async Task<ActionResult<OutgoingDetail>> EditApproved(int id, EditApprovedRequest req, CancellationToken ct)
    {
        await svc.EditAfterApprovalAsync(id, new EditApprovedInput(
            req.EntityId, req.TemplateId, req.Date, req.HeaderPhrase, req.SignatoryName, req.SignatoryTitle, req.Subject, req.BodyHtml,
            req.Amount, req.Currency, req.ExchangeRate,
            Convert.FromBase64String(req.RowVersion), req.ChangeNote, req.BodyJson), ct);
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
            req.Amount, req.Currency, req.ExchangeRate, req.BodyJson), ct);
        return File(bytes, "application/pdf");
    }

    [HttpGet("{id:int}/preview-draft")]
    public async Task<IActionResult> PreviewDraft(int id, CancellationToken ct)
    {
        var bytes = await svc.PreviewDraftPdfAsync(id, ct);
        return File(bytes, "application/pdf");
    }

    [HttpGet("{id:int}/word")]
    public async Task<IActionResult> Word(int id, CancellationToken ct)
    {
        var bytes = await svc.GetWordAsync(id, ct);
        // بلا اسم ملف عمداً: الشاشة تجلب البايتات بـXHR وتسمّي الملف برقم الكتاب، وترويسةُ
        // «تنزيل» تجعل مديري التحميل يختطفون الطلب فلا يصل ردّ (مبدأ ADR-019).
        return File(bytes, "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    }

    private OutgoingDetail Detail(OutgoingBook b, string entityName, bool canApprove,
        List<ReplyLinkDto>? repliesTo = null) => new(
        b.OutgoingId, b.CompanyId, b.Number, b.Year, b.SerialNo, b.Date,
        b.EntityId, entityName, b.TemplateId, b.HeaderPhrase, b.SignatoryName, b.SignatoryTitle, b.Subject, b.BodyHtml,
        b.Status, b.Amount, b.Currency, b.ExchangeRate, b.AmountInIqd,
        b.QrContent, b.GeneratedPdfBlobKey != null, b.ApprovedByUserId, b.ApprovedAt,
        b.CreatedAt, b.UpdatedAt, b.RowVersion is null ? "" : Convert.ToBase64String(b.RowVersion), canApprove, b.BodyJson,
        repliesTo ?? [],
        VerifyUrl(b));

    /// <summary>رابط التحقق العامّ — **للمعتمد وحده**، فالمسودّة بلا رمزٍ مطبوع.</summary>
    private string? VerifyUrl(OutgoingBook b)
    {
        if (b.Status != BookStatus.Final || b.OutgoingId <= 0) return null;

        var token = PublicLink.CreateToken(b.OutgoingId, qrOptions.Value.PrivateKeyBase64);
        var baseUrl = qrOptions.Value.PublicBaseUrl.TrimEnd('/');
        return string.IsNullOrWhiteSpace(baseUrl) ? $"/v/{token}" : $"{baseUrl}/v/{token}";
    }
}
