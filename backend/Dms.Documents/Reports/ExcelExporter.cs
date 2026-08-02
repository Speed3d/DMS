using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;

namespace Dms.Documents.Reports;

/// <summary>تمييز بصري لصفّ في الجدول — يُترجَم إلى تعبئة لونية.</summary>
public enum ExcelRowStyle
{
    Normal = 0,
    Highlight = 1,   // أزرق فاتح — موظف جديد
    Warning = 2,     // أحمر فاتح — منتهي الخدمة
    Note = 3,        // أصفر فاتح — مدفوع من شركة أخرى
    Total = 4,       // رمادي عريض — سطر الإجمالي
}

/// <summary>صفّ مع تمييزه.</summary>
public sealed record ExcelRow(IReadOnlyList<string> Cells, ExcelRowStyle Style = ExcelRowStyle.Normal);

/// <summary>مُصدِّر Excel (.xlsx) عبر OpenXML — يدعم العربية عبر InlineString.</summary>
public static class ExcelExporter
{
    // فهارس التنسيقات داخل الـStylesheet أدناه — يجب أن تطابق ترتيب CellFormats.
    private const uint StylePlain = 0, StyleHeader = 1;
    private const uint StyleHighlight = 2, StyleWarning = 3, StyleNote = 4, StyleTotal = 5;

    /// <summary>
    /// التصدير البسيط (بلا تنسيق) — **توقيعٌ قائم يستعمله <c>ReportService</c>، لا يُمسّ.</summary>
    public static byte[] Create(string sheetName, IReadOnlyList<string> headers, IEnumerable<IReadOnlyList<string>> rows) =>
        Create(sheetName, headers, rows.Select(r => new ExcelRow(r)), styled: false);

    /// <summary>تصدير منسّق: ترويسة عريضة وصفوف ملوّنة بحسب حالتها.</summary>
    public static byte[] CreateStyled(string sheetName, IReadOnlyList<string> headers, IEnumerable<ExcelRow> rows) =>
        Create(sheetName, headers, rows, styled: true);

    private static byte[] Create(
        string sheetName, IReadOnlyList<string> headers, IEnumerable<ExcelRow> rows, bool styled)
    {
        using var ms = new MemoryStream();
        using (var doc = SpreadsheetDocument.Create(ms, SpreadsheetDocumentType.Workbook))
        {
            var wbPart = doc.AddWorkbookPart();
            wbPart.Workbook = new Workbook();

            if (styled)
            {
                var stylesPart = wbPart.AddNewPart<WorkbookStylesPart>();
                stylesPart.Stylesheet = BuildStylesheet();
                stylesPart.Stylesheet.Save();
            }

            var wsPart = wbPart.AddNewPart<WorksheetPart>();
            var sheetData = new SheetData();
            wsPart.Worksheet = new Worksheet(sheetData);

            var sheets = wbPart.Workbook.AppendChild(new Sheets());
            sheets.Append(new Sheet
            {
                Id = wbPart.GetIdOfPart(wsPart),
                SheetId = 1,
                Name = sheetName.Length > 31 ? sheetName[..31] : sheetName,
            });

            // ⚠️ بلا تنسيق ⇒ **بلا StyleIndex إطلاقاً**: الإشارة إلى تنسيق (ولو الفهرس 0) في
            //    مصنّف بلا `WorkbookStylesPart` تُنتج ملفاً غير صالح يرفض Excel فتحه.
            sheetData.Append(MakeRow(headers, styled ? StyleHeader : null));
            foreach (var r in rows)
                sheetData.Append(MakeRow(r.Cells, styled ? StyleOf(r.Style) : null));

            wbPart.Workbook.Save();
        }
        return ms.ToArray();
    }

    private static uint StyleOf(ExcelRowStyle s) => s switch
    {
        ExcelRowStyle.Highlight => StyleHighlight,
        ExcelRowStyle.Warning => StyleWarning,
        ExcelRowStyle.Note => StyleNote,
        ExcelRowStyle.Total => StyleTotal,
        _ => StylePlain,
    };

    private static Row MakeRow(IReadOnlyList<string> cells, uint? styleIndex)
    {
        var row = new Row();
        foreach (var c in cells)
        {
            var cell = new Cell
            {
                DataType = CellValues.InlineString,
                InlineString = new InlineString(new Text(c ?? string.Empty)),
            };
            if (styleIndex is { } s) cell.StyleIndex = s;
            row.Append(cell);
        }
        return row;
    }

    /// <summary>
    /// أصغر Stylesheet صالح: خطّان (عادي/عريض) وأربع تعبئات، ثم ستة CellFormats بترتيب الثوابت أعلاه.
    /// </summary>
    /// <remarks>
    /// ترتيب العناصر في OpenXML **مُلزِم** (Fonts ثم Fills ثم Borders ثم CellFormats)، وأول
    /// تعبئتين محجوزتان للنظام (<c>None</c> و<c>Gray125</c>) — فأي تعبئة حقيقية تبدأ من الفهرس 2.
    /// </remarks>
    private static Stylesheet BuildStylesheet()
    {
        // مؤهَّل بالكامل: `Fonts` يتعارض مع مساحة الأسماء `Dms.Documents.Fonts`.
        var fonts = new DocumentFormat.OpenXml.Spreadsheet.Fonts(
            new Font(new FontSize { Val = 11 }),                            // 0 عادي
            new Font(new Bold(), new FontSize { Val = 11 }));               // 1 عريض

        var fills = new Fills(
            new Fill(new PatternFill { PatternType = PatternValues.None }),      // 0 محجوز
            new Fill(new PatternFill { PatternType = PatternValues.Gray125 }),   // 1 محجوز
            Solid("FFD9E1F2"),   // 2 أزرق فاتح — جديد
            Solid("FFF8CBAD"),   // 3 أحمر فاتح — منتهي الخدمة
            Solid("FFFFF2CC"),   // 4 أصفر فاتح — مدفوع من الخارج
            Solid("FFD9D9D9"));  // 5 رمادي — ترويسة وإجمالي

        var borders = new Borders(new Border());

        var formats = new CellFormats(
            new CellFormat { FontId = 0, FillId = 0, BorderId = 0 },                              // 0 عادي
            new CellFormat { FontId = 1, FillId = 5, BorderId = 0, ApplyFill = true, ApplyFont = true }, // 1 ترويسة
            new CellFormat { FontId = 0, FillId = 2, BorderId = 0, ApplyFill = true },            // 2 جديد
            new CellFormat { FontId = 0, FillId = 3, BorderId = 0, ApplyFill = true },            // 3 منتهٍ
            new CellFormat { FontId = 0, FillId = 4, BorderId = 0, ApplyFill = true },            // 4 خارجي
            new CellFormat { FontId = 1, FillId = 5, BorderId = 0, ApplyFill = true, ApplyFont = true }); // 5 إجمالي

        return new Stylesheet(fonts, fills, borders, formats);
    }

    private static Fill Solid(string argb) =>
        new(new PatternFill(new ForegroundColor { Rgb = argb }) { PatternType = PatternValues.Solid });
}
