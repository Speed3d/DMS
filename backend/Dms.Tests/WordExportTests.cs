using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Documents.Word;
using CellFormula = Dms.Domain.BookTables.CellFormula;
using CellWords = Dms.Domain.BookTables.CellWords;
using Dms.Infrastructure.Documents;
using Xunit;

namespace Dms.Tests;

/// <summary>تصدير Word طبق الأصل (ADR-057، قرار المالك ت١٤) — ملفٌّ صالحٌ يفتحه Word، ومحتواه كالـPDF.</summary>
public class WordExportTests
{
    private static readonly byte[] Qr = QrSigner.CreateQrPng("https://dms.example/v/test");

    private static DocumentAssets Assets(bool withQr = true) => new(
        PlaceholderImages.CreateHeader(), PlaceholderImages.CreateFooter(), PlaceholderImages.CreateWatermark(), withQr ? Qr : null);

    private static BookDocument Book(string body, PrintSignatureMode mode = PrintSignatureMode.LastPage,
        bool pageNumbers = true, bool entity = true, bool subject = true) => new()
    {
        CompanyName = "شركة", Number = "DEN-2026-00007", Date = new DateOnly(2026, 10, 4), Entity = "وزارة النقل",
        Subject = "فاتورة رقم 7", Body = body, HeaderPhrase = "إلى", SignatoryName = "المدير", SignatoryTitle = "المدير المفوض",
        Tables = BookTablePrintMapper.Map(body), SignatureMode = mode, PageNumbers = pageNumbers,
        PrintEntity = entity, PrintSubject = subject,
    };

    /// <summary>جدولٌ بكل ما يصعب في Word: عناوين متكرّرة · دمجٌ أفقيّ وعموديّ · لون · Σ · حروف.</summary>
    private static string InvoiceBody(bool repeat = true, string dir = "rtl", int width = 100)
    {
        var t = T.Table(4, 1,
                T.R(T.C("ت", bg: "#AEAAAA"), T.C("المادة", bg: "#AEAAAA"), T.C("الكمية", bg: "#AEAAAA"), T.C("السعر الكلي", bg: "#AEAAAA")),
                T.R(T.C("1"), T.C("مدموجة عمودياً", rs: 2), T.C("2"), T.C("1,000")),
                T.R(T.C("2"), null, T.C("1"), T.C("250")),
                T.R(T.C("المجموع", cs: 2, bg: "#AEAAAA"), null, T.C("", f: new CellFormula { Col = 3 }, id: "sum"),
                    T.C("", w: new CellWords { SourceCellId = "sum", Prefix = "فقط", Suffix = "لا غير" })))
            with { RepeatHeader = repeat, Dir = dir, WidthPct = width };
        return "<p class=\"ql-align-center\"><strong><span style=\"font-size: 14pt; color: #C00000\">فاتورة</span></strong></p>"
               + T.Tag(t) + "<p>نصٌّ <em>بعد</em> الجدول <s>مشطوب</s>.</p>";
    }

    private static WordprocessingDocument Open(byte[] bytes) => WordprocessingDocument.Open(new MemoryStream(bytes), false);

    private static void AssertValid(byte[] bytes)
    {
        using var doc = Open(bytes);
        var errors = new OpenXmlValidator().Validate(doc).ToList();
        Assert.True(errors.Count == 0, "أخطاء OpenXML: " + string.Join(" | ", errors.Take(8).Select(e => $"{e.Path?.XPath}: {e.Description}")));
    }

    [Theory]
    [InlineData(PrintSignatureMode.LastPage, true, true)]
    [InlineData(PrintSignatureMode.StampEveryPage, false, true)]
    [InlineData(PrintSignatureMode.EveryPage, true, false)]
    public void EveryMode_ProducesAValidDocument(PrintSignatureMode mode, bool pageNumbers, bool withQr)
        => AssertValid(new WordExporter().Generate(Book(InvoiceBody(), mode, pageNumbers), Assets(withQr)));

    [Theory]
    [InlineData(false, "rtl", 100)]
    [InlineData(true, "ltr", 60)]
    public void TableVariants_AreValid(bool repeat, string dir, int width)
        => AssertValid(new WordExporter().Generate(Book(InvoiceBody(repeat, dir, width)), Assets()));

