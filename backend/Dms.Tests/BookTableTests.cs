using System.Net;
using System.Text.Json;
using Dms.Domain;
using Dms.Domain.BookTables;
using Xunit;

namespace Dms.Tests;

/// <summary>بناءُ جداولٍ للاختبار — بالشكل الذي يكتبه المحرّر.</summary>
internal static class T
{
    private static int _seq;
    private static string Id(string p) => $"{p}{Interlocked.Increment(ref _seq)}";

    public static TableCell C(string text, int rs = 1, int cs = 1, string? bg = null,
        CellFormula? f = null, CellWords? w = null, string? id = null) =>
        new() { Id = id ?? Id("c"), RowSpan = rs, ColSpan = cs, Bg = bg, Html = $"<p>{WebUtility.HtmlEncode(text)}</p>", Formula = f, Words = w };

    public static TableRow R(params TableCell?[] cells) => new() { Id = Id("r"), Cells = [.. cells] };

    public static BookTable Table(int cols, int headerRows, params TableRow[] rows) => new()
    {
        Id = Id("t"), HeaderRows = headerRows, NumberingCol = 0,
        Cols = Enumerable.Range(0, cols).Select(i => new TableColumn { Id = $"k{i}", Weight = 1 }).ToList(),
        Rows = [.. rows],
    };

    /// <summary>الوسم كما يكتبه مُسلسِل المحرّر داخل <c>BodyHtml</c>.</summary>
    public static string Tag(BookTable t) =>
        $"<div data-dms-table=\"{WebUtility.HtmlEncode(JsonSerializer.Serialize(t, BookTableJson.Options))}\"></div>";

    /// <summary>
    /// فاتورةٌ **بشكل** فاتورة المالك (لا ببياناتها): 6 أعمدة · عناوين · بنودٌ · صفّ «مواد احتياطية» بخلايا فارغة ·
    /// بنودٌ فرعية · وصفّ مجموعٍ مدموج: «المجموع» (عمودان) · Σ تحت «العربي+الكمية» تجمع «السعر الكلي» · والحروف.
    /// </summary>
    public static BookTable Invoice(out string sumId, out string wordsId)
    {
        sumId = Id("sum");
        wordsId = Id("words");
        return Table(6, 1,
            R(C("ت"), C("المادة بالإنجليزي"), C("المادة بالعربي"), C("الكمية"), C("سعر المفرد"), C("السعر الكلي")),
            R(C("1"), C("Item A"), C("مادة أ"), C("2"), C("1,425,000,000"), C("2,850,000,000")),
            R(C("2"), C("Item B"), C("مادة ب"), C("2"), C("50,000,000"), C("100,000,000")),
            R(C("17"), C("Spare Part"), C("مواد احتياطية"), C(""), C(""), C("")),
            R(C("17.1"), C("CCA"), C("ـــــــ"), C("2"), C("15,000,000"), C("30,000,000")),
            R(C("17.2"), C("USB HUB"), C("ـــــــ"), C("1"), C("1,000,000"), C("1,000,000")),
            R(C("المجموع", cs: 2), null,
              C("", cs: 2, f: new CellFormula { Col = 5 }, id: sumId), null,
              C("", cs: 2, w: new CellWords { SourceCellId = sumId, Currency = "IQD" }, id: wordsId), null));
    }
}

public class BookTableCodecTests
{
    [Fact]
    public void Extract_FindsEveryTable_InOrder_AndDecodesTheAttribute()
    {
        var a = T.Table(1, 0, T.R(T.C("أ \"مقتبس\" & <علامة>")));
        var b = T.Table(1, 0, T.R(T.C("ب")));
        var html = $"<p>قبل</p>{T.Tag(a)}<p>بين</p>{T.Tag(b)}<p>بعد</p>";

        var tables = BookTableCodec.ReadAll(html);
        Assert.Equal([a.Id, b.Id], tables.Select(t => t.Id));
        Assert.Equal("أ \"مقتبس\" & <علامة>", BookTableCodec.PlainText(tables[0].Rows[0].Cells[0]!.Html));
    }

    [Fact]
    public void SingleQuotedAttribute_IsReadToo()
    {
        var json = JsonSerializer.Serialize(T.Table(1, 0, T.R(T.C("x"))), BookTableJson.Options);
        Assert.Single(BookTableCodec.ReadAll($"<div data-dms-table='{WebUtility.HtmlEncode(json)}'></div>"));
    }

    [Fact]
    public void StripTables_LeavesTheTextAround()
        => Assert.Equal("<p>قبل</p><p>بعد</p>", BookTableCodec.StripTables($"<p>قبل</p>{T.Tag(T.Table(1, 0, T.R(T.C("x"))))}<p>بعد</p>"));

    [Fact]
    public void NoTables_IsEmpty_NotAnError()
    {
        Assert.Empty(BookTableCodec.ReadAll("<p>نص</p>"));
        Assert.Empty(BookTableCodec.ReadAll(null));
        Assert.False(BookTableCodec.HasTables("<p>نص</p>"));
    }

    [Fact]
    public void BrokenJson_IsAValidationError_WithTheTableNumber()
    {
        var ex = Assert.Throws<ValidationException>(() =>
            BookTableCodec.ReadAll($"{T.Tag(T.Table(1, 0, T.R(T.C("x"))))}<div data-dms-table=\"{{not json\"></div>"));
        Assert.Contains("الجدول 2", ex.Message);
    }

