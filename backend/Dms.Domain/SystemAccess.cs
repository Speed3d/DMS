namespace Dms.Domain;

/// <summary>نوع إعلان الشريط العلويّ — يحدّد لونه فقط (ADR-050).</summary>
public enum AnnouncementKind
{
    /// <summary>معلومة — بلون التطبيق التفاعليّ.</summary>
    Info = 0,
    /// <summary>تنبيه — بالبرتقاليّ.</summary>
    Warning = 1,
}

/// <summary>أيُّ قائمتَي النصوص المحفوظة (نصوص الإيقاف منفصلةٌ عن نصوص الشريط — قرار المالك).</summary>
public enum SavedTextKind
{
    Lockdown = 0,
    Announcement = 1,
}

/// <summary>
/// قاعدة **إيقاف النظام عن المستخدمين** (ADR-050): مَن يمرّ ومتى.
/// </summary>
/// <remarks>
/// 🔐 **السوبر أدمن وحده يتصفّح أثناء الإيقاف** (قرار المالك) — بلا استثناء لشركةٍ ولا لدور.
/// ويبقى مفتوحاً للجميع ما لا يكشف بياناً ولا يغيّره: حالةُ النظام (ليعرف العميل متى يعود)،
/// والدخولُ والتجديد والخروج (**والرفض فيها يقع في `AuthService` لا هنا**، لأن الدور لا يُعرف
/// قبل التحقّق من كلمة المرور)، وصفحةُ التحقق العامّة لأن الجهة الخارجية لا شأن لها بتحديثاتنا.
///
/// ⚠️ **وطلبٌ يحمل رمزاً منتهي الصلاحية يمرّ** ليأخذ 401 من حارس الصلاحية لا 503 من هنا:
/// لو رُدّ بـ503 لما عرف عميلُ السوبر أدمن أن رمزه انتهى، **فلا يجدّده ويبقى محجوباً عن
/// نظامٍ هو وحده المسموح له به**. وليس في هذا تسريب: كل نقطةٍ غير مستثناة تشترط المصادقة
/// (عدا شعار الشركة، وهو صورةٌ عامّة أصلاً).
/// </remarks>
public static class SystemAccess
{
    /// <summary>أقصى طول لرسالة الإيقاف أو نصّ الشريط.</summary>
    public const int MaxTextLength = 500;

    /// <summary>أقصى عدد للنصوص المحفوظة في كل قائمة.</summary>
    public const int MaxSavedTexts = 30;

    /// <summary>
    /// الرسالة حين يتعذّر قراءة ملفّ الحالة — **يفشل مغلقاً** فيُعدّ النظام موقوفاً.
    /// </summary>
    public const string DefaultLockdownMessage = "النظام متوقّف مؤقتاً للصيانة. سيعود قريباً.";

    // مساراتٌ مطابقةٌ حرفياً (بلا شرطة أخيرة، بلا حساسية لحالة الأحرف).
    private static readonly string[] OpenExactPaths =
    [
        "/api/system/status",
        "/api/auth/login",
        "/api/auth/refresh",
        "/api/auth/logout",
        "/api/verify",
    ];

    /// <summary>صفحة التحقق العامّة وتنزيلها (<c>/v/{token}</c> و<c>/v/{token}/pdf</c>).</summary>
    private const string PublicVerifyPrefix = "/v/";

    /// <summary>هل المسار مفتوحٌ للجميع أثناء الإيقاف؟</summary>
    public static bool IsOpenDuringLockdown(string? path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        if (path.StartsWith(PublicVerifyPrefix, StringComparison.OrdinalIgnoreCase)) return true;

        var p = path.Length > 1 ? path.TrimEnd('/') : path;
        foreach (var open in OpenExactPaths)
            if (string.Equals(p, open, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    /// <summary>هل يُردّ هذا الطلب بـ503 لأن النظام موقوف؟</summary>
    /// <param name="lockdownActive">الإيقاف مفعَّل.</param>
    /// <param name="path">مسار الطلب.</param>
    /// <param name="authenticated">حمل رمزاً صالحاً.</param>
    /// <param name="isSuperAdmin">دوره في الرمز سوبر أدمن.</param>
    /// <param name="hasBearer">أرسل ترويسة <c>Authorization: Bearer</c> (ولو منتهية).</param>
    public static bool ShouldBlock(bool lockdownActive, string? path, bool authenticated, bool isSuperAdmin, bool hasBearer)
    {
        if (!lockdownActive) return false;
        if (IsOpenDuringLockdown(path)) return false;
        if (authenticated) return !isSuperAdmin;
        // رمزٌ لم يُقبل (منتهٍ غالباً) ⇒ يمرّ ليأخذ 401 فيجدّده صاحبه — انظر الملاحظة أعلاه.
        return !hasBearer;
    }

    /// <summary>
    /// هل يُرفض **دخولُ** هذا الدور أو تجديدُ رمزه لأن النظام موقوف؟
    /// </summary>
    /// <remarks>
    /// ⚠️ **يُسأل بعد التحقّق من كلمة المرور لا قبله**: كلمةٌ خاطئة تبقى تُحسب محاولةً فاشلة
    /// كالمعتاد — وإلا صار الإيقاف نافذةً لتخمين كلمات المرور بلا قفل. **والذي لا يُحسب هو
    /// الرفض بسبب الصيانة وحده.**
    /// </remarks>
    public static bool RejectsSignIn(bool lockdownActive, UserRole role)
        => lockdownActive && role != UserRole.SuperAdmin;

    /// <summary>
    /// ينظّف نصّاً ويتحقّق منه — <b>مطلوبٌ</b> حين <paramref name="required"/>.
    /// </summary>
    /// <returns>النصّ مقصوص الفراغ، أو <c>null</c> إن كان فارغاً وغير مطلوب.</returns>
    public static string? NormalizeText(string? text, bool required, string what)
    {
        var t = text?.Trim();
        if (string.IsNullOrEmpty(t))
        {
            if (required) throw new ValidationException($"{what} مطلوب.");
            return null;
        }
        if (t.Length > MaxTextLength)
            throw new ValidationException($"{what} أطول من {MaxTextLength} حرفاً.");
        return t;
    }
}