    [Fact]
    public void PlainBook_WithoutAssets_IsValid() => AssertValid(new WordExporter().Generate(Book("<p>كتاب عادي</p>")));

    [Fact]
    public void Table_HasMerges_RepeatedHeader_Shading_AndDirection()
    {
        using var doc = Open(new WordExporter().Generate(Book(InvoiceBody()), Assets()));
        var body = doc.MainDocumentPart!.Document!.Body!;
        var table = body.Elements<Table>().Single(t => t.GetFirstChild<TableProperties>()?.GetFirstChild<BiDiVisual>() is not null);   // جدول البيانات (العربيّ)

        Assert.NotNull(table.GetFirstChild<TableProperties>()!.GetFirstChild<BiDiVisual>());
        var rows = table.Elements<TableRow>().ToList();
        Assert.Equal(4, rows.Count);
        Assert.NotNull(rows[0].Descendants<TableHeader>().SingleOrDefault());           // العناوين تتكرّر
        Assert.Null(rows[1].Descendants<TableHeader>().SingleOrDefault());

        // كل صفٍّ يغطّي الأعمدة الأربعة: (gridSpan) + خانة الاستمرار تحت المدموج عمودياً
        foreach (var r in rows)
            Assert.Equal(4, r.Elements<TableCell>().Sum(c => (int?)c.TableCellProperties?.GridSpan?.Val?.Value ?? 1));
        Assert.Equal(DocumentFormat.OpenXml.Wordprocessing.MergedCellValues.Restart,
            rows[1].Elements<TableCell>().ElementAt(1).TableCellProperties!.VerticalMerge!.Val!.Value);
        Assert.Null(rows[2].Elements<TableCell>().ElementAt(1).TableCellProperties!.VerticalMerge!.Val);   // استمرار
        Assert.Equal("AEAAAA", rows[0].Descendants<Shading>().First().Fill!.Value);
    }

    [Fact]
    public void Formulas_AreRecomputed_AndTheTableTagLeavesNoText()
    {
        using var doc = Open(new WordExporter().Generate(Book(InvoiceBody()), Assets()));
        var text = doc.MainDocumentPart!.Document!.Body!.InnerText;
        Assert.Contains("1,250", text);
        Assert.Contains("فقط ألف ومئتان وخمسون دينار عراقي لا غير", text.Replace("مائتان", "مئتان"));
        Assert.DoesNotContain("data-dms-table", text);
        Assert.Contains("بعد", text);
    }

    [Fact]
    public void MixedFormatting_IsKept()
    {
        using var doc = Open(new WordExporter().Generate(Book(InvoiceBody()), Assets()));
        var runs = doc.MainDocumentPart!.Document!.Body!.Descendants<Run>().ToList();
        var title = runs.First(r => r.InnerText == "فاتورة");
        Assert.NotNull(title.RunProperties!.Bold);
        Assert.Equal("C00000", title.RunProperties.Color!.Val!.Value);
        Assert.Equal("28", title.RunProperties.FontSize!.Val!.Value);   // 14 نقطة
        Assert.NotNull(runs.First(r => r.InnerText == "بعد").RunProperties!.Italic);
        Assert.NotNull(runs.First(r => r.InnerText == "مشطوب").RunProperties!.Strike);
        Assert.Equal("Times New Roman", runs.First(r => r.InnerText.Contains("نصٌّ")).RunProperties!.RunFonts!.Ascii!.Value);
    }

    private static int FooterImages(WordprocessingDocument d) => d.MainDocumentPart!.FooterParts.Sum(f => f.ImageParts.Count());
    private static int BodyImages(WordprocessingDocument d) => d.MainDocumentPart!.ImageParts.Count();

    [Fact]
    public void LastPage_PutsSignatureAndStampAfterTheBody()
    {
        using var d = Open(new WordExporter().Generate(Book(InvoiceBody(), PrintSignatureMode.LastPage), Assets()));
        Assert.Equal(1, BodyImages(d));        // الختم بعد المتن
        Assert.Equal(1, FooterImages(d));      // صورة التذييل وحدها
        Assert.Contains("المدير المفوض", d.MainDocumentPart!.Document!.Body!.InnerText);
    }

