namespace Dms.Api.Auth;

/// <summary>
/// أسماء سياسات حدّ الطلبات — **في مكانٍ واحد** فلا يتباعد الاسم بين التهيئة والوسم.
/// </summary>
public static class RateLimitPolicies
{
    /// <summary>صفحة التحقق العامّة — قراءةٌ خفيفة.</summary>
    public const string PublicVerify = "public-verify";

    /// <summary>تنزيل الـPDF العامّ — **أضيق**، لأنه يقرأ ملفاً من القرص.</summary>
    public const string PublicDownload = "public-download";
}
