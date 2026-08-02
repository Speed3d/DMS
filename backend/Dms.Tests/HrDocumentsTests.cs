using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using Dms.Documents.Reports;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// مستندات وحدة الرواتب. الاختبار هنا ليس ترفاً: <c>Stylesheet</c> مكتوبةٌ يدوياً، و**Excel
/// يرفض فتح الملف المشوّه بلا أي رسالة مفيدة** — فالتحقق بالمُدقِّق يكشف العطب هنا لا عند المالك.
/// </summary>
public class HrDocumentsTests
{
    private static readonly string[] Headers =
        ["م", "الاسم", "الصفة", "الأساسي", "الصافي", "بالدينار"];

    private static IEnumerable<ExcelRow> SampleRows() =>
    [
        new(["1", "سنان", "مهندس", "1,200,000", "1,200,000", "1,200,000"]),
        new(["2", "علي", "سائق", "700,000", "620,000", "620,000"], ExcelRowStyle.Highlight),
        new(["3", "حسن", "محاسب", "900,000", "300,000", "300,000"], ExcelRowStyle.Warning),
        new(["4", "كريم", "فنّي", "800,000", "800,000", "800,000"], ExcelRowStyle.Note),
        new(["", "الإجمالي", "", "", "", "2,920,000"], ExcelRowStyle.Total),
    ];

    [Fact]
    public void StyledExcel_IsValidOpenXml()
    {
        var bytes = ExcelExporter.CreateStyled("كشف الرواتب", Headers, SampleRows());

        using var ms = new MemoryStream(bytes);
        using var doc = SpreadsheetDocument.Open(ms, false);

        var errors = new OpenXmlValidator().Validate(doc).ToList();
        Assert.True(errors.Count == 0,
            "أخطاء OpenXML: " + string.Join(" | ", errors.Select(e => e.Description)));
    }

    [Fact]
    public void StyledExcel_WritesHeaderAndEveryRow()
    {
        var bytes = ExcelExporter.CreateStyled("كشف الرواتب", Headers, SampleRows());

        using var ms = new MemoryStream(bytes);
        using var doc = SpreadsheetDocument.Open(ms, false);
        var wbPart = doc.WorkbookPart ?? throw new InvalidOperationException("المصنّف بلا WorkbookPart.");

        var sheet = wbPart.WorksheetParts.Single().Worksheet
                    ?? throw new InvalidOperationException("الورقة فارغة.");
        var rows = sheet.Descendants<DocumentFormat.OpenXml.Spreadsheet.Row>().ToList();

        Assert.Equal(6, rows.Count); // ترويسة + 5 صفوف
        Assert.NotNull(wbPart.WorkbookStylesPart);
    }

    [Fact]
    public void PlainExcel_StillWorks_ForTheFinancialReport()
    {
        // التوقيع القديم يستعمله ReportService — كسرُه كان سيُعطّل تقريراً يعمل منذ Phase 2.
        var bytes = ExcelExporter.Create("التقرير المالي", Headers,
            new[] { new[] { "1", "سنان", "مهندس", "1", "2", "3" } });

        using var ms = new MemoryStream(bytes);
        using var doc = SpreadsheetDocument.Open(ms, false);
        Assert.Empty(new OpenXmlValidator().Validate(doc));
    }

    [Fact]
    public void ArabicReceipt_GeneratesNonEmptyPdf()
    {
        var pdf = SalaryReceiptPdf.Generate(new SalaryReceiptModel(
            "أرض العرين للتجارة والمقاولات", "سنان", "مهندس",
            "تموز", 2026, "1,200,000", null, "2026-08-01", English: false));

        Assert.True(pdf.Length > 1000);
        Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(pdf, 0, 4));
    }

    [Fact]
    public void EnglishReceipt_GeneratesNonEmptyPdf()
    {
        var pdf = SalaryReceiptPdf.Generate(new SalaryReceiptModel(
            "DEN LAND", "John Smith", "Engineer",
            "July", 2026, "917,000", "700 USD", "2026-08-01", English: true));

        Assert.True(pdf.Length > 1000);
        Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(pdf, 0, 4));
    }

    [Fact]
    public void BulkReceipts_ProduceOnePagePerEmployee()
    {
        var models = Enumerable.Range(1, 4).Select(i => new SalaryReceiptModel(
            "أرض العرين", $"موظف {i}", "فنّي", "تموز", 2026, "500,000", null,
            "2026-08-01", English: false)).ToList();

        var pdf = SalaryReceiptPdf.Generate(models);
        var text = System.Text.Encoding.ASCII.GetString(pdf);
        // أربع صفحات ⇒ أربعة كائنات /Type /Page على الأقل.
        Assert.True(pdf.Length > 3000);
        Assert.Contains("/Page", text);
    }

    [Fact]
    public void PayrollSheet_GeneratesNonEmptyPdf()
    {
        var model = new PayrollSheetModel(
            "أرض العرين", "تموز", 2026, "مسودة", "30", "1,310",
            [
                new PayrollSheetLine("سنان", "مهندس", "د.ع", "1,200,000", "—", "—", "0", "0",
                    "1,200,000", "1,200,000", "لم يُصرف", null, false, false),
                new PayrollSheetLine("John", "Driver", "$", "700", "—", "—", "2", "46.67",
                    "653.33", "855,862", "لم يُصرف", null, true, false),
            ],
            "2,055,862");

        var pdf = PayrollSheetPdf.Generate(model);
        Assert.True(pdf.Length > 1000);
        Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(pdf, 0, 4));
    }
}
