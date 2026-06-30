using Dms.Documents.Fonts;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Reports;

public sealed record FinancialReportLine(
    string Source, string Number, string Date, string Entity, string Amount, string AmountInIqd);

public sealed record FinancialReportModel(
    string CompanyName, string Period, IReadOnlyList<FinancialReportLine> Lines, string TotalIqd, int Count);

/// <summary>تقرير مالي بالعربية (QuestPDF) — جدول الكتب + المجموع بالدينار العراقي.</summary>
public static class FinancialReportPdf
{
    static FinancialReportPdf()
    {
        QuestPDF.Settings.License = LicenseType.Community;
        ArabicFonts.EnsureRegistered();
    }

    public static byte[] Generate(FinancialReportModel m)
    {
        return Document.Create(doc =>
        {
            doc.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(30);
                page.DefaultTextStyle(x => x.FontFamily(ArabicFonts.Family).FontSize(10).DirectionFromRightToLeft());

                page.Header().Column(col =>
                {
                    col.Item().AlignCenter().Text("التقرير المالي").FontSize(18).SemiBold();
                    col.Item().AlignCenter().Text(m.CompanyName).FontSize(12);
                    col.Item().AlignCenter().Text(m.Period).FontSize(10).FontColor(Colors.Grey.Darken1);
                    col.Item().PaddingBottom(8);
                });

                page.Content().ContentFromRightToLeft().Table(table =>
                {
                    table.ColumnsDefinition(c =>
                    {
                        c.ConstantColumn(28);   // م
                        c.RelativeColumn(2);    // المصدر/الرقم
                        c.RelativeColumn(2);    // التاريخ
                        c.RelativeColumn(4);    // الجهة
                        c.RelativeColumn(3);    // المبلغ
                        c.RelativeColumn(3);    // بالدينار
                    });

                    table.Header(h =>
                    {
                        void HeadCell(string t) => h.Cell().Background(Colors.Grey.Lighten2)
                            .Border(0.5f).Padding(5).Text(t).SemiBold();
                        HeadCell("م");
                        HeadCell("الرقم/المصدر");
                        HeadCell("التاريخ");
                        HeadCell("الجهة");
                        HeadCell("المبلغ");
                        HeadCell("بالدينار");
                    });

                    var i = 1;
                    foreach (var line in m.Lines)
                    {
                        void Cell(string t) => table.Cell().Border(0.5f).BorderColor(Colors.Grey.Lighten1).Padding(4).Text(t);
                        Cell(i.ToString());
                        Cell($"{line.Number}\n({line.Source})");
                        Cell(line.Date);
                        Cell(line.Entity);
                        Cell(line.Amount);
                        Cell(line.AmountInIqd);
                        i++;
                    }
                });

                page.Footer().PaddingTop(10).Column(col =>
                {
                    col.Item().LineHorizontal(1).LineColor(Colors.Grey.Medium);
                    col.Item().PaddingTop(6).Row(row =>
                    {
                        row.RelativeItem().Text($"عدد السجلات: {m.Count}").SemiBold();
                        row.RelativeItem().AlignLeft().Text($"الإجمالي بالدينار العراقي: {m.TotalIqd} د.ع").SemiBold().FontSize(12);
                    });
                });
            });
        }).GeneratePdf();
    }
}
