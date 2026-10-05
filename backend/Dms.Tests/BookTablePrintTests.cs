using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Domain;
using Dms.Domain.BookTables;
using Dms.Infrastructure.Documents;
using Xunit;

namespace Dms.Tests;

/// <summary>قواعد صفحات التوقيع والختم والترقيم (ADR-057) — دوالُّ نقيّة يناديها الراسم.</summary>
public class PrintPageRulesTests
{
    [Fact]
    public void LastPage_FreesTheSpace_AndShowsBothOnTheLastPageOnly()
    {
        var m = PrintSignatureMode.LastPage;
        Assert.False(PrintPageRules.ReserveEveryPage(m));
        Assert.False(PrintPageRules.ShowSignature(m, 1, 7));
        Assert.False(PrintPageRules.ShowStamp(m, 6, 7));
        Assert.True(PrintPageRules.ShowSignature(m, 7, 7));
        Assert.True(PrintPageRules.ShowStamp(m, 7, 7));
    }

    [Fact]
    public void StampEveryPage_StampOnAll_SignatureOnLast_SpaceReserved()
    {
        var m = PrintSignatureMode.StampEveryPage;
        Assert.True(PrintPageRules.ReserveEveryPage(m));
        Assert.True(PrintPageRules.ShowStamp(m, 1, 7));
        Assert.False(PrintPageRules.ShowSignature(m, 1, 7));
        Assert.True(PrintPageRules.ShowSignature(m, 7, 7));
    }

    [Fact]
    public void EveryPage_IsTheBehaviourBeforeAdr057()
    {
        var m = PrintSignatureMode.EveryPage;
        Assert.True(PrintPageRules.ReserveEveryPage(m));
        Assert.True(PrintPageRules.ShowSignature(m, 1, 7) && PrintPageRules.ShowStamp(m, 1, 7));
    }

    [Fact]
    public void FirstLayoutPass_HasNoTotal_AndShowsNothingThatDependsOnIt()
    {
        // QuestPDF يرسم مرّتين؛ في الأولى «عدد الصفحات» مجهول — فلا يظهر ما يتوقّف عليه.
        Assert.False(PrintPageRules.ShowSignature(PrintSignatureMode.LastPage, 1, null));
        Assert.False(PrintPageRules.ShowPageNumber(true, null));
    }

    [Fact]
    public void PageNumbers_OnlyWhenEnabled_AndNeverOnASinglePageBook()
    {
        Assert.True(PrintPageRules.ShowPageNumber(true, 2));
        Assert.False(PrintPageRules.ShowPageNumber(true, 1));
        Assert.False(PrintPageRules.ShowPageNumber(false, 9));
    }
}

public class BookTablePrintMapperTests
{
    [Fact]
    public void Mapper_RecomputesTheTotal_IntoTheCell_KeepingItsFormatting()
    {
        var total = T.C("999", f: new CellFormula { Col = 0 }, id: "total") with { Html = "<p class=\"ql-align-center\"><strong>999</strong></p>" };
        var t = T.Table(1, 0, T.R(T.C("1,000")), T.R(T.C("250")), T.R(total));

        var print = BookTablePrintMapper.ToPrint(t);
        Assert.Equal("<p class=\"ql-align-center\"><strong>1,250</strong></p>", print.Cells.Single(c => c.Row == 2).Html);
    }

    [Fact]
    public void Mapper_KeepsOnlyRealCells_WithTheirSpans()
    {
        var t = T.Table(3, 1,
            T.R(T.C("أ", cs: 2), null, T.C("ب")),
            T.R(T.C("1"), T.C("2"), T.C("3")));
        var p = BookTablePrintMapper.ToPrint(t);
        Assert.Equal(5, p.Cells.Count);
        Assert.Equal((0, 0, 1, 2), (p.Cells[0].Row, p.Cells[0].Col, p.Cells[0].RowSpan, p.Cells[0].ColSpan));
        Assert.True(p.Rtl);
        Assert.Equal(3, p.ColumnWeights.Count);
    }

