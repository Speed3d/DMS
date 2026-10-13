using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Security;
using Dms.Infrastructure.Documents;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Dms.Api.Controllers;

public sealed record VerifyRequest(string QrContent);

[ApiController]
[Route("api/[controller]")]
public sealed class VerifyController(AppDbContext db, IOptions<QrSigningOptions> qr, IPublicBookVerifier verifier) : ControllerBase
{
    /// <summary>
    /// تحقق من كتابٍ صادر — بمحتوى الـQR الموقّع الخامّ، **أو برابط التحقق المطبوع على الكتاب** (<c>…/v/{token}</c>).
    /// </summary>
    /// <remarks>
    /// <para>
    /// 📷 **الرابط (ADR-061)**: الختم المطبوع منذ ADR-043 يحمل رابطاً لا محتوىً موقّعاً — فمسحُه بالكاميرا داخل النظام يُعطي رابطاً.
    /// ويُحكم عليه **بمنطق صفحة الهاتف العامّة نفسه** (`IPublicBookVerifier`) — والإفصاح مثلُها: الرقم والتاريخ والجهة **بلا مبلغ**
    /// (قرار المالك 2026-09-09)، فالنقطة مجهولةٌ كالصفحة ولا تكشف ما تُخفيه الصفحة.
    /// </para>
    /// <para>
    /// 🔐 **وحدُّ طلباتٍ لكل عنوان** (حدُّ الصفحة العامّة نفسه) — كلُّ فحصٍ برابطٍ يُكتب في سجلّ التدقيق، فلا يُغرَق بطلبٍ مجهول.
    /// </para>
    /// </remarks>
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.PublicVerify)]
    [HttpPost]
    public async Task<ActionResult<VerifyResponse>> Verify(VerifyRequest req, CancellationToken ct)
    {
        if (PublicBookVerifier.TokenFromLink(req.QrContent) is { } token)
        {
            var ip = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "غير معروف";
            var v = await verifier.EvaluateAsync(token, "فحصٌ من داخل النظام", ip, ct);
            return new VerifyResponse(
                v.Verdict != PublicVerdict.Tampered, v.Title, v.Number, v.Date, v.Entity, AmountInIqd: null,
                FoundInDb: v.Verdict == PublicVerdict.Genuine,
                Verdict: v.Verdict, Title: v.Title, Note: v.Note, CompanyName: v.CompanyName,
                VersionNo: v.Verdict == PublicVerdict.Genuine ? v.VersionNo : null);
        }

        var result = QrSigner.Verify(req.QrContent, qr.Value.PublicKeyBase64);
        if (!result.IsValid)
        {
            var t = PublicBookVerifier.TamperedVerdict();
            return new VerifyResponse(false, result.Message, null, null, null, null, false, t.Verdict, t.Title, t.Note);
        }

        var found = await db.OutgoingBooks.AnyAsync(b => b.Number == result.Number, ct);
        var verdict = found
            ? new PublicVerdict(PublicVerdict.Genuine, "تم إصدار هذا الكتاب فعلاً من الشركة",
                "طابِق البيانات أدناه مع الورقة التي بين يديك.", null, null, null, null, 0, null)
            : PublicBookVerifier.WithdrawnVerdict(result.Number);
        return new VerifyResponse(true, result.Message, result.Number, result.Date,
            result.Entity, result.AmountInIqd, found, verdict.Verdict, verdict.Title, verdict.Note);
    }
}
