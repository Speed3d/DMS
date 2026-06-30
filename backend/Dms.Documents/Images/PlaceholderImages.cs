using SkiaSharp;

namespace Dms.Documents.Images;

/// <summary>
/// مولّد صور بديلة (placeholder) للهيدر/الفوتر/العلامة المائية — لمحاكاة الصور التي ستوفّرها الشركة.
/// نستخدم نصوصاً لاتينية هنا (الشعار/الترويسة صورة جاهزة في الإنتاج)؛
/// صحّة العربية RTL تُختبر في متن الـ PDF عبر QuestPDF (تشكيل HarfBuzz).
/// الأبعاد بدقة قريبة من 300DPI لعرض A4 (~2480px).
/// </summary>
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

        // دائرة الشعار "DL"
        float cx = 180, cy = height / 2f, r = 110;
        using var circle = new SKPaint { Color = SKColors.White, IsAntialias = true };
        canvas.DrawCircle(cx, cy, r, circle);
        DrawText(canvas, "DL", cx, cy + 38, 110, Brand, SKFontStyle.Bold, center: true);

        // اسم الشركة (لاتيني)
        DrawText(canvas, "DEN LAND", 360, cy - 10, 120, SKColors.White, SKFontStyle.Bold);
        DrawText(canvas, "Trading & Contracting", 362, cy + 90, 56, SKColors.White, SKFontStyle.Normal);

        return Encode(bmp);
    }

    public static byte[] CreateFooter(int width = 2480, int height = 180)
    {
        using var bmp = new SKBitmap(width, height);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.White);

        using var line = new SKPaint { Color = Brand, IsAntialias = true, StrokeWidth = 6 };
        canvas.DrawLine(120, 20, width - 120, 20, line);

        DrawText(canvas, "Baghdad, Iraq  |  +964 770 000 0000  |  info@denland.iq",
            width / 2f, 110, 48, Brand, SKFontStyle.Normal, center: true);

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
        DrawText(canvas, "DL", cx, cy + 150, 460, color, SKFontStyle.Bold, center: true);

        return Encode(bmp);
    }

    private static void DrawText(SKCanvas canvas, string text, float x, float y,
        float textSize, SKColor color, SKFontStyle style, bool center = false)
    {
        using var typeface = SKTypeface.FromFamilyName("Arial", style)
                             ?? SKTypeface.Default;
        using var font = new SKFont(typeface, textSize);
        using var paint = new SKPaint { Color = color, IsAntialias = true };
        var align = center ? SKTextAlign.Center : SKTextAlign.Left;
        canvas.DrawText(text, x, y, align, font, paint);
    }

    private static byte[] Encode(SKBitmap bmp)
    {
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }
}
