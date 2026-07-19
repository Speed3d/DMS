using System.Reflection;
using QuestPDF.Drawing;

namespace Dms.Documents.Fonts;

/// <summary>
/// تسجيل الخطوط المضمّنة داخل QuestPDF: Amiri/Cairo (OFL) + Arial/Times New Roman (وفّرها المالك).
/// أسماء العائلات (Family) تُستخدم في FontFamily(...) وفي خريطة HtmlToQuestPdf.
/// </summary>
public static class ArabicFonts
{
    /// <summary>الخط الافتراضي للمتن.</summary>
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
            RegisterEmbedded("Dms.Documents.Assets.Fonts.Cairo-Regular.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.Cairo-Bold.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.arial.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.arialbd.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.times.ttf");
            RegisterEmbedded("Dms.Documents.Assets.Fonts.timesbd.ttf");

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