    [Fact]
    public void PlainText_FoldsTagsEntitiesAndSpaces()
        => Assert.Equal("1,425,000,000", BookTableCodec.PlainText("<p><strong>1,425,000,000</strong>&nbsp;</p>"));
}

public class BookTableRulesTests
{
    private static void Ok(BookTable t) => BookTableRules.Validate(t);

    private static string Bad(BookTable t) => Assert.Throws<ValidationException>(() => BookTableRules.Validate(t, 3)).Message;

    [Fact]
    public void InvoiceShape_IsValid() => Ok(T.Invoice(out _, out _));

    [Fact]
    public void Messages_CarryTheTableNumber() => Assert.StartsWith("الجدول 3:", Bad(T.Table(2, 0, T.R(T.C("a")))));

    [Fact]
    public void RowWithWrongCellCount_IsRejected() => Assert.Contains("لا يطابق", Bad(T.Table(2, 0, T.R(T.C("a")))));

    [Fact]
    public void HoleNotCoveredByMerge_IsRejected() => Assert.Contains("لا يغطّيها دمج", Bad(T.Table(2, 0, T.R(T.C("a"), null))));

    [Fact]
    public void CellInsideAnotherMerge_IsRejected()
        => Assert.Contains("داخل دمجٍ آخر", Bad(T.Table(2, 0, T.R(T.C("a", cs: 2), T.C("b")))));

    [Fact]
    public void MergeOutsideTheTable_IsRejected()
        => Assert.Contains("يخرج عن حدود", Bad(T.Table(2, 0, T.R(T.C("a"), T.C("b", rs: 2)))));

    [Fact]
    public void VerticalAndHorizontalMergeTogether_IsValid()
        => Ok(T.Table(3, 0,
            T.R(T.C("عمودي", rs: 2), T.C("أفقي", cs: 2), null),
            T.R(null, T.C("x"), T.C("y"))));

    [Fact]
    public void BadColor_IsRejected() => Assert.Contains("لون", Bad(T.Table(1, 0, T.R(T.C("a", bg: "red")))));

    [Fact]
    public void ScriptTag_IsRejected()
    {
        var t = T.Table(1, 0, T.R(T.C("a") with { Html = "<p>x</p><script>alert(1)</script>" }));
        Assert.Contains("script", Bad(t));
    }

    [Fact]
    public void MixedFormatting_IsAllowed()
        => Ok(T.Table(1, 0, T.R(T.C("a") with { Html = "<p>نص <strong>عريض</strong> <em>مائل</em> <span style=\"color: #C00000\">أحمر</span><br/>سطر</p>" })));

    [Fact]
    public void TooManyColumns_IsRejected()
    {
        var cols = BookTableRules.MaxColumns + 1;
        Assert.Contains("الأعمدة", Bad(T.Table(cols, 0, T.R(Enumerable.Range(0, cols).Select(_ => T.C("x")).ToArray()))));
    }

    [Fact]
    public void FormulaColumnOutside_IsRejected()
        => Assert.Contains("صيغة", Bad(T.Table(1, 0, T.R(T.C("", f: new CellFormula { Col = 4 })))));

    [Fact]
    public void WordsFromMissingCell_IsRejected()
        => Assert.Contains("غير موجودة", Bad(T.Table(1, 0, T.R(T.C("", w: new CellWords { SourceCellId = "nope" })))));

    [Fact]
    public void UnknownCurrency_IsRejected()
    {
        var src = T.C("5", id: "src");
        Assert.Contains("عملة", Bad(T.Table(2, 0, T.R(src, T.C("", w: new CellWords { SourceCellId = "src", Currency = "EUR" })))));
    }

    [Fact]
    public void HeaderRowsMoreThanRows_IsRejected()
        => Assert.Contains("العناوين", Bad(T.Table(1, 2, T.R(T.C("a")))));

    [Fact]
    public void DuplicateCellIds_AreRejected()
        => Assert.Contains("المعرّف نفسه", Bad(T.Table(2, 0, T.R(T.C("a", id: "same"), T.C("b", id: "same")))));

    [Fact]
    public void FutureFormatVersion_IsRejected_NotMisread()
        => Assert.Contains("لا يعرفها", Bad(T.Table(1, 0, T.R(T.C("a"))) with { V = 2 }));

    [Fact]
    public void Body_MoreThanMaxTables_IsRejected()
    {
        var body = string.Concat(Enumerable.Range(0, BookTableRules.MaxTables + 1).Select(_ => T.Tag(T.Table(1, 0, T.R(T.C("x"))))));
        Assert.Throws<ValidationException>(() => BookTableRules.ValidateBody(body));
    }

    [Fact]
    public void Body_TwoTablesWithSameId_AreRejected()
    {
        var t = T.Table(1, 0, T.R(T.C("x")));
        Assert.Throws<ValidationException>(() => BookTableRules.ValidateBody(T.Tag(t) + T.Tag(t)));
    }

    [Fact]
    public void Body_WithoutTables_PassesUntouched() => Assert.Empty(BookTableRules.ValidateBody("<p>كتاب عادي</p>"));
}
