using System.Text.RegularExpressions;
using Dms.Documents.Security;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Dms.Infrastructure.Documents;

/// <summary>حكمُ التحقق من رمز الرابط العامّ — **ثلاث حالات لا اثنتان**.</summary>
public sealed record PublicVerdict(
    string Verdict,          // Genuine | Withdrawn | Tampered
    string Title,
    string Note,
    string? Number,
    string? Date,
    string? Entity,
    string? CompanyName,
    int VersionNo,
    string? Token)
{
    public const string Genuine = "Genuine";
    public const string Withdrawn = "Withdrawn";
    public const string Tampered = "Tampered";
}

public interface IPublicBookVerifier
{
    /// <summary>يحكم على رمز الرابط المطبوع في الـQR — ويسجّل الفحص في سجلّ التدقيق.</summary>
    /// <param name="source">مصدر الفحص في سجلّ التدقيق — «فحصٌ عامّ» (صفحة الهاتف) أو «فحصٌ من داخل النظام».</param>
    Task<PublicVerdict> EvaluateAsync(string token, string source, string clientIp, CancellationToken ct = default);
}

/// <summary>
/// منطقُ التحقق من الرابط العامّ (ADR-043) — **في موضعٍ واحد** تناديه صفحةُ الهاتف العامّة (`/v/{token}`) وشاشةُ التحقق داخل النظام
/// (مسح الختم بالكاميرا — ADR-061). 🔑 **نسخُ قاعدة الحكم أوّلُ الطريق إلى تباعدها** — فكتابٌ «صحيحٌ» على الهاتف و«مسحوبٌ» في النظام كذبةٌ لأحدهما.
/// </summary>
public sealed class PublicBookVerifier(AppDbContext db, IOptions<QrSigningOptions> qr, IAuditService audit) : IPublicBookVerifier
{
    /// <summary>
    /// الرابط **يبدأ به النصّ** (مخطّطٌ ومضيفٌ اختياريّان ثم <c>/v/</c>) — 🔴 فالمحتوى الموقّع الخامّ (<c>DMS2|…</c>) لا يُحسب رابطاً ولو
    /// حوى ترميزُه <c>/v/</c> صدفةً: المضيف لا يعبر <c>|</c>.
    /// </summary>
    private static readonly Regex LinkToken =
        new(@"^(?:https?://)?[^/\s|]*/v/([A-Za-z0-9_-]{8,64})(?:[/?#].*)?$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>
    /// رمزُ الرابط من نصٍّ ممسوح أو ملصوق (<c>https://…/v/{token}</c>) — أو <c>null</c> إن لم يكن رابطَ تحقّق.
    /// ⚠️ **المضيف لا يُفحص عمداً**: الرابط قد يُطبع بالدومين ويُمسح من جهازٍ يعمل على عنوانٍ آخر — والبصمة وحدها تحكم.
    /// </summary>
    public static string? TokenFromLink(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var m = LinkToken.Match(input.Trim());
        return m.Success ? m.Groups[1].Value : null;
    }

    public async Task<PublicVerdict> EvaluateAsync(string token, string source, string clientIp, CancellationToken ct = default)
    {
        // 🔐 **الفشل قبل أي استعلام** — فرمزٌ مزوَّر لا يكشف إن كان الكتاب موجوداً.
        if (!PublicLink.TryParse(token, qr.Value.PrivateKeyBase64, out var bookId))
            return TamperedVerdict();

        // ⚠️ **`IgnoreQueryFilters` مقصود**: الطلب قد يكون مجهولاً، ولولاه لسقط فلترُ الشركة… ولا يسقط فلترُ الحذف الناعم.
        //    والفرق بين «مزوَّر» و«مسحوب» **معلومةٌ يحتاجها المتحقِّق**، فيُقرأ الكتاب ولو كان محذوفاً ثم يُقال له الصدق.
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
        if (book is null) return WithdrawnVerdict(null);

        // 🔴 **يُتحقَّق من التوقيع المحفوظ لا من الرمز**: الرمز يثبت **أي كتابٍ** يُقصد، والتوقيع يثبت أن بيانات الكتاب لم تُمسّ
        //    منذ اعتماده. حارسان لا واحد.
        if (string.IsNullOrEmpty(book.QrContent)) return TamperedVerdict();

        var signed = QrSigner.Verify(book.QrContent, qr.Value.PublicKeyBase64);
        if (!signed.IsValid) return TamperedVerdict();

        if (book.IsDeleted || book.Status != BookStatus.Final)
            return WithdrawnVerdict(book.Number);

        var company = await db.Companies.IgnoreQueryFilters()
            .Where(c => c.CompanyId == book.CompanyId)
            .Select(c => c.Name).FirstOrDefaultAsync(ct);

        var entity = await db.Entities.IgnoreQueryFilters()
            .Where(e => e.EntityId == book.EntityId)
            .Select(e => e.Name).FirstOrDefaultAsync(ct);

        // ⚠️ **عددُ الإصدارات يُعلَن** — فورقةٌ قديمة لكتابٍ عُدِّل بعد اعتماده لا تُقرأ على أنها الأحدث.
        var versions = await db.DocumentVersions
            .IgnoreQueryFilters()
            .CountAsync(v => v.DocType == OwnerType.Outgoing && v.DocId == book.OutgoingId, ct);

        audit.Add("VerifyScan", nameof(OutgoingBook), book.OutgoingId.ToString(),
            $"{source} للكتاب {book.Number} من {clientIp}", book.CompanyId);
        await db.SaveChangesAsync(ct);

        return new PublicVerdict(
            PublicVerdict.Genuine,
            "تم إصدار هذا الكتاب فعلاً من الشركة",
            "طابِق البيانات أدناه مع الورقة التي بين يديك.",
            book.Number, book.Date.ToString("yyyy-MM-dd"), entity, company,
            versions + 1,
            // ⚠️ **الزرّ يغيب حين يُطفأ المفتاح** — لا يُعرض ما يردّ 404.
            book.GeneratedPdfBlobKey is null || !qr.Value.AllowPublicPdfDownload ? null : token);
    }

    public static PublicVerdict TamperedVerdict() => new(
        PublicVerdict.Tampered,
        "تم التلاعب بالكتاب",
        "هذا الرمز لا يطابق أي كتابٍ صادرٍ عن الشركة. لا تعتمد على هذه الورقة.",
        null, null, null, null, 0, null);

    public static PublicVerdict WithdrawnVerdict(string? number) => new(
        PublicVerdict.Withdrawn,
        "هذا الكتاب لم يعُد ضمن سجلّات الشركة",
        "قد يكون سُحب أو أُلغي. راجِع الجهة المُصدِرة قبل الاعتماد عليه.",
        number, null, null, null, 0, null);
}
