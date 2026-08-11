using Dms.Documents.Fonts;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Reports;

/// <summary>عمود في تقرير جدوليّ: عنوانه ووزنه النسبيّ في العرض.</summary>
/// <param name="Header">عنوان العمود بالعربية.</param>
/// <param name="Weight">وزنٌ نسبيّ (1 = ضيّق، 4 = عريض).</param>
public sealed record TableReportColumn(string Header, float Weight = 2f);

/// <summary>نموذج تقرير جدوليّ عام — عنوانٌ وفترة وأعمدة وصفوف وسطور ملخّص.</summary>
/// <param name="Summary">
/// سطور تُطبع في التذييل («عدد السجلات: 128» · «الإجمالي: 3,930,000 د.ع»). قد تكون فارغة.
/// </param>
public sealed record TableReportModel(
    string Title,
    string CompanyName,
    string Period,
    IReadOnlyList<TableReportColumn> Columns,
    IReadOnlyList<IReadOnlyList<string>> Rows,
    IReadOnlyList<string> Summary);

/// <summary>
/// تقرير جدوليّ عربيّ عام (QuestPDF) — يخدم تقرير النشاط والتقارير التفصيلية بأعمدةٍ متغيّرة.
/// </summary>
/// <remarks>
/// 🔴 **لماذا مولّدٌ واحد لا ثلاثة؟** لأن <c>FinancialReportPdf</c> كان النسخة الأولى بأعمدةٍ
/// **مثبَّتة في الكود**، ونسخُه لكل تقريرٍ جديد يعني ثلاثة أماكن تُصلَح فيها العربية والاتجاه
/// والترقيم — وهو بالضبط نمط «القاعدة المنسوخة» الذي عالجته ADR-030 في قاعدة الرؤية.
/// (وبقي <c>FinancialReportPdf</c> كما هو: تقريرٌ يعمل ومُثبَتٌ حيّاً لا يُعاد كتابته بلا سبب.)
///
/// ⚠️ **الاتجاه يُضبط مرّتين عمداً**: <c>DirectionFromRightToLeft</c> للنصّ،
/// و<c>ContentFromRightToLeft</c> للمحتوى — ضبطُ أحدهما وحده يترك الجدول يبدأ من اليسار
/// (درس إيصال الرواتب، بلاغ المالك ٥).
///
/// ⚠️ **والصفحة أفقية (Landscape)**: تقارير التفصيل تحمل ٧ أعمدة فأكثر، والعموديّة تسحقها.
/// </remarks>
public static class TableReportPdf
{
    static TableReportPdf()
    {
        QuestPDF.Settings.License = LicenseType.Community;
        ArabicFonts.EnsureRegistered();
    }

    public static byte[] Generate(TableReportModel m)
    {
        return Document.Create(doc =>
        {
            doc.Page(page =>
            {
                page.Size(PageSizes.A4.Landscape());
                page.Margin(24);
                page.DefaultTextStyle(x => x.FontFamily(ArabicFonts.Family).FontSize(9).DirectionFromRightToLeft());

                page.Header().Column(col =>
                {
                    col.Item().AlignCenter().Text(m.Title).FontSize(16).SemiBold();
                    col.Item().AlignCenter().Text(m.CompanyName).FontSize(11);
                    col.Item().AlignCenter().Text(m.Period).FontSize(9).FontColor(Colors.Grey.Darken1);
                    col.Item().PaddingBottom(6);
                });

                page.Content().ContentFromRightToLeft().Table(table =>
                {
                    table.ColumnsDefinition(c =>
                    {
                        c.ConstantColumn(26);                       // م
                        foreach (var col in m.Columns) c.RelativeColumn(col.Weight);
                    });

                    // الترويسة تتكرّر في كل صفحة — تقرير النشاط قد يبلغ مئات السطور.
                    table.Header(h =>
                    {
                        void HeadCell(string t) => h.Cell().Background(Colors.Grey.Lighten2)
                            .Border(0.5f).Padding(4).Text(t).SemiBold();
                        HeadCell("م");
                        foreach (var col in m.Columns) HeadCell(col.Header);
                    });

                    var i = 1;
                    foreach (var row in m.Rows)
                    {
                        void Cell(string t) => table.Cell().Border(0.5f)
                            .BorderColor(Colors.Grey.Lighten1).Padding(3).Text(t);
                        Cell(i.ToString());

                        // 🔴 صفٌّ أقصر من الأعمدة يُملأ فراغاً بدل أن يزيح الجدول كلَّه:
                        //    خليّةٌ ناقصة في QuestPDF تُزحزح ما بعدها فينكسر المحاذاة صامتاً.
                        for (var c = 0; c < m.Columns.Count; c++)
                            Cell(c < row.Count ? row[c] ?? "" : "");
                        i++;
                    }
                });

                page.Footer().PaddingTop(8).Column(col =>
                {
                    col.Item().LineHorizontal(1).LineColor(Colors.Grey.Medium);
                    if (m.Summary.Count > 0)
                    {
                        col.Item().PaddingTop(4).Row(row =>
                        {
                            foreach (var s in m.Summary)
                                row.RelativeItem().Text(s).SemiBold().FontSize(10);
                        });
                    }
                    col.Item().PaddingTop(2).AlignLeft()
                        .Text(t => t.CurrentPageNumber().FontSize(8).FontColor(Colors.Grey.Darken1));
                });
            });
        }).GeneratePdf();
    }
}
