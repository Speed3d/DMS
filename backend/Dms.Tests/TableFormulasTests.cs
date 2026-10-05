using Dms.Domain;
using Dms.Domain.BookTables;
using Xunit;

namespace Dms.Tests;

public class TableFormulasTests
{
    [Theory]
    [InlineData("1,425,000,000", 1425000000)]
    [InlineData("1430.33", 1430.33)]
    [InlineData("1,430.33", 1430.33)]
    [InlineData("١٬٤٢٥٬٠٠٠", 1425000)]      // أرقامٌ هندية وفاصل آلافٍ عربي
    [InlineData("١٤٣٠٫٣٣", 1430.33)]        // فاصلةٌ عشرية عربية
    [InlineData(" 2 ", 2)]
    [InlineData("-5", -5)]
    public void ParseNumber_ReadsWhatPeopleWrite(string text, double expected)
        => Assert.Equal((decimal)expected, TableFormulas.ParseNumber(text));

    [Theory]
    [InlineData("")]
    [InlineData("ـــــــ")]
    [InlineData("2 قطعة")]
    [InlineData("1.2.3")]
    [InlineData("مواد احتياطية")]
    public void ParseNumber_TextIsNotANumber(string text) => Assert.Null(TableFormulas.ParseNumber(text));

    [Fact]
    public void InvoiceTotal_SumsTheChosenColumn_SkippingTheEmptyGroupRow()
    {
        var t = T.Invoice(out var sumId, out _);
        BookTableRules.Validate(t);
        var r = TableFormulas.Evaluate(t, (_, _) => "حروف");
        // 2,850,000,000 + 100,000,000 + (صفّ «مواد احتياطية» الفارغ) + 30,000,000 + 1,000,000
        Assert.Equal(2_981_000_000m, r[sumId].Value);
        Assert.Equal("2,981,000,000", r[sumId].Text);
    }

    [Fact]
    public void Words_FollowTheLiveSum_WithPrefixAndSuffix()
    {
        var t = T.Invoice(out var sumId, out var wordsId);
        var wordsCell = t.Rows[^1].Cells[4]!;
        t.Rows[^1].Cells[4] = wordsCell with { Words = wordsCell.Words! with { Prefix = "فقط", Suffix = "لا غير" } };

        var r = TableFormulas.Evaluate(t);
        Assert.Equal("فقط ملياران وتسعمائة وواحد وثمانون مليون دينار عراقي لا غير", r[wordsId].Text);

        // تغيّر سعرٌ ⟵ تتغيّر الحروف معه (قرار المالك: «تتغيّر وتتحدّث»)
        t.Rows[1].Cells[5] = T.C("2,000,000,000");
        Assert.Equal(2_131_000_000m, TableFormulas.Evaluate(t)[sumId].Value);
    }

    [Fact]
    public void Subtotals_AreNotCountedTwice()
    {
        var sub = T.C("", f: new CellFormula { Col = 1 }, id: "sub");
        var total = T.C("", f: new CellFormula { Col = 1 }, id: "total");
        var t = T.Table(2, 1,
            T.R(T.C("ت"), T.C("المبلغ")),
            T.R(T.C("1"), T.C("100")),
            T.R(T.C("2"), T.C("200")),
            T.R(T.C("مجموع فرعي"), sub),
            T.R(T.C("3"), T.C("50")),
            T.R(T.C("المجموع"), total));
        var r = TableFormulas.Evaluate(t);
        Assert.Equal(300m, r["sub"].Value);
        Assert.Equal(350m, r["total"].Value);   // لا 650
    }

    [Fact]
    public void VerticallyMergedNumber_CountsOnce()
    {
        var total = T.C("", f: new CellFormula { Col = 1 }, id: "total");
        var t = T.Table(2, 0,
            T.R(T.C("a"), T.C("100", rs: 2)),
            T.R(T.C("b"), null),
            T.R(T.C("="), total));
        Assert.Equal(100m, TableFormulas.Evaluate(t)["total"].Value);
    }

    [Fact]
    public void AnyFraction_GivesTwoDecimals()
    {
        var total = T.C("", f: new CellFormula { Col = 0 }, id: "total");
        var t = T.Table(1, 0, T.R(T.C("1,000")), T.R(T.C("430.3")), T.R(total));
        Assert.Equal("1,430.30", TableFormulas.Evaluate(t)["total"].Text);
    }

    [Fact]
    public void ClientValueIsIgnored_TheServerRecomputes()
    {
        var total = T.C("999,999", f: new CellFormula { Col = 0 }, id: "total");   // رقمٌ «أرسله العميل»
        var t = T.Table(1, 0, T.R(T.C("5")), T.R(T.C("7")), T.R(total));
        Assert.Equal("12", TableFormulas.Evaluate(t)["total"].Text);
    }

