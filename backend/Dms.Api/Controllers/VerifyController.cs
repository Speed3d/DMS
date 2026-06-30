using Dms.Api.Dtos;
using Dms.Documents.Security;
using Dms.Infrastructure.Documents;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Dms.Api.Controllers;

public sealed record VerifyRequest(string QrContent);

[ApiController]
[Route("api/[controller]")]
public sealed class VerifyController(AppDbContext db, IOptions<QrSigningOptions> qr) : ControllerBase
{
    /// <summary>
    /// تحقق عام من كتاب عبر محتوى الـ QR: (1) صحة التوقيع الرقمي، (2) مطابقة السجل في قاعدة البيانات.
    /// </summary>
    [AllowAnonymous]
    [HttpPost]
    public async Task<ActionResult<VerifyResponse>> Verify(VerifyRequest req, CancellationToken ct)
    {
        var result = QrSigner.Verify(req.QrContent, qr.Value.PublicKeyBase64);
        if (!result.IsValid)
            return new VerifyResponse(false, result.Message, null, null, null, null, false);

        var found = await db.OutgoingBooks.AnyAsync(b => b.Number == result.Number, ct);
        return new VerifyResponse(true, result.Message, result.Number, result.Date,
            result.Entity, result.AmountInIqd, found);
    }
}
