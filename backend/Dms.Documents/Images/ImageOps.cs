using SkiaSharp;

namespace Dms.Documents.Images;

/// <summary>عمليات صور مساعدة (تشغّل على أي منصّة عبر SkiaSharp).</summary>
public static class ImageOps
{
    /// <summary>يطبّق شفافية عامة (0–100%) على صورة PNG ويعيدها PNG.</summary>
    public static byte[] ApplyOpacity(byte[] png, int opacityPercent)
    {
        opacityPercent = Math.Clamp(opacityPercent, 0, 100);
        if (opacityPercent == 100) return png;

        using var src = SKBitmap.Decode(png);
        if (src is null) return png;

        using var surface = new SKBitmap(src.Width, src.Height, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(surface);
        canvas.Clear(SKColors.Transparent);

        using var paint = new SKPaint
        {
            Color = SKColors.White.WithAlpha((byte)Math.Round(opacityPercent / 100.0 * 255)),
            IsAntialias = true
        };
        using var srcImage = SKImage.FromBitmap(src);
        canvas.DrawImage(srcImage,
            new SKRect(0, 0, src.Width, src.Height),
            new SKSamplingOptions(SKFilterMode.Linear),
            paint);
        canvas.Flush();

        using var img = SKImage.FromBitmap(surface);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }
}