    [Fact]
    public void WordsFromATypedNumber_AndUsdCents()
    {
        var t = T.Table(2, 0, T.R(T.C("1,430.33", id: "n"), T.C("", w: new CellWords { SourceCellId = "n", Currency = "USD" }, id: "w")));
        Assert.Equal("ألف وأربعمائة وثلاثون دولار أمريكي وثلاثة وثلاثون سنتاً", TableFormulas.Evaluate(t)["w"].Text);
    }

    [Fact]
    public void WordsFromText_IsEmpty_NotACrash()
    {
        var t = T.Table(2, 0, T.R(T.C("نص", id: "n"), T.C("", w: new CellWords { SourceCellId = "n", Prefix = "فقط" }, id: "w")));
        Assert.Equal("فقط", TableFormulas.Evaluate(t)["w"].Text);
    }
}

public class ArabicNumberWordsTests
{
    [Theory]
    // نموذج المالك نفسه (بالمئات الموصولة — قراره 2026-10-04)
    [InlineData(9_450_000_000, "IQD", "تسعة مليارات وأربعمائة وخمسون مليون دينار عراقي")]
    [InlineData(0, "IQD", "صفر دينار عراقي")]
    [InlineData(1, "IQD", "واحد دينار عراقي")]
    [InlineData(11, "IQD", "أحد عشر دينار عراقي")]
    [InlineData(12, "IQD", "اثنا عشر دينار عراقي")]
    [InlineData(21, "IQD", "واحد وعشرون دينار عراقي")]
    [InlineData(100, "IQD", "مائة دينار عراقي")]
    [InlineData(200, "IQD", "مئتان دينار عراقي")]
    [InlineData(500, "IQD", "خمسمائة دينار عراقي")]
    [InlineData(900, "IQD", "تسعمائة دينار عراقي")]
    [InlineData(1_000, "IQD", "ألف دينار عراقي")]
    [InlineData(2_000, "IQD", "ألفان دينار عراقي")]
    [InlineData(3_000, "IQD", "ثلاثة آلاف دينار عراقي")]
    [InlineData(10_000, "IQD", "عشرة آلاف دينار عراقي")]
    [InlineData(11_000, "IQD", "أحد عشر ألف دينار عراقي")]
    [InlineData(103_000, "IQD", "مائة وثلاثة آلاف دينار عراقي")]
    [InlineData(1_000_000, "IQD", "مليون دينار عراقي")]
    [InlineData(2_500_000, "IQD", "مليونان وخمسمائة ألف دينار عراقي")]
    [InlineData(15_000_000, "IQD", "خمسة عشر مليون دينار عراقي")]
    [InlineData(1_000_000_001, "IQD", "مليار وواحد دينار عراقي")]
    [InlineData(2_850_000_000, "IQD", "ملياران وثمانمائة وخمسون مليون دينار عراقي")]
    public void Integers(double amount, string currency, string expected)
        => Assert.Equal(expected, ArabicNumberWords.ToWords((decimal)amount, currency));

    [Theory]
    [InlineData(1430.33, "ألف وأربعمائة وثلاثون دولار أمريكي وثلاثة وثلاثون سنتاً")]
    [InlineData(1.01, "واحد دولار أمريكي وسنت واحد")]
    [InlineData(5.02, "خمسة دولار أمريكي وسنتان")]
    [InlineData(5.05, "خمسة دولار أمريكي وخمسة سنتات")]
    [InlineData(0.5, "خمسون سنتاً")]
    public void UsdWithCents(double amount, string expected)
        => Assert.Equal(expected, ArabicNumberWords.ToWords((decimal)amount, "USD"));

    [Fact]
    public void IqdFraction_IsFils() => Assert.Equal("عشرة دينار عراقي وخمسمائة فلساً", ArabicNumberWords.ToWords(10.5m, "IQD"));

    [Fact]
    public void Rounding_ToAWholeUnit_CarriesOver() => Assert.Equal("ستة دولار أمريكي", ArabicNumberWords.ToWords(5.999m, "USD"));

    [Fact]
    public void Negative_Huge_AndUnknownCurrency_AreRejected()
    {
        Assert.Throws<ValidationException>(() => ArabicNumberWords.ToWords(-1, "IQD"));
        Assert.Throws<ValidationException>(() => ArabicNumberWords.ToWords(ArabicNumberWords.Max + 1, "IQD"));
        Assert.Throws<ValidationException>(() => ArabicNumberWords.ToWords(1, "EUR"));
    }
}

public class BookTableDiffTests
{
    private static string Body(params BookTable[] tables) => "<p>نص</p>" + string.Concat(tables.Select(T.Tag));

    [Fact]
    public void Unchanged_SaysNothing()
    {
        var body = Body(T.Invoice(out _, out _));
        var r = BookTableDiff.Describe(body, body);
        Assert.False(r.Any);
        Assert.Null(r.Details);
    }

