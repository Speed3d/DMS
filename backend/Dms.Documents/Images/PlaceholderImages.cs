using SkiaSharp;

namespace Dms.Documents.Images;

/// <summary>
/// صور القالب الافتراضي — الهيدر/الفوتر/العلامة المائية حين **لا يرفع المستخدم صوره**.
/// </summary>
/// <remarks>
/// 🔴 **محايدةٌ بلا اسمٍ ولا شعار** (قرار المالك 2026-08-20): كانت ترسم «DEN LAND» و
/// «Trading & Contracting» ودائرة «DL» وسطر «Baghdad, Iraq | +964 …». وهي بيانات
/// **مُختلَقة**، وكتابٌ رسميّ يخرج بعنوانٍ وهاتفٍ لا يملكهما أحد **أسوأ من كتابٍ بلا
/// ترويسة**: القارئ يصدّق ما هو مطبوع.
///
/// ⚠️ **الشكل بقي، والهوية سقطت**: الشريط المتدرّج والخطّ الذهبي وخطّ الفوتر باقية
/// ليبقى للمستند إطارٌ مرتّب — و**كل نصٍّ ورمزٍ يدلّ على جهةٍ بعينها أُزيل**.
/// ومَن يريد ترويسته يرفع صورته من الإعدادات، وهي تحلّ محلّ هذه كلّها.
///
/// الأبعاد بدقة قريبة من 300DPI لعرض A4 (~2480px).
/// </remarks>
public static class PlaceholderImages
{
    private static readonly SKColor Brand = new(0x0B, 0x3D, 0x91);   // أزرق داكن
    private static readonly SKColor BrandLight = new(0x2E, 0x6F, 0xD6);
    private static readonly SKColor Gold = new(0xC9, 0xA2, 0x2B);

    public static byte[] CreateHeader(int width = 2480, int height = 380)
    {
        using var bmp = new SKBitmap(width, height);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.White);

        using var grad = new SKPaint
        {
            Shader = SKShader.CreateLinearGradient(
                new SKPoint(0, 0), new SKPoint(width, 0),
                new[] { Brand, BrandLight }, null, SKShaderTileMode.Clamp),
            IsAntialias = true
        };
        canvas.DrawRect(0, 0, width, height, grad);

        // شريط ذهبي سفلي
        using var goldPaint = new SKPaint { Color = Gold, IsAntialias = true };
        canvas.DrawRect(0, height - 14, width, 14, goldPaint);

        // ⚠️ **بلا شعارٍ ولا اسم** — الشريط وحده (قرار المالك 2026-08-20).
        return Encode(bmp);
    }

    public static byte[] CreateFooter(int width = 2480, int height = 180)
    {
        using var bmp = new SKBitmap(width, height);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.White);

        using var line = new SKPaint { Color = Brand, IsAntialias = true, StrokeWidth = 6 };
        canvas.DrawLine(120, 20, width - 120, 20, line);

        // ⚠️ **بلا عنوانٍ ولا هاتفٍ ولا بريد** — بياناتٌ مُختلَقة على كتابٍ رسميّ
        //    أسوأ من فراغ (قرار المالك 2026-08-20).
        return Encode(bmp);
    }

    /// <param name="opacityPercent">0–100 — يطابق WatermarkOpacity في تصميم القالب.</param>
    public static byte[] CreateWatermark(int opacityPercent = 10, int size = 1400)
    {
        opacityPercent = Math.Clamp(opacityPercent, 0, 100);
        byte alpha = (byte)Math.Round(opacityPercent / 100.0 * 255);

        using var bmp = new SKBitmap(size, size);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.Transparent);

        var color = Brand.WithAlpha(alpha);
        float cx = size / 2f, cy = size / 2f;

        using var ring = new SKPaint
        {
            Color = color, IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 24
        };
        canvas.DrawCircle(cx, cy, size * 0.34f, ring);
        // ⚠️ **وحلقةٌ بلا حروف**: «DL» شعارٌ كغيره — والقاعدة واحدة في المواضع الثلاثة.
        return Encode(bmp);
    }

    private static byte[] Encode(SKBitmap bmp)
    {
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }
}
