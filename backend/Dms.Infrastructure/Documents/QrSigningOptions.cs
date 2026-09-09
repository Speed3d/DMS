namespace Dms.Infrastructure.Documents;

/// <summary>
/// مفاتيح توقيع الـ QR (ECDSA P-256) — Base64.
/// التطوير: من appsettings. الإنتاج: من Azure Key Vault.
/// </summary>
public sealed class QrSigningOptions
{
    public const string Section = "QrSigning";
    public string PrivateKeyBase64 { get; set; } = string.Empty;
    public string PublicKeyBase64 { get; set; } = string.Empty;

    /// <summary>
    /// العنوان العامّ الذي يفتحه ماسحُ الكاميرا — مثل <c>https://dms.example.com</c>.
    /// </summary>
    /// <remarks>
    /// 🔴 **يُضبط قبل أوّل كتابٍ رسميّ — تماماً كمفاتيح التوقيع.** الـQR **يُخبَز في الـPDF
    /// لحظة الاعتماد**، فكتابٌ اعتُمد وهذا فارغٌ يحمل النصّ الخامّ **إلى الأبد**: تعرضه
    /// الكاميرا نصّاً ولا تفتح صفحة.
    /// ⚠️ **وفراغُه ليس عطلاً** — بل السلوك القديم حرفياً، فبيئة التطوير تعمل بلا إعداد.
    /// </remarks>
    public string PublicBaseUrl { get; set; } = string.Empty;

    /// <summary>هل يُتاح تنزيل الـPDF من صفحة التحقق العامّة؟ (قرار المالك: نعم مع ضوابط.)</summary>
    /// <remarks>
    /// 🔴 **مفتاح إطفاء**: الرابط المطبوع **يحمل نفسه مفتاحاً** — فمن وصلته صورةُ الكتاب
    /// يستطيع تنزيل نسخته الرسمية. وإطفاؤه هنا **يُبقي التحقق ويُخفي التنزيل** بلا إعادة
    /// طبع ورقةٍ واحدة. ⚠️ **ويحتاج إعادة تشغيل الخدمة** (ثوانٍ).
    /// </remarks>
    public bool AllowPublicPdfDownload { get; set; } = true;
}