    [Fact]
    public void ChangedCells_AreListed_WithRowAndColumnNames()
    {
        var before = T.Invoice(out _, out _);
        var after = before with { Rows = [.. before.Rows] };
        after.Rows[2] = after.Rows[2] with { Cells = [.. after.Rows[2].Cells] };
        after.Rows[2].Cells[5] = after.Rows[2].Cells[5]! with { Html = "<p>125,000,000</p>" };

        var r = BookTableDiff.Describe(Body(before), Body(after));
        Assert.Equal("الجدول 1: تغيّرت خلية", r.Summaries.Single());
        Assert.Equal("البند 2 — السعر الكلي: 100,000,000 ⟵ 125,000,000", r.CellChanges.Single());
    }

    [Fact]
    public void AddedAndRemovedRows_AreCounted_ByIdNotPosition()
    {
        var before = T.Invoice(out _, out _);
        var inserted = T.R(T.C("1.5"), T.C("New"), T.C("جديد"), T.C("1"), T.C("5"), T.C("5"));
        var after = before with { Rows = [before.Rows[0], inserted, .. before.Rows.Skip(1).Where((_, i) => i != 2)] };

        var r = BookTableDiff.Describe(Body(before), Body(after));
        Assert.Equal("الجدول 1: أُضيف صفّ · حُذف صفّ", r.Summaries.Single());
        Assert.Empty(r.CellChanges);   // إدراجٌ في الأعلى لا يجعل ما تحته «متغيّراً»
    }

    [Fact]
    public void MoreThanTen_IsSummarised()
    {
        var rows = Enumerable.Range(1, 15).Select(i => T.R(T.C($"{i}"), T.C("قديم"))).ToArray();
        var before = T.Table(2, 0, rows);
        var after = before with { Rows = before.Rows.Select(r => r with { Cells = [r.Cells[0], r.Cells[1]! with { Html = "<p>جديد</p>" }] }).ToList() };

        var r = BookTableDiff.Describe(Body(before), Body(after));
        Assert.Equal(BookTableDiff.MaxListedCells, r.CellChanges.Count);
        Assert.Equal(5, r.More);
        Assert.EndsWith("و5 غيرها", r.Details);
        Assert.Contains("تغيّرت 15 خلية", r.Summaries.Single());
    }

    [Fact]
    public void FormattingOnly_IsNotATextChange()
    {
        var before = T.Table(1, 0, T.R(T.C("نص")));
        var after = before with { Rows = [before.Rows[0] with { Cells = [before.Rows[0].Cells[0]! with { Html = "<p><strong>نص</strong></p>", Bg = "#AEAAAA" }] }] };
        var r = BookTableDiff.Describe(Body(before), Body(after));
        Assert.Equal("الجدول 1: تنسيق خلية", r.Summaries.Single());
        Assert.Empty(r.CellChanges);
    }

    [Fact]
    public void AddedAndDeletedTables()
    {
        var a = T.Table(2, 0, T.R(T.C("x"), T.C("y")));
        var b = T.Table(1, 0, T.R(T.C("z")));
        Assert.Equal("أُضيف الجدول 1 (عمودان × صفّ)", BookTableDiff.Describe(Body(), Body(a)).Summaries.Single());
        Assert.Equal("حُذف الجدول 2", BookTableDiff.Describe(Body(a, b), Body(a)).Summaries.Single());
    }

    [Fact]
    public void BrokenOldBody_DoesNotFailTheLog()
        => Assert.False(BookTableDiff.Describe("<div data-dms-table=\"{bad\"></div>", Body()).Any);
}

public class OutgoingChangesTablesTests
{
    private static OutgoingFields F(string body, SignaturePlacement sp = SignaturePlacement.LastPage, int? type = 1) => new(
        1, 1, new DateTime(2026, 10, 4), null, null, null, "فاتورة", body, null, null, null, type, true, true, true, sp);

    [Fact]
    public void TableEdit_IsTables_NotBody()
    {
        var before = T.Table(1, 0, T.R(T.C("1")));
        var after = before with { Rows = [before.Rows[0] with { Cells = [before.Rows[0].Cells[0]! with { Html = "<p>2</p>" }] }] };
        Assert.Equal(["الجداول"], OutgoingChanges.Describe(F("<p>نص</p>" + T.Tag(before)), F("<p>نص</p>" + T.Tag(after))));
    }

    [Fact]
    public void TextEdit_AroundAnUnchangedTable_IsBody()
    {
        var t = T.Tag(T.Table(1, 0, T.R(T.C("1"))));
        Assert.Equal(["المتن"], OutgoingChanges.Describe(F("<p>نص</p>" + t), F("<p>نص معدّل</p>" + t)));
    }

    [Fact]
    public void TypeAndPrintOptions_HaveTheirNames()
    {
        Assert.Equal(["النوع"], OutgoingChanges.Describe(F("<p>x</p>"), F("<p>x</p>", type: 2)));
        Assert.Equal(["خيارات الطباعة"], OutgoingChanges.Describe(F("<p>x</p>"), F("<p>x</p>", SignaturePlacement.EveryPage)));
    }
}
