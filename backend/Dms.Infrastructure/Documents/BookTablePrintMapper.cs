using Dms.Documents.Models;
using Dms.Domain;
using Dms.Domain.BookTables;

namespace Dms.Infrastructure.Documents;

/// <summary>
/// جسرُ الطبقتين (ADR-057): جدولُ القواعد (<c>Dms.Domain</c>) ⟵ جدولٌ جاهزٌ للرسم (<c>Dms.Documents</c>).
/// </summary>
/// <remarks>
/// 🔑 **ثلاث خطواتٍ بترتيبها عند كل طباعة**: الفحص (<see cref="BookTableRules.ValidateBody"/>) — فلا يُرسم ما لم يُفحص ولو
/// خُزِّن قبل وجود القواعد · ثم **إعادة حساب Σ والحروف** (<see cref="TableFormulas.Evaluate"/>) — فالخادم لا يطبع رقماً
/// أرسله العميل · ثم النقل إلى نموذج الطباعة بالخلايا الحقيقية وحدها.
/// </remarks>
public static class BookTablePrintMapper
{
    public static IReadOnlyList<PrintTable> Map(string? bodyHtml) =>
        BookTableRules.ValidateBody(bodyHtml).Select(ToPrint).ToList();

    public static PrintTable ToPrint(BookTable t)
    {
        var computed = TableFormulas.Evaluate(t);
        var cells = new List<PrintCell>();
        for (var r = 0; r < t.Rows.Count; r++)
            for (var c = 0; c < t.Rows[r].Cells.Count; c++)
                if (t.Rows[r].Cells[c] is { } cell)
                {
                    var html = computed.TryGetValue(cell.Id, out var v) ? TableFormulas.WithText(cell.Html, v.Text) : cell.Html;
                    cells.Add(new PrintCell(r, c, cell.RowSpan, cell.ColSpan, cell.Bg, cell.VAlign, html));
                }

        return new PrintTable
        {
            Rtl = t.Dir != "ltr",
            WidthPct = t.WidthPct,
            Align = t.Align,
            BorderPt = (float)t.Border.WidthPt,
            BorderColor = t.Border.Color,
            HeaderRows = t.HeaderRows,
            RepeatHeader = t.RepeatHeader,
            ColumnWeights = t.Cols.Select(c => (float)c.Weight).ToList(),
            RowCount = t.Rows.Count,
            Cells = cells,
        };
    }

    public static PrintSignatureMode Mode(SignaturePlacement p) => p switch
    {
        SignaturePlacement.StampEveryPage => PrintSignatureMode.StampEveryPage,
        SignaturePlacement.EveryPage => PrintSignatureMode.EveryPage,
        _ => PrintSignatureMode.LastPage,
    };
}
