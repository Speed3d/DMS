using System.Net;
using Dms.Api.Auth;
using Dms.Documents.Security;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Documents;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Dms.Api.Controllers;

/// <summary>
/// صفحة التحقق العامّة — يفتحها **ماسحُ كاميرا الهاتف** حين يمسح رمز كتابٍ صادر (ADR-043).
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **صفحةٌ يولّدها الخادم لا مسارٌ في تطبيق Flutter**، لثلاثة أسباب:
/// حزمةُ الويب ثقيلةٌ على بيانات الجوال والمتحقِّق ينتظر ثانيةً لا عشراً ·
/// و**CORS في الإنتاج مغلقٌ افتراضياً** فطلبٌ من صفحةٍ عامة يُردّ ·
/// والصفحة يجب أن تعمل **بلا تسجيل دخول وبلا اعتمادٍ على أن التطبيق سليم**.
/// </para>
/// <para>
/// ⚠️ **بلا JavaScript وبلا أصولٍ خارجية** — كلُّ شيءٍ في ردٍّ واحد، فتُفتح على شبكةٍ ضعيفة.
/// </para>
/// <para>
/// 🔐 **والإفصاح مقصورٌ على ما يحتاجه المطابِق**: الرقم والتاريخ والجهة — **بلا مبلغ**
/// (قرار المالك 2026-09-09). ومَن يملك الورقة يرى مبلغَها عليها.
/// </para>
/// </remarks>
[ApiController]
[AllowAnonymous]
public sealed class PublicVerifyController(
    AppDbContext db,
    IOptions<QrSigningOptions> qr,
    IFileStorage storage,
    IAuditService audit) : ControllerBase
{
    /// <summary>صفحة التحقق — `GET /v/{token}`.</summary>
    [EnableRateLimiting(RateLimitPolicies.PublicVerify)]
    [HttpGet("/v/{token}")]
    public async Task<IActionResult> Page(string token, CancellationToken ct)
    {
        var view = await BuildAsync(token, ct);

        // ⚠️ **الردّ 200 في كل الحالات** — بما فيها التلاعب. صفحةُ خطأ 404 من المتصفّح
        //    تقول «الرابط معطوب» وهي رسالةٌ خاطئة: الرابط وصل، **والكتاب هو المشكوك فيه**.
        return Content(RenderHtml(view), "text/html; charset=utf-8");
    }

    /// <summary>تنزيل الـPDF لحاملِ الرمز — `GET /v/{token}/pdf`.</summary>
    /// <remarks>
    /// 🔴 **الرابط بوّابةٌ لا هويّة**: مَن يحمله ينزّل، ومَن يحمل الورقة يملك محتواها أصلاً.
    /// والضوابط ثلاثة: **مفتاح إطفاء** · **حدُّ طلباتٍ أضيق** · و**تسجيلٌ لكل تنزيل**.
    /// </remarks>
    [EnableRateLimiting(RateLimitPolicies.PublicDownload)]
    [HttpGet("/v/{token}/pdf")]
    public async Task<IActionResult> Pdf(string token, CancellationToken ct)
    {
        // ⚠️ **404 لا 403 حين يُطفأ** — فلا يُفصح الردُّ أن ثمّة ملفاً يُحجب.
        if (!qr.Value.AllowPublicPdfDownload) return NotFound();

        if (!PublicLink.TryParse(token, qr.Value.PrivateKeyBase64, out var bookId))
            return NotFound();

        var book = await db.OutgoingBooks
            .IgnoreQueryFilters()
            .Where(b => b.OutgoingId == bookId && !b.IsDeleted && b.Status == BookStatus.Final)
            .Select(b => new { b.OutgoingId, b.Number, b.CompanyId, b.QrContent, b.GeneratedPdfBlobKey })
            .FirstOrDefaultAsync(ct);

        if (book?.GeneratedPdfBlobKey is null || string.IsNullOrEmpty(book.QrContent))
            return NotFound();

        // 🔴 **لا يُنزَّل ما لا يُتحقَّق منه** — نفس حارس الصفحة، فلا يصير التنزيل باباً أوسع.
        if (!QrSigner.Verify(book.QrContent, qr.Value.PublicKeyBase64).IsValid) return NotFound();

        var bytes = await storage.ReadAsync(book.GeneratedPdfBlobKey, ct);

        audit.Add("PublicPdfDownload", nameof(OutgoingBook), book.OutgoingId.ToString(),
            $"تنزيلٌ عامّ للكتاب {book.Number} من {ClientIp()}", book.CompanyId);
        await db.SaveChangesAsync(ct);

        // ⚠️ **باسم ملفٍ صريح هنا عمداً**: هذا زرُّ تنزيلٍ قصده المستخدم، بخلاف مسارات
        //    العرض التي تُترك بلا اسمٍ لئلّا يختطفها مدير التحميل (مبدأ ADR-019).
        return File(bytes, "application/pdf", $"{book.Number}.pdf");
    }

    // ─────────────────────────── المنطق ───────────────────────────

    private sealed record VerifyView(
        string Verdict,          // Genuine | Withdrawn | Tampered
        string Title,
        string Note,
        string? Number,
        string? Date,
        string? Entity,
        string? CompanyName,
        int VersionNo,
        string? Token);

    private async Task<VerifyView> BuildAsync(string token, CancellationToken ct)
    {
        // 🔐 **الفشل قبل أي استعلام** — فرمزٌ مزوَّر لا يكشف إن كان الكتاب موجوداً.
        if (!PublicLink.TryParse(token, qr.Value.PrivateKeyBase64, out var bookId))
            return Tampered();

        // ⚠️ **`IgnoreQueryFilters` مقصود**: الطلب مجهول، ولولاه لسقط فلترُ الشركة… ولا يسقط
        //    فلترُ الحذف الناعم. والفرق بين «مزوَّر» و«مسحوب» **معلومةٌ يحتاجها المتحقِّق**،
        //    فيُقرأ الكتاب ولو كان محذوفاً ثم يُقال له الصدق.
        var book = await db.OutgoingBooks
            .IgnoreQueryFilters()
            .Where(b => b.OutgoingId == bookId)
            .Select(b => new
            {
                b.OutgoingId, b.Number, b.Date, b.Status, b.IsDeleted,
                b.QrContent, b.CompanyId, b.EntityId, b.GeneratedPdfBlobKey,
            })
            .FirstOrDefaultAsync(ct);

        // رمزٌ سليم البصمة لكتابٍ لا وجود له = قاعدةٌ استُعيدت أو صفٌّ مُحي — لا تزوير.
        if (book is null) return Withdrawn(null);

        // 🔴 **يُتحقَّق من التوقيع المحفوظ لا من الرمز**: الرمز يثبت **أي كتابٍ** يُقصد،
        //    والتوقيع يثبت أن بيانات الكتاب لم تُمسّ منذ اعتماده. حارسان لا واحد.
        if (string.IsNullOrEmpty(book.QrContent)) return Tampered();

        var signed = QrSigner.Verify(book.QrContent, qr.Value.PublicKeyBase64);
        if (!signed.IsValid) return Tampered();

        if (book.IsDeleted || book.Status != BookStatus.Final)
            return Withdrawn(book.Number);

        var company = await db.Companies.IgnoreQueryFilters()
            .Where(c => c.CompanyId == book.CompanyId)
            .Select(c => c.Name).FirstOrDefaultAsync(ct);

        var entity = await db.Entities.IgnoreQueryFilters()
            .Where(e => e.EntityId == book.EntityId)
            .Select(e => e.Name).FirstOrDefaultAsync(ct);

        // ⚠️ **عددُ الإصدارات يُعلَن** — فورقةٌ قديمة لكتابٍ عُدِّل بعد اعتماده لا تُقرأ
        //    على أنها الأحدث. الصمتُ هنا يجعل الصفحة تكذب على من يقارن.
        var versions = await db.DocumentVersions
            .IgnoreQueryFilters()
            .CountAsync(v => v.DocType == OwnerType.Outgoing && v.DocId == book.OutgoingId, ct);

        audit.Add("VerifyScan", nameof(OutgoingBook), book.OutgoingId.ToString(),
            $"فحصٌ عامّ للكتاب {book.Number} من {ClientIp()}", book.CompanyId);
        await db.SaveChangesAsync(ct);

        return new VerifyView(
            "Genuine",
            "تم إصدار هذا الكتاب فعلاً من الشركة",
            "طابِق البيانات أدناه مع الورقة التي بين يديك.",
            book.Number, book.Date.ToString("yyyy-MM-dd"), entity, company,
            versions + 1,
            // ⚠️ **الزرّ يغيب حين يُطفأ المفتاح** — لا يُعرض ما يردّ 404.
            book.GeneratedPdfBlobKey is null || !qr.Value.AllowPublicPdfDownload ? null : token);
    }

    private static VerifyView Tampered() => new(
        "Tampered",
        "تم التلاعب بالكتاب",
        "هذا الرمز لا يطابق أي كتابٍ صادرٍ عن الشركة. لا تعتمد على هذه الورقة.",
        null, null, null, null, 0, null);

    private static VerifyView Withdrawn(string? number) => new(
        "Withdrawn",
        "هذا الكتاب لم يعُد ضمن سجلّات الشركة",
        "قد يكون سُحب أو أُلغي. راجِع الجهة المُصدِرة قبل الاعتماد عليه.",
        number, null, null, null, 0, null);

    private string ClientIp() =>
        HttpContext.Connection.RemoteIpAddress?.ToString() ?? "غير معروف";

    // ─────────────────────────── الرسم ───────────────────────────

    private static string E(string? s) => WebUtility.HtmlEncode(s ?? "");

    private static string RenderHtml(VerifyView v)
    {
        var (accent, glyph) = v.Verdict switch
        {
            "Genuine" => ("#178A5B", "✓"),
            "Withdrawn" => ("#BE7A12", "!"),
            _ => ("#C13B33", "✕"),
        };

        var rows = new List<string>();
        void Row(string label, string? value)
        {
            if (!string.IsNullOrWhiteSpace(value))
                rows.Add($"<div class=r><span class=k>{E(label)}</span><span class=v>{E(value)}</span></div>");
        }

        Row("رقم الكتاب", v.Number);
        Row("التاريخ", v.Date);
        Row("الجهة", v.Entity);
        Row("الشركة", v.CompanyName);
        if (v.VersionNo > 1)
            Row("ملاحظة", $"عُدِّل بعد الاعتماد — الإصدار {v.VersionNo}");

        var download = v.Token is null
            ? ""
            : $"<a class=btn href=\"/v/{E(v.Token)}/pdf\">تنزيل الكتاب (PDF)</a>";

        // ⚠️ **`$$` وأقواسٌ مزدوجة للاستيفاء**: النصّ الخامّ لا يعرف `{{` مهرباً، وCSS
        //    مليءٌ بالأقواس — فيُقلَب الاصطلاح: `{` حرفٌ عاديّ و`{{expr}}` استيفاء.
        return $$"""
        <!doctype html>
        <html lang="ar" dir="rtl">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>التحقق من كتاب صادر</title>
        <style>
          :root { color-scheme: light }
          * { box-sizing: border-box }
          body { margin:0; padding:24px 16px; background:#E9EDF4; color:#0F1D38;
                 font:16px/1.7 "Segoe UI",Tahoma,Arial,sans-serif;
                 display:flex; justify-content:center }
          .card { background:#fff; border-radius:16px; max-width:520px; width:100%;
                  padding:28px 22px; box-shadow:0 2px 18px rgba(16,32,64,.10) }
          .badge { width:64px; height:64px; border-radius:50%; margin:0 auto 16px;
                   display:flex; align-items:center; justify-content:center;
                   font-size:32px; font-weight:700; color:#fff; background:{{accent}} }
          h1 { font-size:20px; text-align:center; margin:0 0 8px; color:{{accent}} }
          .note { text-align:center; color:#5A6B8C; font-size:14px; margin:0 0 22px }
          .r { display:flex; justify-content:space-between; gap:12px;
               padding:11px 0; border-bottom:1px solid #E2E7EF }
          .r:last-child { border-bottom:0 }
          .k { color:#5A6B8C; font-size:14px; flex:0 0 auto }
          .v { font-weight:600; text-align:left; word-break:break-word }
          .btn { display:block; margin-top:22px; padding:14px; border-radius:12px;
                 background:#0C1B33; color:#fff; text-decoration:none;
                 text-align:center; font-weight:700 }
          .foot { text-align:center; color:#8A99B5; font-size:12px; margin-top:20px }
        </style>
        <div class="card">
          <div class="badge">{{glyph}}</div>
          <h1>{{E(v.Title)}}</h1>
          <p class="note">{{E(v.Note)}}</p>
          {{string.Concat(rows)}}
          {{download}}
          <p class="foot">تحقّقٌ إلكترونيّ بختمٍ رقميّ — {{E(v.CompanyName ?? "نظام إدارة الوثائق")}}</p>
        </div>
        """;
    }
}
