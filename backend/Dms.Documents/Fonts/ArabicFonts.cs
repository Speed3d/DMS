using System.Reflection;
using QuestPDF.Drawing;

namespace Dms.Documents.Fonts;

/// <summary>
/// تسجيل الخطوط العربية المضمّنة (Amiri — OFL) داخل QuestPDF.
/// خط مفتوح الترخيص قابل للتضمين في PDF على السيرفر بلا قيود.
/// </summary>
public static class ArabicFonts
{
    /// <summary>اسم عائلة الخط كما هو في ملف TTF — يُستخدم في FontFamily(...).</summary>
    public const string Family = "Amiri";

    private static bool _registered;
    private static readonly object _lock = new();

    public static void EnsureRegistered()
    {
        if (_registered) return;
        lock (_lock)
        {
            if (_registered) return;

            RegisterEmbedded("Dms.Documents.Assets.Fonts.Amiri-Regular.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.Amiri-Bold.ttf");

            _registered = true;
        }
    }

    private static void RegisterEmbedded(string resourceName)
    {
        var asm = Assembly.GetExecutingAssembly();
        using var stream = asm.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException(
                $"تعذّر العثور على الخط المضمّن: {resourceName}. " +
                $"المتاح: {string.Join(", ", asm.GetManifestResourceNames())}");
        FontManager.RegisterFont(stream);
    }
}
