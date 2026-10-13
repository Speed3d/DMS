using System.Net;
using System.Text.Json;
using Dms.Domain;
using Dms.Domain.BookTables;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// معادلات الجداول (ADR-060): المحلّل · الحساب الدقيق · المراجع · الأعمدة المحسوبة · الأخطاء — **والأمثلة المشتركة مع المحرّر**
/// (<c>Fixtures/table-calc-vectors.json</c>) يُخرج لها الخادم والمحرّر النصّ نفسه.
/// </summary>
public class TableCalcTests
{
    // ─────────────────────────── الأمثلة المشتركة ───────────────────────────

    private static readonly string VectorsPath = FindVectors();

    private static string FindVectors()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var p = Path.Combine(dir.FullName, "Dms.Tests", "Fixtures", "table-calc-vectors.json");
            if (File.Exists(p)) return p;
        }
        throw new FileNotFoundException("table-calc-vectors.json");
    }

    public static TheoryData<string> VectorNames()
    {
        var data = new TheoryData<string>();
        using var doc = JsonDocument.Parse(File.ReadAllText(VectorsPath));
        foreach (var v in doc.RootElement.GetProperty("vectors").EnumerateArray()) data.Add(v.GetProperty("name").GetString()!);
        return data;
    }

    [Theory]
    [MemberData(nameof(VectorNames))]
    public void SharedVector_ComputesExactlyAsTheEditorDoes(string name)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(VectorsPath));
        var v = doc.RootElement.GetProperty("vectors").EnumerateArray().First(x => x.GetProperty("name").GetString() == name);
        var table = Build(v);
        BookTableRules.Validate(table);   // ما في الأمثلة يمرّ بقواعد الحفظ
        var computed = TableFormulas.Evaluate(table, (d, _) => $"حروف {d}");

        foreach (var e in v.GetProperty("expected").EnumerateObject())
        {
            Assert.True(computed.TryGetValue(e.Name, out var c), $"{name}: الخلية {e.Name} لم تُحسب");
            var shown = c!.Error is { } code ? $"{TableFormulas.ErrorText}:{code}" : c.Text;
            Assert.Equal(e.Value.GetString(), shown);
        }
        if (v.TryGetProperty("absent", out var absent))
            foreach (var id in absent.EnumerateArray())
                Assert.False(computed.ContainsKey(id.GetString()!), $"{name}: الخلية {id} حُسبت ولا يجب");
    }

    /// <summary>جدولٌ من صيغة الأمثلة المختصرة — النصّ وحده خلية، والكائن يحمل المعرّف والمعادلة والجمع والحروف والدمج.</summary>
    internal static BookTable Build(JsonElement v)
    {
        var cols = v.GetProperty("cols").EnumerateArray().Select(c => new TableColumn
        {
            Id = c.GetProperty("id").GetString()!,
            Calc = c.TryGetProperty("calc", out var calc) ? new CellCalc { Expr = calc.GetString()! } : null,
        }).ToList();
        var rows = new List<TableRow>();
        var ri = 0;
        foreach (var row in v.GetProperty("rows").EnumerateArray())
        {
            var cells = new List<TableCell?>();
            var ci = 0;
            foreach (var x in row.EnumerateArray())
            {
                var auto = $"r{ri}c{ci}";
                cells.Add(x.ValueKind switch
                {
                    JsonValueKind.Null => null,
                    JsonValueKind.String => new TableCell { Id = auto, Html = P(x.GetString()!) },
                    _ => new TableCell
                    {
                        Id = x.TryGetProperty("id", out var id) ? id.GetString()! : auto,
                        Html = P(x.TryGetProperty("text", out var t) ? t.GetString()! : ""),
                        RowSpan = x.TryGetProperty("span", out var sp) ? sp[0].GetInt32() : 1,
                        ColSpan = x.TryGetProperty("span", out var sp2) ? sp2[1].GetInt32() : 1,
                        Calc = x.TryGetProperty("calc", out var calc) ? new CellCalc { Expr = calc.GetString()! } : null,
                        Formula = x.TryGetProperty("sum", out var sum) ? new CellFormula { Col = sum.GetInt32() } : null,
                        Words = x.TryGetProperty("words", out var w) ? new CellWords { SourceCellId = w.GetString()! } : null,
                    },
                });
                ci++;
            }
            rows.Add(new TableRow { Id = $"r{ri}", Cells = cells });
            ri++;
        }
        return new BookTable { Id = "t", HeaderRows = v.GetProperty("headerRows").GetInt32(), Cols = cols, Rows = rows };
    }

    private static string P(string text) => text.Length == 0 ? "<p><br/></p>" : $"<p>{WebUtility.HtmlEncode(text)}</p>";

    // ─────────────────────────── المحلّل ───────────────────────────

    [Theory]
    [InlineData("{c1}*{c2}", new[] { "c1", "c2" })]
    [InlineData("({a}+{b})÷{a}", new[] { "a", "b" })]
    [InlineData("12.5 × 2 − 1", new string[0])]
    [InlineData("١٢٫٥*٢", new string[0])]
    public void Parse_AcceptsTheStoredForm_AndListsRefsOnce(string expr, string[] refs)
        => Assert.Equal(refs, TableExpression.Parse(expr).Refs);

    [Theory]
    [InlineData("")]
    [InlineData("2+")]
    [InlineData("(2+3")]
    [InlineData("2+3)")]
    [InlineData("{a")]
    [InlineData("{}")]
    [InlineData("{a b}")]
    [InlineData("{../x}")]          // 🔐 لا رموز خارج المعرّف
    [InlineData("2 ^ 3")]
    [InlineData("1.2.3")]
    [InlineData("SUM(A1)")]
    [InlineData("1234567890123456789")]   // أطول من 18 رقماً
    public void Parse_RejectsWhatIsNotAnExpression_InArabic(string expr)
    {
        var ex = Assert.Throws<ValidationException>(() => TableExpression.Parse(expr));
        Assert.Matches(@"\p{IsArabic}", ex.Message);
    }

    [Fact]
    public void Parse_EnforcesLength_Refs_AndDepth()
    {
        Assert.Throws<ValidationException>(() => TableExpression.Parse(new string('1', 10) + string.Concat(Enumerable.Repeat("+1", 260))));
        Assert.Throws<ValidationException>(() => TableExpression.Parse(string.Join("+", Enumerable.Range(0, 51).Select(i => $"{{c{i}}}"))));
        Assert.Throws<ValidationException>(() => TableExpression.Parse(new string('(', 25) + "1" + new string(')', 25)));
        Assert.Equal(50, TableExpression.Parse(string.Join("+", Enumerable.Range(0, 50).Select(i => $"{{c{i}}}"))).Refs.Count);
    }

    // ─────────────────────────── الدقة ───────────────────────────

    [Fact]
    public void Rational_IsExact_WhereDoubleIsNot()
    {
        var r = TableExpression.Parse("0.1+0.2").Evaluate(_ => default);
        Assert.Equal(new Rational(3, 10), r.Value);
        Assert.Equal(1m, TableExpression.Parse("(1/3)*3").Evaluate(_ => default).Value!.Value.ToDecimal());
    }

    [Theory]
    [InlineData("2.345", "2.35")]
    [InlineData("-2.345", "-2.35")]
    [InlineData("2.344", "2.34")]
    [InlineData("0.005", "0.01")]
    [InlineData("-0.005", "-0.01")]
    public void RoundCents_IsHalfAwayFromZero(string value, string expected)
    {
        var r = TableExpression.Parse(value).Evaluate(_ => default).Value!.Value.RoundCents();
        Assert.Equal(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture), r.ToDecimal());
    }

    [Theory]
    [InlineData(0, "A")]
    [InlineData(25, "Z")]
    [InlineData(26, "AA")]
    [InlineData(29, "AD")]
    public void ColumnLetter_IsExcelStyle(int index, string letter) => Assert.Equal(letter, TableFormulas.ColumnLetter(index));

    // ─────────────────────────── لا أثر على القائم ───────────────────────────

    [Fact]
    public void ExistingInvoice_WithoutCalcs_ComputesExactlyAsBefore()
    {
        var t = T.Invoice(out var sumId, out var wordsId);
        var c = TableFormulas.Evaluate(t, (d, _) => $"حروف {d}");
        Assert.Equal(new[] { sumId, wordsId }.OrderBy(x => x), c.Keys.OrderBy(x => x));   // لا خلايا محسوبةٌ جديدة
        Assert.Equal("2,981,000,000", c[sumId].Text);
        Assert.Equal(2_981_000_000m, c[sumId].Value);
        Assert.Null(c[sumId].Error);
        Assert.Equal("حروف 2981000000", c[wordsId].Text);
    }

    // ─────────────────────────── القواعد والاعتماد ───────────────────────────

    [Fact]
    public void Rules_RejectABrokenStoredExpression_ButAllowAMissingReference()
    {
        var bad = T.Table(1, 0, T.R(T.C("") with { Calc = new CellCalc { Expr = "2+" } }));
        var ex = Assert.Throws<ValidationException>(() => BookTableRules.Validate(bad));
        Assert.Contains("معادلة الخلية", ex.Message);

        // مرجعٌ إلى خليةٍ حُذفت: المسوّدة تُحفظ — والخطأ يمنع الاعتماد وحده (قرار المالك)
        var dangling = T.Table(1, 0, T.R(T.C("") with { Calc = new CellCalc { Expr = "{gone}*2" } }));
        BookTableRules.Validate(dangling);
        var appr = Assert.Throws<ValidationException>(() => BookTableRules.EnsureNoFormulaErrors(T.Tag(dangling)));
        Assert.Contains("الخلية A1", appr.Message);
        Assert.Contains("قبل الاعتماد", appr.Message);
    }

    [Fact]
    public void Rules_RejectACalcCombinedWithSumOrWords_AndABrokenColumnExpression()
    {
        var both = T.Table(2, 0, T.R(T.C("5"), T.C("", f: new CellFormula { Col = 0 }) with { Calc = new CellCalc { Expr = "1" } }));
        Assert.Throws<ValidationException>(() => BookTableRules.Validate(both));
        var col = T.Table(2, 0, T.R(T.C("1"), T.C("2")));
        col = col with { Cols = [col.Cols[0], col.Cols[1] with { Calc = new CellCalc { Expr = "{k0}*" } }] };
        var ex = Assert.Throws<ValidationException>(() => BookTableRules.Validate(col));
        Assert.Contains("معادلة العمود", ex.Message);
    }

    [Fact]
    public void Approval_PassesForCorrectFormulas_AndTablesWithoutFormulas()
    {
        BookTableRules.EnsureNoFormulaErrors(T.Tag(T.Invoice(out _, out _)));
        var ok = T.Table(2, 0, T.R(T.C("4", id: "a"), T.C("") with { Calc = new CellCalc { Expr = "{a}/2" } }));
        BookTableRules.EnsureNoFormulaErrors(T.Tag(ok));
        BookTableRules.EnsureNoFormulaErrors("<p>كتابٌ بلا جدول</p>");
    }

    [Fact]
    public void Print_ReplacesTheCellText_WithTheComputedValue_KeepingItsFormatting()
    {
        var t = T.Table(3, 0, T.R(T.C("3", id: "q"), T.C("1,500", id: "p"),
            new TableCell { Id = "x", Html = "<p><strong><span style=\"font-size: 14pt\"></span></strong></p>", Calc = new CellCalc { Expr = "{q}*{p}" } }));
        var printed = Infrastructure.Documents.BookTablePrintMapper.ToPrint(t);
        var cell = printed.Cells.Single(c => c.Col == 2);
        Assert.Contains("<strong><span style=\"font-size: 14pt\">4,500</span></strong>", cell.Html);
    }

    [Fact]
    public void Diff_ReportsCalcChanges()
    {
        var a = T.Table(2, 0, T.R(T.C("4", id: "a"), T.C("", id: "b") with { Calc = new CellCalc { Expr = "{a}*2" } }));
        var b = a with
        {
            Rows = [a.Rows[0] with { Cells = [a.Rows[0].Cells[0], a.Rows[0].Cells[1]! with { Calc = new CellCalc { Expr = "{a}*3" } }] }],
            Cols = [a.Cols[0], a.Cols[1] with { Calc = new CellCalc { Expr = "{k0}+1" } }],
        };
        var d = BookTableDiff.Describe(T.Tag(a), T.Tag(b));
        Assert.Contains(d.Summaries, s => s.Contains("معادلة خلية") && s.Contains("معادلة عمود") && !s.Contains("تنسيق"));
    }
}
