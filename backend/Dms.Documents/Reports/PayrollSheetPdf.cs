using Dms.Documents.Fonts;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Reports;

/// <summary>سطر في كشف الرواتب المطبوع (كل القيم منسّقة نصّاً مسبقاً).</summary>
public sealed record PayrollSheetLine(
    string Name, string Position, string Currency, string BaseSalary,
    string Bonus, string Deduction, string AbsenceDays, string AbsenceDeduction,
    string Net, string NetIqd, string PaymentStatus, string? Notes,
    bool IsNewHire, bool IsTerminated);

/// <param name="TotalIqd">**ما تدفعه الشركة فعلاً** — بعد استثناء ما صرفته شركةٌ أخرى (ADR-028).</param>
/// <param name="ExcludedIqd">
/// المستثنى، أو <c>null</c> إن لم يكن ثمّة استثناء.
/// ⚠️ **يُطبع ولا يُسقَط صامتاً**: كشفٌ إجماليُّه أقلّ من مجموع أعمدته بلا تفسير يبدو خطأ حساب.
/// </param>
public sealed record PayrollSheetModel(
    string CompanyName, string MonthName, int Year, string Status,
    string WorkingDays, string? ExchangeRate,
    IReadOnlyList<PayrollSheetLine> Lines, string TotalIqd, string? ExcludedIqd = null);

/// <summary>كشف الرواتب الشهري للطباعة — عربي RTL على نمط <see cref="FinancialReportPdf"/>.</summary>
public static class PayrollSheetPdf
{
    static PayrollSheetPdf()
    {
        QuestPDF.Settings.License = LicenseType.Community;
        ArabicFonts.EnsureRegistered();
    }

    public static byte[] Generate(PayrollSheetModel m)
    {
        return Document.Create(doc =>
        {
            doc.Page(page =>
            {
                page.Size(PageSizes.A4.Landscape());
                page.Margin(22);
                page.DefaultTextStyle(x => x.FontFamily(ArabicFonts.Family).FontSize(8.5f)
                    .DirectionFromRightToLeft());

                page.Header().Column(col =>
                {
                    col.Item().AlignCenter().Text("كشف الرواتب").FontSize(16).SemiBold();
                    col.Item().AlignCenter().Text(m.CompanyName).FontSize(11);
                    col.Item().AlignCenter().Text($"{m.MonthName} / {m.Year} — {m.Status}")
                        .FontSize(9.5f).FontColor(Colors.Grey.Darken1);

                    col.Item().PaddingTop(4).AlignCenter().Text(t =>
                    {
                        t.DefaultTextStyle(s => s.FontSize(8.5f).FontColor(Colors.Grey.Darken1));
                        t.Span($"أيام العمل: {m.WorkingDays}");
                        if (m.ExchangeRate is not null) t.Span($"   ·   سعر الصرف: {m.ExchangeRate}");
                    });
                    col.Item().PaddingBottom(8);
                });

                page.Content().ContentFromRightToLeft().Table(table =>
                {
                    table.ColumnsDefinition(c =>
                    {
                        c.ConstantColumn(22);  // م
                        c.RelativeColumn(3);   // الاسم
                        c.RelativeColumn(2);   // الصفة
                        c.ConstantColumn(38);  // العملة
                        c.RelativeColumn(2);   // الأساسي
                        c.RelativeColumn(2);   // مكافأة
                        c.RelativeColumn(2);   // خصم
                        c.ConstantColumn(34);  // غياب
                        c.RelativeColumn(2);   // خصم الغياب
                        c.RelativeColumn(2);   // الصافي
                        c.RelativeColumn(2);   // بالدينار
                        c.RelativeColumn(2);   // حالة الدفع
                    });

                    table.Header(h =>
                    {
                        void Head(string t) => h.Cell().Background(Colors.Grey.Lighten2)
                            .Border(0.5f).Padding(4).Text(t).SemiBold().FontSize(8);
                        Head("م"); Head("الاسم"); Head("الصفة"); Head("العملة");
                        Head("الأساسي"); Head("مكافأة"); Head("خصم"); Head("غياب");
                        Head("خصم الغياب"); Head("الصافي"); Head("بالدينار"); Head("الحالة");
                    });

                    var i = 1;
                    foreach (var line in m.Lines)
                    {
                        // ألوان الحالات الخاصة — نفس دلالات الشاشة، فلا يتعلّم المستخدم ترميزين.
                        var bg = line switch
                        {
                            { IsTerminated: true } => Colors.Red.Lighten4,
                            { IsNewHire: true } => Colors.Blue.Lighten5,
                            _ => Colors.White,
                        };

                        void Cell(string t) => table.Cell().Background(bg)
                            .Border(0.5f).BorderColor(Colors.Grey.Lighten1).Padding(3).Text(t).FontSize(8);

                        Cell(i.ToString());
                        Cell(line.Name);
                        Cell(line.Position);
                        Cell(line.Currency);
                        Cell(line.BaseSalary);
                        Cell(line.Bonus);
                        Cell(line.Deduction);
                        Cell(line.AbsenceDays);
                        Cell(line.AbsenceDeduction);
                        Cell(line.Net);
                        Cell(line.NetIqd);
                        Cell(line.PaymentStatus);
                        i++;
                    }
                });

                page.Footer().PaddingTop(8).Column(col =>
                {
                    col.Item().LineHorizontal(1).LineColor(Colors.Grey.Medium);

                    // ⚠️ **المستثنى قبل الإجمالي لا بعده** (ADR-028): يقرأ المحاسب سببَ نقصان
                    //    الرقم قبل أن يرى الرقم، فلا يظنّه خطأ حساب.
                    if (m.ExcludedIqd is { } excluded)
                    {
                        col.Item().PaddingTop(4).AlignLeft()
                            .Text($"مستثنى (مدفوع من شركة أخرى): {excluded} د.ع")
                            .FontSize(9.5f).FontColor(Colors.Grey.Darken2);
                    }

                    col.Item().PaddingTop(5).Row(row =>
                    {
                        row.RelativeItem().Text($"عدد الموظفين: {m.Lines.Count}").SemiBold();
                        row.RelativeItem().AlignLeft()
                            .Text($"الإجمالي المستحقّ بالدينار العراقي: {m.TotalIqd} د.ع")
                            .SemiBold().FontSize(11);
                    });
                });
            });
        }).GeneratePdf();
    }
}
