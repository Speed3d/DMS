using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Models;
using Dms.Documents.Pdf;

namespace Dms.Documents.Word;

/// <summary>
/// جدول الطباعة ⟵ جدول Word (ADR-057): الدمج الأفقيّ (<c>gridSpan</c>) والعموديّ (<c>vMerge</c>) · الخلفية · الحدود ·
/// المحاذاة العمودية · تكرار العناوين (<c>tblHeader</c>) · الاتجاه (<c>bidiVisual</c>) · العرض والمحاذاة.
/// </summary>
/// <remarks>
/// 🔑 **في Word لكل صفٍّ خليةٌ لكل عمودٍ من الشبكة** — والمدموجُ عمودياً يحتاج في الصفوف التالية خليةَ «استمرار»
/// (<c>vMerge</c> بلا قيمة) بالامتداد الأفقيّ نفسه، وإلا انزاحت أعمدة الصفّ كلُّها. نموذج الطباعة لا يحمل تلك الخانات،
/// فتُولَّد هنا.
/// </remarks>
internal static class WordTables
{
    /// <summary>عرض المتن بالـtwips (595 − 2×40 نقطة) — كما في الـPDF.</summary>
    public const int ContentWidthTwips = 10300;

    private const string CellMarginTwips = "80";   // 4 نقاط — هامش الخلية في الـPDF

    public static Table Build(PrintTable t)
    {
        var cols = t.ColumnWeights.Count;
        var width = ContentWidthTwips * Math.Clamp(t.WidthPct, 30, 100) / 100;
        var sum = t.ColumnWeights.Sum();
        var colW = t.ColumnWeights.Select(w => (int)Math.Round(width * w / sum)).ToArray();

        var props = new TableProperties();
        if (t.Rtl) props.AppendChild(new BiDiVisual());
        props.AppendChild(new TableWidth { Width = width.ToString(), Type = TableWidthUnitValues.Dxa });
        // ⚠️ محاذاة الجدول في مستندٍ عربيّ: «بداية» السطر هي اليمين.
        props.AppendChild(new TableJustification
        {
            Val = t.Align switch
            {
                "start" => TableRowAlignmentValues.Right,
                "end" => TableRowAlignmentValues.Left,
                _ => TableRowAlignmentValues.Center,
            },
        });
        props.AppendChild(Borders(t));
        props.AppendChild(new TableLayout { Type = TableLayoutValues.Fixed });
        props.AppendChild(new TableCellMarginDefault(
            new TopMargin { Width = CellMarginTwips, Type = TableWidthUnitValues.Dxa },
            new TableCellLeftMargin { Width = 80, Type = TableWidthValues.Dxa },
            new BottomMargin { Width = CellMarginTwips, Type = TableWidthUnitValues.Dxa },
            new TableCellRightMargin { Width = 80, Type = TableWidthValues.Dxa }));

        var table = new Table(props, new TableGrid(colW.Select(w => new GridColumn { Width = w.ToString() })));

        // الخلايا الحقيقية وخانات الاستمرار تحتها (الدمج العموديّ)
        var masters = t.Cells.ToDictionary(c => (c.Row, c.Col));
        var continuation = new Dictionary<(int, int), PrintCell>();
        foreach (var c in t.Cells.Where(c => c.RowSpan > 1))
            for (var r = c.Row + 1; r < c.Row + c.RowSpan; r++) continuation[(r, c.Col)] = c;

        for (var r = 0; r < t.RowCount; r++)
        {
            var row = new TableRow();
            if (r < t.HeaderRows && t.RepeatHeader)
                row.AppendChild(new TableRowProperties(new TableHeader()));

            for (var c = 0; c < cols;)
            {
                if (masters.TryGetValue((r, c), out var cell))
                {
                    row.AppendChild(Cell(cell, colW, merge: cell.RowSpan > 1 ? MergedCellValues.Restart : null, t));
                    c += Math.Max(1, cell.ColSpan);
                }
                else if (continuation.TryGetValue((r, c), out var above))
                {
                    row.AppendChild(Cell(above, colW, merge: MergedCellValues.Continue, t, empty: true));
                    c += Math.Max(1, above.ColSpan);
                }
                else c++;   // لا يحدث في جدولٍ مفحوص
            }
            table.AppendChild(row);
        }
        return table;
    }

    private static TableCell Cell(PrintCell cell, int[] colW, MergedCellValues? merge, PrintTable t, bool empty = false)
    {
        var span = Math.Max(1, cell.ColSpan);
        var w = colW.Skip(cell.Col).Take(span).Sum();
        var tcPr = new TableCellProperties(new TableCellWidth { Width = w.ToString(), Type = TableWidthUnitValues.Dxa });
        if (span > 1) tcPr.AppendChild(new GridSpan { Val = span });
        if (merge is { } m) tcPr.AppendChild(m == MergedCellValues.Continue ? new VerticalMerge() : new VerticalMerge { Val = m });
        if (!string.IsNullOrEmpty(cell.Bg))
            tcPr.AppendChild(new Shading { Val = ShadingPatternValues.Clear, Color = "auto", Fill = cell.Bg.TrimStart('#').ToUpperInvariant() });
        var numeric = !empty && HtmlToQuestPdf.IsNumeric(cell.Html);
        if (numeric) tcPr.AppendChild(new NoWrap());   // الرقم لا ينكسر على سطرين (قرار المالك)
        tcPr.AppendChild(new TableCellVerticalAlignment
        {
            Val = cell.VAlign switch
            {
                "top" => TableVerticalAlignmentValues.Top,
                "bottom" => TableVerticalAlignmentValues.Bottom,
                _ => TableVerticalAlignmentValues.Center,
            },
        });

        var tc = new TableCell(tcPr);
        if (empty) tc.AppendChild(new Paragraph());
        else foreach (var block in WordHtml.Blocks(cell.Html, null, inCell: true)) tc.AppendChild(block);
        return tc;
    }

    private static TableBorders Borders(PrintTable t)
    {
        var none = t.BorderPt <= 0;
        var size = (UInt32Value)(uint)Math.Clamp(Math.Round(t.BorderPt * 8), 2, 96);   // ثُمن النقطة
        var color = t.BorderColor.TrimStart('#').ToUpperInvariant();
        T B<T>() where T : BorderType, new() => new()
        {
            Val = none ? BorderValues.Nil : BorderValues.Single,
            Size = none ? 0u : size, Color = color, Space = 0,
        };
        return new TableBorders(B<TopBorder>(), B<LeftBorder>(), B<BottomBorder>(), B<RightBorder>(),
            B<InsideHorizontalBorder>(), B<InsideVerticalBorder>());
    }
}
