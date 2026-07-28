using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// محلّل أسماء ملفات الأرشيف — الأمثلة مأخوذة من **أسماء المالك الحقيقية**، وهي مختلطة:
/// منها المفيد ومنها ناتج الماسح الأعمى.
/// </summary>
public class ArchiveFileNameParserTests
{
    [Theory]
    [InlineData("وزارة الكهرباء - طلب تجهيز - 2023-05-12.pdf", "وزارة الكهرباء - طلب تجهيز", 2023, 5, 12)]
    [InlineData("عقد مقاولة 2022_11_03.docx", "عقد مقاولة", 2022, 11, 3)]
    [InlineData("فاتورة رقم 55 - 03-06-2024.xlsx", "فاتورة رقم 55", 2024, 6, 3)]
    [InlineData("مخاطبة بلدية 20230918.pdf", "مخاطبة بلدية", 2023, 9, 18)]
    public void ExtractsTitleAndDate(string file, string title, int y, int m, int d)
    {
        var p = ArchiveFileNameParser.Parse(file);
        Assert.Equal(title, p.Title);
        Assert.Equal(new DateTime(y, m, d), p.Date);
        Assert.False(p.NeedsTitle);
    }

    [Theory]
    [InlineData("IMG_0234.pdf")]
    [InlineData("Scan_001.pdf")]
    [InlineData("scan.pdf")]
    [InlineData("DOC001.docx")]
    [InlineData("image 12.png")]
    [InlineData("00234.pdf")]
    [InlineData("Untitled.pdf")]
    public void MarksMeaninglessNamesInsteadOfInventingTitles(string file)
    {
        var p = ArchiveFileNameParser.Parse(file);

        // ⚠️ الجوهر: لا نخترع عنواناً. الاسم الأعمى يبقى **بلا عنوان معلَّماً** ليُحسَّن
        //    لاحقاً — لأن «مستند 234» عنوانٌ كاذب يوهم بأن البيانات مكتملة.
        Assert.Null(p.Title);
        Assert.True(p.NeedsTitle);
    }

    [Fact]
    public void KeepsDateEvenWhenNameIsMeaningless()
    {
        // ماسحات تُسمّي الملف برقم وتاريخ — التاريخ مفيد ولو كان الباقي بلا معنى.
        var p = ArchiveFileNameParser.Parse("IMG_0234 2023-05-12.pdf");
        Assert.Equal(new DateTime(2023, 5, 12), p.Date);
        Assert.True(p.NeedsTitle);
    }

    [Fact]
    public void IgnoresImpossibleDatesInsteadOfThrowing()
    {
        // «2023-13-45» يطابق النمط ولا يصلح تاريخاً. لو بُني مباشرةً لرمى استثناءً
        // **فأفشل استيراد الدفعة كلها بسبب ملف واحد**.
        var p = ArchiveFileNameParser.Parse("كتاب 2023-13-45.pdf");
        Assert.Null(p.Date);
        Assert.Equal("كتاب 2023-13-45", p.Title);
    }

    [Fact]
    public void HandlesEmptyAndExtensionOnlyNames()
    {
        Assert.True(ArchiveFileNameParser.Parse("").NeedsTitle);
        Assert.True(ArchiveFileNameParser.Parse("   ").NeedsTitle);
        Assert.True(ArchiveFileNameParser.Parse(".pdf").NeedsTitle);
    }

    [Fact]
    public void NormalizesUnderscoresAndExtraSpaces()
    {
        var p = ArchiveFileNameParser.Parse("كتاب__رسمي___مهم.pdf");
        Assert.Equal("كتاب رسمي مهم", p.Title);
    }
}