    [Fact]
    public void StampEveryPage_PutsTheStampInTheFooter_AndTheSignatureAfterTheBody()
    {
        using var d = Open(new WordExporter().Generate(Book(InvoiceBody(), PrintSignatureMode.StampEveryPage), Assets()));
        Assert.Equal(0, BodyImages(d));
        Assert.Equal(2, FooterImages(d));      // التذييل + الختم
        Assert.Contains("المدير المفوض", d.MainDocumentPart!.Document!.Body!.InnerText);
        Assert.DoesNotContain("المدير المفوض", d.MainDocumentPart.FooterParts.Single().Footer!.InnerText);
    }

    [Fact]
    public void EveryPage_PutsBothInTheFooter()
    {
        using var d = Open(new WordExporter().Generate(Book(InvoiceBody(), PrintSignatureMode.EveryPage), Assets()));
        Assert.Equal(0, BodyImages(d));
        Assert.Contains("المدير المفوض", d.MainDocumentPart!.FooterParts.Single().Footer!.InnerText);
    }

    [Fact]
    public void Draft_WithoutQr_ShowsThePreviewBox()
    {
        using var d = Open(new WordExporter().Generate(Book(InvoiceBody()), Assets(withQr: false)));
        Assert.Contains("نسخة للمعاينة", d.MainDocumentPart!.Document!.Body!.InnerText);
        Assert.Equal(0, BodyImages(d));
    }

    [Fact]
    public void PageNumbers_UseConditionalFields_OnlyWhenEnabled()
    {
        using var on = Open(new WordExporter().Generate(Book("<p>x</p>", pageNumbers: true), Assets()));
        var codes = string.Concat(on.MainDocumentPart!.FooterParts.Single().Footer!.Descendants<FieldCode>().Select(f => f.Text));
        Assert.Contains("IF", codes);
        Assert.Contains("NUMPAGES", codes);
        Assert.Contains("PAGE", codes);
        Assert.Contains("> 1", codes);   // لا ترقيم في الصفحة الواحدة

        using var off = Open(new WordExporter().Generate(Book("<p>x</p>", pageNumbers: false), Assets()));
        Assert.Empty(off.MainDocumentPart!.FooterParts.Single().Footer!.Descendants<FieldCode>());
    }

    [Fact]
    public void EntityAndSubject_FollowThePrintOptions()
    {
        using var shown = Open(new WordExporter().Generate(Book("<p>x</p>"), Assets()));
        Assert.Contains("وزارة النقل", shown.MainDocumentPart!.Document!.Body!.InnerText);
        Assert.Contains("الموضوع / فاتورة رقم 7", shown.MainDocumentPart.Document!.Body!.InnerText);

        using var hidden = Open(new WordExporter().Generate(Book("<p>x</p>", entity: false, subject: false), Assets()));
        Assert.DoesNotContain("وزارة النقل", hidden.MainDocumentPart!.Document!.Body!.InnerText);
        Assert.DoesNotContain("الموضوع /", hidden.MainDocumentPart.Document!.Body!.InnerText);
    }

    [Fact]
    public void HeaderHasTheImage_AndTheWatermarkBehindTheText()
    {
        using var d = Open(new WordExporter().Generate(Book("<p>x</p>"), Assets()));
        var header = d.MainDocumentPart!.HeaderParts.Single();
        Assert.Equal(2, header.ImageParts.Count());
        Assert.True(header.Header!.Descendants<DocumentFormat.OpenXml.Drawing.Wordprocessing.Anchor>().Single().BehindDoc!.Value);
    }

    [Fact]
    public void NumericCells_DoNotWrap()
    {
        using var d = Open(new WordExporter().Generate(Book(InvoiceBody()), Assets()));
        var cells = d.MainDocumentPart!.Document!.Body!.Descendants<TableCell>().ToList();
        Assert.NotNull(cells.First(c => c.InnerText == "1,000").TableCellProperties!.NoWrap);
        Assert.Null(cells.First(c => c.InnerText == "المادة").TableCellProperties!.NoWrap);
    }

    [Fact]
    public void ImageSize_IsReadWithoutDecoding()
        => Assert.Equal((2480, 380), ImageOps.Size(PlaceholderImages.CreateHeader()));
}
