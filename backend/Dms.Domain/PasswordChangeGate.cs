namespace Dms.Domain;

/// <summary>
/// «تغيير كلمة المرور المؤقتة» **يفرضه الخادم** لا الواجهة وحدها (G19).
/// </summary>
/// <remarks>
/// 🔴 **الثغرة التي يُغلقها:** كان <c>MustChangePassword</c> يُفحص في الواجهة وحدها، فمن يملك
/// كلمةً مؤقتة (أعطاها له المدير عند الإنشاء أو إعادة التعيين) يستعمل الـAPI مباشرةً دون تغييرها
/// — **والمدير يعرف كلمته إلى الأبد**، فيستطيع الدخول باسمه، وسجلُّ التدقيق ينسب أفعالَه إليه.
///
/// الرمز يحمل علامة «يجب التغيير»، ولا يمرّ به إلا ما يلزم للتغيير نفسه. وتغييرُ الكلمة **يُصدر
/// رمزاً جديداً بلا العلامة**. ⚠️ **والجديدة تختلف عن المؤقتة** — وإلا صار «التغيير» شكلياً وبقي
/// المدير يعرفها.
/// </remarks>
public static class PasswordChangeGate
{
    public const int MinLength = 8;

    // ما يمرّ برمزٍ يحمل «يجب التغيير»: التغيير نفسه · الخروج · بياناتُ الجلسة · حالة النظام.
    private static readonly string[] Allowed =
    [
        "/api/auth/change-password",
        "/api/auth/logout",
        "/api/auth/me",
        "/api/auth/refresh",
        "/api/auth/login",
        "/api/system/status",
    ];

    /// <summary>هل يمرّ هذا المسار برمزٍ لم تُغيَّر كلمتُه المؤقتة بعد؟</summary>
    public static bool IsAllowedBeforeChange(string? path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        var p = path.Length > 1 ? path.TrimEnd('/') : path;
        foreach (var a in Allowed)
            if (string.Equals(p, a, StringComparison.OrdinalIgnoreCase)) return true;
        // الصفحة العامّة للتحقق لا تحتاج رمزاً أصلاً.
        return p.StartsWith("/v/", StringComparison.OrdinalIgnoreCase)
               || string.Equals(p, "/api/verify", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>يتحقّق من الكلمة الجديدة — ويرمي برسالةٍ عربية.</summary>
    public static void ValidateNew(string? current, string? next)
    {
        if (string.IsNullOrWhiteSpace(next) || next.Length < MinLength)
            throw new ValidationException($"كلمة المرور الجديدة يجب ألا تقل عن {MinLength} أحرف.");
        if (string.Equals(current, next, StringComparison.Ordinal))
            throw new ValidationException("كلمة المرور الجديدة يجب أن تختلف عن الحالية.");
    }
}
