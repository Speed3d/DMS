using Dms.Documents.Images;
using SkiaSharp;
using Xunit;

/// <summary>
/// حرّاس **القالب الافتراضي المحايد** (قرار المالك 2026-08-20).
///
/// 🔴 **سبب وجودها:** كانت الصور الافتراضية ترسم «DEN LAND» و«Trading &amp; Contracting»
/// ودائرة «DL» وسطر «Baghdad, Iraq | +964 770 000 0000 | info@denland.iq» — وهي بيانات
/// **مُختلَقة**. وكتابٌ رسميّ يخرج بعنوانٍ وهاتفٍ لا يملكهما أحد **أسوأ من كتابٍ بلا
/// ترويسة**: القارئ يصدّق ما هو مطبوع، والشركة تُسأل عن رقمٍ ليس رقمها.
///
/// ⚠️ **والقياس على البكسل لا على النصّ**: اختبارٌ يقرأ الكود ويتأكّد من غياب السلسلة
/// يمرّ على رسمٍ بحروفٍ مبنيّة بطريقةٍ أخرى. هنا **نفحص الصورة الناتجة**.
public class PlaceholderImagesTests
{
    private static SKBitmap Decode(byte[] png) => SKBitmap.Decode(png);

    [Fact]
    public void الهيدر_الافتراضي_بلا_شعارٍ_ولا_اسم()
    {
        using var bmp = Decode(PlaceholderImages.CreateHeader());

        // الشعار والاسم كانا **أبيضَين** فوق الشريط المتدرّج. والشريط يغطّي الصورة
        // كاملةً، فبقاءُ بكسلٍ أبيض واحد يعني أن شيئاً رُسم فوقه.
        var white = 0;
        for (var x = 0; x < bmp.Width; x += 3)
        for (var y = 0; y < bmp.Height; y += 3)
        {
            var c = bmp.GetPixel(x, y);
            if (c.Red > 245 && c.Green > 245 && c.Blue > 245) white++;
        }

        Assert.True(white == 0, $"الهيدر ما زال يحمل رسماً أبيض ({white} بكسل) — شعارٌ أو اسم؟");
    }

    [Fact]
    public void الفوتر_الافتراضي_بلا_عنوانٍ_ولا_هاتفٍ_ولا_بريد()
    {
        using var bmp = Decode(PlaceholderImages.CreateFooter());

        // لم يبقَ في الفوتر إلا الخطّ العلويّ (نحو y = 20). وسطر التواصل كان عند y = 110.
        var marked = 0;
        for (var x = 0; x < bmp.Width; x += 3)
        for (var y = 60; y < bmp.Height; y += 3)
        {
            var c = bmp.GetPixel(x, y);
            if (c.Alpha > 0 && (c.Red < 240 || c.Green < 240 || c.Blue < 240)) marked++;
        }

        Assert.True(marked == 0, $"الفوتر ما زال يحمل نصّاً تحت الخطّ ({marked} بكسل)");
    }

    /// <summary>⚠️ والخطّ العلويّ **يبقى** — المطلوب حيادٌ لا فراغ.</summary>
    [Fact]
    public void لكنّ_إطار_المستند_يبقى_مرتّباً()
    {
        using var footer = Decode(PlaceholderImages.CreateFooter());
        var line = 0;
        for (var x = 200; x < footer.Width - 200; x += 5)
        {
            var c = footer.GetPixel(x, 20);
            if (c.Red < 240 || c.Green < 240 || c.Blue < 240) line++;
        }
        Assert.True(line > 0, "اختفى خطّ الفوتر أيضاً — هذا فراغٌ لا حياد");

        using var header = Decode(PlaceholderImages.CreateHeader());
        Assert.Equal(2480, header.Width);
        Assert.True(header.Height > 0);
    }

    /// <summary>
    /// 🔴 **والعلامة المائية كذلك**: «DL» شعارٌ كغيره، والقاعدة واحدة في المواضع الثلاثة.
    /// </summary>
    [Fact]
    public void العلامة_المائية_حلقةٌ_بلا_حروف()
    {
        using var bmp = Decode(PlaceholderImages.CreateWatermark(100));

        // مركز الصورة كان يحمل «DL» بحجم 460 — فيبقى فارغاً الآن.
        // (والحلقة عند نصف قطرٍ 0.34 من الحجم، بعيدةٌ عن هذه النافذة.)
        var cx = bmp.Width / 2;
        var cy = bmp.Height / 2;
        var marked = 0;
        for (var x = cx - 150; x < cx + 150; x += 3)
        for (var y = cy - 150; y < cy + 150; y += 3)
            if (bmp.GetPixel(x, y).Alpha > 0) marked++;

        Assert.True(marked == 0, $"مركز العلامة المائية ما زال يحمل رسماً ({marked} بكسل)");
    }

    /// <summary>والحلقة نفسها باقية — وإلا صارت العلامة المائية بلا أثر.</summary>
    [Fact]
    public void والحلقة_باقية()
    {
        using var bmp = Decode(PlaceholderImages.CreateWatermark(100));
        var cx = bmp.Width / 2;
        var ringY = (int)(bmp.Height / 2 - bmp.Width * 0.34);

        var marked = 0;
        for (var y = ringY - 20; y <= ringY + 20; y++)
            if (bmp.GetPixel(cx, y).Alpha > 0) marked++;

        Assert.True(marked > 0, "اختفت الحلقة — العلامة المائية صارت شفافةً بالكامل");
    }
}
