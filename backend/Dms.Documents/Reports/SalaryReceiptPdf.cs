using Dms.Documents.Fonts;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Reports;

/// <summary>إيصال استلام راتب واحد.</summary>
public sealed record SalaryReceiptModel(
    string CompanyName,
    string EmployeeName,
    string Position,
    string MonthName,
    int Year,
    string NetIqd,
    string? NetForeign,
    string IssueDate,
    bool English);

/// <summary>
/// إيصال استلام الراتب — عربي RTL أو إنجليزي LTR.
/// </summary>
/// <remarks>
/// ⚠️ **الاتجاه ليس تفصيلاً تجميلياً:** <see cref="FinancialReportPdf"/> يفرض
/// <c>DirectionFromRightToLeft()</c> على مستوى الصفحة، ونسخُ ذلك للإيصال الإنجليزي كان
/// سيُنتج مستنداً إنجليزياً مقلوباً يوقّعه عاملٌ لا يقرأ العربية.
///
/// ⚠️ **ولا يقول «راتباً كاملاً»:** الإيصال إقرارٌ موقَّع يُحتجّ به، والشهر قد يكون جزئياً أو
/// فيه خصومات — فيصف المبلغ والشهر ولا يصف ما ليس كذلك.
/// </remarks>
public static class SalaryReceiptPdf
{
    static SalaryReceiptPdf()
    {
        QuestPDF.Settings.License = LicenseType.Community;
        ArabicFonts.EnsureRegistered();
    }

    /// <summary>إيصال واحد.</summary>
    public static byte[] Generate(SalaryReceiptModel model) => Generate([model]);

    /// <summary>إيصالات متعدّدة في ملف واحد — **صفحة لكل موظف** ليُقصّ ويوقَّع منفرداً.</summary>
    public static byte[] Generate(IReadOnlyList<SalaryReceiptModel> models)
    {
        return Document.Create(doc =>
        {
            foreach (var m in models)
                doc.Page(page => Compose(page, m));
        }).GeneratePdf();
    }

    private static void Compose(PageDescriptor page, SalaryReceiptModel m)
    {
        page.Size(PageSizes.A5.Landscape());
        page.Margin(28);
        page.DefaultTextStyle(x =>
        {
            var s = x.FontFamily(ArabicFonts.Family).FontSize(11);
            return m.English ? s : s.DirectionFromRightToLeft();
        });

        var title = m.English ? "Salary Receipt" : "إيصال استلام راتب";
        var dateLabel = m.English ? "Date" : "التاريخ";

        page.Header().Column(col =>
        {
            col.Item().Row(row =>
            {
                row.RelativeItem().Text(m.CompanyName).SemiBold().FontSize(13);
                row.RelativeItem().AlignRight().Text($"{dateLabel}: {m.IssueDate}")
                    .FontColor(Colors.Grey.Darken1);
            });
            col.Item().PaddingTop(4).LineHorizontal(1).LineColor(Colors.Grey.Medium);
            col.Item().PaddingTop(10).AlignCenter().Text(title).SemiBold().FontSize(16);
            col.Item().PaddingBottom(10);
        });

        page.Content().Column(col =>
        {
            if (m.English) ComposeEnglish(col, m);
            else ComposeArabic(col, m);
        });

        page.Footer().Column(col =>
        {
            col.Item().PaddingTop(20).LineHorizontal(0.5f).LineColor(Colors.Grey.Lighten1);
            col.Item().PaddingTop(10).Row(row =>
            {
                row.RelativeItem().Text(m.English ? "Name: ______________________" : "الاسم: ______________________");
                row.RelativeItem().AlignRight()
                    .Text(m.English ? "Signature: ______________________" : "التوقيع: ______________________");
            });
            col.Item().PaddingTop(8)
                .Text(m.English ? "Date: ______________________" : "التاريخ: ______________________");
        });
    }

    private static void ComposeArabic(ColumnDescriptor col, SalaryReceiptModel m)
    {
        col.Item().PaddingBottom(8).Text("أقرّ أنا الموقّع أدناه:").FontSize(12);
        col.Item().Text(t => { t.Span("الاسم: ").SemiBold(); t.Span(m.EmployeeName); });
        col.Item().PaddingTop(3).Text(t => { t.Span("الصفة: ").SemiBold(); t.Span(m.Position); });

        col.Item().PaddingTop(14).Text(t =>
        {
            t.Span("باستلام مبلغ وقدره: ");
            t.Span($"{m.NetIqd} دينار عراقي").SemiBold().FontSize(13);
        });

        if (m.NetForeign is not null)
            col.Item().PaddingTop(3).Text($"({m.NetForeign})").FontColor(Colors.Grey.Darken2);

        col.Item().PaddingTop(10).Text(t =>
        {
            t.Span("وذلك راتب شهر: ");
            t.Span($"{m.MonthName} / {m.Year}").SemiBold();
        });
    }

    private static void ComposeEnglish(ColumnDescriptor col, SalaryReceiptModel m)
    {
        col.Item().PaddingBottom(8).Text("I, the undersigned:").FontSize(12);
        col.Item().Text(t => { t.Span("Name: ").SemiBold(); t.Span(m.EmployeeName); });
        col.Item().PaddingTop(3).Text(t => { t.Span("Position: ").SemiBold(); t.Span(m.Position); });

        col.Item().PaddingTop(14).Text("Hereby acknowledge receipt of the amount of:");
        col.Item().PaddingTop(3).Text($"{m.NetIqd} Iraqi Dinars").SemiBold().FontSize(13);

        if (m.NetForeign is not null)
            col.Item().PaddingTop(3).Text($"({m.NetForeign})").FontColor(Colors.Grey.Darken2);

        col.Item().PaddingTop(10).Text(t =>
        {
            t.Span("As salary for the month of: ");
            t.Span($"{m.MonthName} {m.Year}").SemiBold();
        });
    }
}