    [Fact]
    public void Mapper_RefusesAnInvalidStoredTable()
    {
        var bad = T.Table(2, 0, T.R(T.C("a"), null));   // خانةٌ بلا دمج
        Assert.Throws<ValidationException>(() => BookTablePrintMapper.Map(T.Tag(bad)));
    }

    [Theory]
    [InlineData(SignaturePlacement.LastPage, PrintSignatureMode.LastPage)]
    [InlineData(SignaturePlacement.StampEveryPage, PrintSignatureMode.StampEveryPage)]
    [InlineData(SignaturePlacement.EveryPage, PrintSignatureMode.EveryPage)]
    public void SignatureModes_MapOneToOne(SignaturePlacement p, PrintSignatureMode m) => Assert.Equal(m, BookTablePrintMapper.Mode(p));

    [Theory]
    [InlineData("<p><strong>500</strong></p>", "1,250", "<p><strong>1,250</strong></p>")]
    [InlineData("<p></p>", "12", "<p>12</p>")]
    [InlineData("<p><br></p>", "12", "<p>12</p>")]
    [InlineData("", "12", "<p>12</p>")]
    [InlineData("<p>ألف <em>ومائة</em></p>", "فقط مائة", "<p>فقط مائة<em></em></p>")]
    // 🐛 خليةُ المجموع الفارغة بتنسيقها: الرقم يرث العريض والحجم (كان يخرج رفيعاً صغيراً)
    [InlineData("<p class=\"ql-align-center\"><strong><span style=\"font-size: 14pt\"></span></strong></p>", "9,450,000,000",
        "<p class=\"ql-align-center\"><strong><span style=\"font-size: 14pt\">9,450,000,000</span></strong></p>")]
    public void WithText_ReplacesTheText_KeepsTheTags(string html, string text, string expected)
        => Assert.Equal(expected, TableFormulas.WithText(html, text));

    [Fact]
    public void HeaderCell_SpanningIntoTheBody_IsRejected()
    {
        var t = T.Table(2, 1, T.R(T.C("أ", rs: 2), T.C("ب")), T.R(null, T.C("1")));
        Assert.Contains("صفوف العناوين", Assert.Throws<ValidationException>(() => BookTableRules.Validate(t)).Message);
    }

    [Theory]
    [InlineData("<p>1,425,000,000</p>", true)]
    [InlineData("<p><strong>1,430.33</strong></p>", true)]
    [InlineData("<p>١٬٤٢٥</p>", true)]
    [InlineData("<p>2 قطعة</p>", false)]
    [InlineData("<p>ـــــ</p>", false)]
    [InlineData("<p></p>", false)]
    public void NumericCells_AreDetected(string html, bool numeric) => Assert.Equal(numeric, HtmlToQuestPdf.IsNumeric(html));
}

/// <summary>
/// رسمٌ حقيقيّ بـQuestPDF (ADR-057) — عدد الصفحات يُقاس بالصور الناتجة بلا مكتبةٍ إضافية. والنصوص والمواضع
/// تُفحص خارج الاختبارات (PyMuPDF) وتُذكر في سجلّ الدفعة.
/// </summary>
public class BookTableRenderTests
{
    private static readonly DocumentAssets Assets = new(
        PlaceholderImages.CreateHeader(), PlaceholderImages.CreateFooter(), PlaceholderImages.CreateWatermark(),
        QrSigner.CreateQrPng("https://dms.example/v/test"));

    private static BookDocument Book(string body, PrintSignatureMode mode = PrintSignatureMode.LastPage,
        bool pageNumbers = true, bool entity = true, bool subject = true) => new()
    {
        CompanyName = "شركة", Number = "DEN-2026-00007", Date = new DateOnly(2026, 10, 4), Entity = "جهة",
        Subject = "فاتورة", Body = body, SignatoryName = "المدير", SignatoryTitle = "المدير المفوض",
        Tables = BookTablePrintMapper.Map(body), SignatureMode = mode, PageNumbers = pageNumbers,
        PrintEntity = entity, PrintSubject = subject,
    };

