using Dms.Documents.Fonts;
using Dms.Documents.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Pdf;

/// <summary>الصور الجاهزة للقالب (تأتي من الشركة في الإنتاج، ومن المولّد البديل في الاختبار).</summary>
public sealed record DocumentAssets(byte[] Header, byte[] Footer, byte[] Watermark, byte[] QrPng);

/// <summary>
/// مولّد PDF بـ QuestPDF (أصلي، بلا متصفح) — يثبت:
///  - صفحة A4 + صورة هيدر/فوتر.
///  - علامة مائية بشفافية خلف النص (طبقة Layer).
///  - متن عربي RTL حقيقي (قابل للبحث/التحديد) بخط Amiri مع تشكيل صحيح (HarfBuzz).
///  - عرض الحقول (الرقم/التاريخ/الجهة/الموضوع/النص + المالية) + صورة QR.
/// </summary>
public sealed class PdfGenerator
{
    static PdfGenerator()
    {
        QuestPDF.Settings.License = LicenseType.Community;
        ArabicFonts.EnsureRegistered();
    }

    public byte[] Generate(BookDocument book, DocumentAssets assets)
        => BuildDocument(book, assets).GeneratePdf();

    /// <summary>معاينة الصفحات كصور PNG (للفحص البصري/الاختبار) — نفس محرّك العرض.</summary>
    public IEnumerable<byte[]> GeneratePreviewImages(BookDocument book, DocumentAssets assets)
        => BuildDocument(book, assets).GenerateImages();

    private static IDocument BuildDocument(BookDocument book, DocumentAssets assets)
    {
        return Document.Create(doc =>
        {
            doc.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(0);
                page.DefaultTextStyle(x => x
                    .FontFamily(ArabicFonts.Family)
                    .FontSize(13)
                    .DirectionFromRightToLeft());

                // الهيدر: ارتفاع مقيّد + FitArea ليعمل مع أي نسبة أبعاد للصورة
                page.Header().Height(140).AlignCenter().AlignMiddle()
                    .Image(assets.Header).FitArea();

                // المتن: علامة مائية خلف المحتوى + الحقول
                page.Content()
                    .PaddingHorizontal(40)
                    .PaddingVertical(24)
                    .ContentFromRightToLeft()
                    .Layers(layers =>
                    {
                        // العلامة المائية (الشفافية مدمجة في PNG) — حجم مقيّد + FitArea
                        layers.Layer()
                            .AlignCenter().AlignMiddle()
                            .Width(300).Height(300)
                            .Image(assets.Watermark).FitArea();

                        layers.PrimaryLayer().Column(col =>
                        {
                            col.Spacing(10);

                            // سطر الرقم والتاريخ
                            col.Item().Row(row =>
                            {
                                row.RelativeItem().Text(t =>
                                {
                                    t.Span("العدد: ").SemiBold();
                                    t.Span(book.Number);
                                });
                                row.RelativeItem().AlignLeft().Text(t =>
                                {
                                    t.Span("التاريخ: ").SemiBold();
                                    t.Span(book.Date.ToString("yyyy-MM-dd"));
                                });
                            });

                            col.Item().Text(t =>
                            {
                                t.Span("الجهة: ").SemiBold();
                                t.Span(book.Entity);
                            });

                            col.Item().Text(t =>
                            {
                                t.Span("الموضوع / ").SemiBold();
                                t.Span(book.Subject).SemiBold();
                            });

                            col.Item().PaddingTop(6).Text(book.Body)
                                .Justify().LineHeight(1.6f);

                            if (book.HasFinancials)
                                col.Item().PaddingTop(10).Element(c => FinancialBox(c, book));

                            // QR + تعليمة التحقق
                            col.Item().PaddingTop(20).AlignCenter().Column(qr =>
                            {
                                qr.Item().AlignCenter().Width(110).Image(assets.QrPng).FitWidth();
                                qr.Item().AlignCenter().Text("امسح الرمز للتحقق من صحة الكتاب")
                                    .FontSize(9).FontColor(Colors.Grey.Darken1);
                            });
                        });
                    });

                // الفوتر: ارتفاع مقيّد + FitArea
                page.Footer().Height(80).AlignCenter().AlignMiddle()
                    .Image(assets.Footer).FitArea();
            });
        });
    }

    private static void FinancialBox(IContainer container, BookDocument book)
    {
        container
            .Border(1).BorderColor(Colors.Grey.Lighten1)
            .Background(Colors.Grey.Lighten4)
            .Padding(10)
            .Column(col =>
            {
                col.Spacing(4);
                col.Item().Text("التفاصيل المالية").SemiBold();
                col.Item().Text($"المبلغ: {book.Amount:#,0} {CurrencyLabel(book.Currency)}");
                if (string.Equals(book.Currency, "USD", StringComparison.OrdinalIgnoreCase))
                    col.Item().Text($"سعر الصرف: {book.ExchangeRate:#,0}");
                col.Item().Text($"المعادل بالدينار العراقي: {book.AmountInIqd:#,0} د.ع").SemiBold();
            });
    }

    private static string CurrencyLabel(string? currency) =>
        string.Equals(currency, "USD", StringComparison.OrdinalIgnoreCase) ? "دولار" : "دينار";
}
