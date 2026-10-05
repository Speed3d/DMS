using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Documents.Word;
using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// موضع «صفحة X من Y» في القالب (بلاغ المالك 2026-10-05): يمين · وسط · يسار وإزاحةٌ بالمليمتر. والقيم تُفحص في
/// <see cref="PageNumberPosition"/> وحدها. ومع <c>DMS_PAGENUM_OUT</c> تُكتب ملفات الـPDF لقياس موضع الرقم بـPyMuPDF.
/// </summary>
public class PageNumberPositionTests
{
    [Theory]
    [InlineData(null, "center")]      // القوالب القائمة ⟵ الوسط كما كانت
    [InlineData("", "center")]
    [InlineData(" Right ", "right")]
    [InlineData("LEFT", "left")]
    [InlineData("center", "center")]
    public void Align_IsNormalised(string? value, string expected) => Assert.Equal(expected, PageNumberPosition.Align(value));

    [Fact]
    public void Align_RejectsUnknownValues_InArabic()
    {
        var ex = Assert.Throws<ValidationException>(() => PageNumberPosition.Align("top"));
        Assert.Contains("ترقيم الصفحة", ex.Message);
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(25, 25)]
    [InlineData(500, PageNumberPosition.MaxOffsetXMm)]
    [InlineData(-500, -PageNumberPosition.MaxOffsetXMm)]
    public void OffsetX_IsClamped(int mm, int expected) => Assert.Equal(expected, PageNumberPosition.OffsetX(mm));

    [Theory]
    [InlineData(10, 10)]
    [InlineData(200, PageNumberPosition.MaxOffsetYMm)]
    [InlineData(-200, -PageNumberPosition.MaxOffsetYMm)]
    public void OffsetY_IsClamped(int mm, int expected) => Assert.Equal(expected, PageNumberPosition.OffsetY(mm));

    [Fact]
    public void NewTemplate_DefaultsToTheOldBehaviour()
    {
        var t = new Template();
        Assert.Equal((PageNumberPosition.Center, 0, 0), (t.PageNumberAlign, t.PageNumberOffsetX, t.PageNumberOffsetY));
    }

    // ─────────────────────────── الطباعة والتصدير ───────────────────────────

    private static readonly DocumentAssets Assets = new(PlaceholderImages.CreateHeader(), PlaceholderImages.CreateFooter(),
        PlaceholderImages.CreateWatermark(), QrSigner.CreateQrPng("https://dms.example/v/test"));

    private static BookDocument Book(string align, int xMm, int yMm) => new()
    {
        CompanyName = "شركة", Number = "DEN-2026-00007", Date = new DateOnly(2026, 10, 5), Entity = "جهة", Subject = "اختبار",
        // متنٌ يمتدّ على صفحتين — فالترقيم يُطبع
        Body = string.Concat(Enumerable.Repeat("<p>نصٌّ طويلٌ يملأ الصفحة ليمتدّ الكتاب إلى صفحةٍ ثانية فيُطبع الترقيم في أسفلها.</p>", 60)),
        SignatoryName = "المدير", PageNumbers = true,
        PageNumberAlign = align,
        PageNumberOffsetXPt = xMm * PageNumberPosition.PointsPerMm,
        PageNumberOffsetYPt = yMm * PageNumberPosition.PointsPerMm,
    };

    public static TheoryData<string, int, int> Positions => new()
    {
        { "center", 0, 0 }, { "right", 0, 0 }, { "left", 0, 0 },
        { "center", 30, 10 }, { "right", -20, -5 }, { "left", 15, 25 },
        { "center", -PageNumberPosition.MaxOffsetXMm, PageNumberPosition.MaxOffsetYMm },
    };

    [Theory]
    [MemberData(nameof(Positions))]
    public void Pdf_RendersEveryPosition_WithoutLayoutErrors(string align, int x, int y)
    {
        var r = new PdfGenerator().Render(Book(align, x, y), Assets);
        Assert.True(r.TotalPages > 1);
        var dir = Environment.GetEnvironmentVariable("DMS_PAGENUM_OUT");
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
            File.WriteAllBytes(Path.Combine(dir, $"{align}_{x}_{y}.pdf"), r.Pdf);
        }
    }

    [Theory]
    [MemberData(nameof(Positions))]
    public void Word_PlacesThePageNumber_AndStaysValid(string align, int x, int y)
    {
        var bytes = new WordExporter().Generate(Book(align, x, y), Assets);
        using var doc = WordprocessingDocument.Open(new MemoryStream(bytes), false);
        Assert.Empty(new OpenXmlValidator().Validate(doc));
        var p = doc.MainDocumentPart!.FooterParts.SelectMany(f => f.Footer!.Descendants<Paragraph>())
            .Single(p => p.InnerText.Contains("صفحة"));
        var jc = p.ParagraphProperties!.Justification!.Val!.Value;
        Assert.Equal(align switch { "right" => JustificationValues.Right, "left" => JustificationValues.Left, _ => JustificationValues.Center }, jc);
        Assert.Null(p.ParagraphProperties.BiDi);   // المحاذاة فيزيائية — Word يقلبها في الفقرة العربية
        Assert.Equal(x == 0, p.ParagraphProperties.Indentation is null);
    }
}
