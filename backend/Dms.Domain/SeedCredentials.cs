namespace Dms.Domain;

/// <summary>
/// بيانات أوّل حساب سوبر أدمن — **قاعدةٌ واحدة** في المجال لأن الخطأ فيها يُقفل النظام
/// على مالكه في اللحظة التي لا يملك فيها حساباً آخر يُصلحه به.
///
/// 🔴 **العيب الذي وُلدت منه:** كان البذر يكتب <c>config["Seed:AdminUsername"] ?? "admin"</c>،
///    و<c>appsettings.json</c> المنشور يشحن <c>""</c> — **والسلسلة الفارغة ليست <c>null</c>**،
///    فلا يعمل الاحتياطيّ إطلاقاً. النتيجة في الإنتاج: سوبر أدمن **باسمٍ فارغ وكلمة مرورٍ
///    فارغة**، ولا حسابَ ثانٍ يدخل به المالك ليصلحه. (مُقاسٌ بالتجربة لا مُستنتَجاً.)
///
/// 🔑 **والدرس أوسع من موضعه:** في الإعدادات **القيمة الفارغة غيابُ إعداد لا إعدادٌ فارغ**،
///    و<c>??</c> يحرس <c>null</c> وحده. كلُّ قراءةٍ لإعدادٍ له افتراضٌ تحتاج
///    <c>IsNullOrWhiteSpace</c> لا <c>??</c>.
/// </summary>
public static class SeedCredentials
{
    public const string DefaultUsername = "admin";
    public const string DefaultPassword = "Admin@12345";

    /// <summary>اسم أوّل مدير — الافتراض عند غياب الإعداد <b>أو فراغه</b>.</summary>
    public static string Username(string? configured) => Or(configured, DefaultUsername);

    /// <summary>كلمة مرور أوّل مدير — الافتراض عند غياب الإعداد <b>أو فراغه</b>.</summary>
    /// <remarks>
    /// ⚠️ افتراضٌ معروفٌ عمداً للتطوير. في الإنتاج تكتب <c>generate-secrets</c> كلمةً
    /// عشوائية فريدة في <c>appsettings.Production.json</c> فلا يُستعمل هذا الافتراض أصلاً —
    /// وهو باقٍ **شبكةَ أمانٍ لا سياسة**، ويبقى <c>MustChangePassword</c> مفروضاً فوقه.
    /// </remarks>
    public static string Password(string? configured) => Or(configured, DefaultPassword);

    private static string Or(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value;
}