    private static int Pages(BookDocument b) => new PdfGenerator().GeneratePreviewImages(b, Assets).Count();

    /// <summary>جدولٌ طويل بشكل فاتورة المالك: عناوين + بنودٌ بنصٍّ متعدّد الأسطر + مجموعٌ مدموج.</summary>
    private static string LongInvoiceBody(int rows, bool repeatHeader = true, int widthPct = 100, string dir = "rtl")
    {
        var sumId = "sum";
        var list = new List<TableRow> { T.R(T.C("ت"), T.C("Item"), T.C("المادة"), T.C("الكمية"), T.C("سعر المفرد"), T.C("السعر الكلي")) };
        for (var i = 1; i <= rows; i++)
            list.Add(T.R(T.C($"{i}"), T.C("CAT III - ILS Localizer, Dual Equipment, Dual Frequency, 240 VAC"),
                T.C("جهاز لتحديد مركز المدرج للطائرة ذو التصنيف الثالث"), T.C("2"), T.C("1,425,000,000"), T.C("2,850,000,000")));
        list.Add(T.R(T.C("المجموع", cs: 2), null, T.C("", cs: 2, f: new CellFormula { Col = 5 }, id: sumId), null,
            T.C("", cs: 2, w: new CellWords { SourceCellId = sumId, Prefix = "فقط", Suffix = "لا غير" }), null));
        var t = T.Table(6, 1, [.. list]) with { RepeatHeader = repeatHeader, WidthPct = widthPct, Dir = dir,
            Cols = new[] { 876, 2977, 2410, 834, 1559, 1712 }.Select((w, i) => new TableColumn { Id = $"k{i}", Weight = w }).ToList() };
        return "<p class=\"ql-align-center\"><strong>فاتورة</strong></p>" + T.Tag(t);
    }

    [Fact]
    public void ShortBook_StaysOnOnePage()
        => Assert.Equal(1, Pages(Book("<p>نصٌّ قصير.</p>")));

    [Fact]
    public void LongTable_FlowsAcrossPages_AndFreeingTheSpaceSavesPages()
    {
        var body = LongInvoiceBody(40);
        var free = Pages(Book(body, PrintSignatureMode.LastPage));
        var reserved = Pages(Book(body, PrintSignatureMode.EveryPage));
        Assert.True(free > 1, $"الجدول الطويل يمتدّ على أكثر من صفحة ({free})");
        Assert.True(free < reserved, $"تفريغ المساحة يوفّر صفحات: {free} مقابل {reserved}");
        Assert.Equal(reserved, Pages(Book(body, PrintSignatureMode.StampEveryPage)));   // الختم في كل صفحة ⟵ الحجز باقٍ
    }

    [Theory]
    [InlineData(false, 100, "rtl")]   // العناوين في البداية فقط
    [InlineData(true, 60, "rtl")]     // جدولٌ أضيق من المتن يمتدّ على صفحات
    [InlineData(true, 100, "ltr")]    // جدولٌ إنجليزيّ يبدأ من اليسار
    public void TableVariants_RenderAcrossPages_WithoutLayoutErrors(bool repeat, int width, string dir)
        => Assert.True(Pages(Book(LongInvoiceBody(30, repeat, width, dir))) > 1);

    [Fact]
    public void TextAndSeveralTables_RenderTogether()
    {
        var a = T.Table(3, 0, T.R(T.C("عمودي", rs: 2), T.C("أفقي", cs: 2), null), T.R(null, T.C("x"), T.C("y")));
        var b = T.Table(2, 1, T.R(T.C("No"), T.C("Item")), T.R(T.C("1"), T.C("Item")));
        Assert.Equal(1, Pages(Book($"<p>قبل</p>{T.Tag(a)}<p>بين</p>{T.Tag(b)}<p>بعد</p>")));
    }

    [Fact]
    public void HiddenEntityAndSubject_AndNoPageNumbers_StillRender()
        => Assert.True(Pages(Book(LongInvoiceBody(20), entity: false, subject: false, pageNumbers: false)) >= 1);
}
