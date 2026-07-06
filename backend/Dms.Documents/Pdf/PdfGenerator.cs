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
                    .PaddingTop(5)
                    .PaddingBottom(120) // نضع حداً كبيراً لمنع النص من النزول لمنطقة الباركود والتوقيع
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

                            // سطر يحتوي على مساحة فارغة يميناً، العبارة الاختيارية في المنتصف، والرقم/التاريخ يساراً
                            col.Item().Row(row =>
                            {
                                // اليمين: فارغ (أو يمكن وضع الشعار هنا لاحقاً)
                                row.RelativeItem(1);

                                // المنتصف: العبارة الاختيارية (تنزل للأسفل قليلاً)
                                row.RelativeItem(2).AlignCenter().AlignTop().Column(c =>
                                {
                                    if (!string.IsNullOrWhiteSpace(book.HeaderPhrase))
                                    {
                                        c.Item().PaddingTop(35).Text(book.HeaderPhrase).SemiBold().FontSize(15);
                                    }
                                });

                                // اليسار: الرقم والتاريخ (LTR ليقرأ من اليسار لليمين)
                                row.RelativeItem(1).ContentFromLeftToRight().Column(c =>
                                {
                                    c.Item().Text($"No: {book.Number}").SemiBold();
                                    c.Item().Text($"Date: {book.Date:yyyy-MM-dd}").SemiBold();
                                });
                            });

                            // الجهة والموضوع (في المنتصف، أسفل السطر السابق)
                            col.Item().PaddingTop(10).AlignCenter().Column(c =>
                            {
                                c.Spacing(5);
                                c.Item().AlignCenter().Text(book.Entity).SemiBold().FontSize(15);
                                c.Item().AlignCenter().Text($"الموضوع / {book.Subject}").SemiBold().FontSize(14);
                            });

                            // المتن الرئيسي للكتاب (نستخدم المترجم الجديد للـ HTML لدعم التنسيقات)
                            col.Item().PaddingTop(15).Text(text =>
                            {
                                text.DefaultTextStyle(x => x.LineHeight(1.6f));
                                text.Justify();
                                text.RenderHtml(book.Body);
                            });

                            // (تم إخفاء التفاصيل المالية من الطباعة بناءً على طلب المستخدم، لكنها تظل محفوظة في قاعدة البيانات)

                            // (تم نقل الباركود إلى الفوتر ليظهر على جميع الصفحات بمكان ثابت)
                        });
                    });

                // الفوتر: مساحته الأصلية للرسمة فقط
                page.Footer().Height(100).AlignCenter().AlignMiddle().Image(assets.Footer).FitArea();

                // طبقة أمامية لكل الصفحات: نثبت فيها الباركود يميناً والتوقيع يساراً ونرفعهما عن الفوتر مع أرقام الصفحات
                page.Foreground().Layers(layers =>
                {
                    layers.PrimaryLayer()
                        .PaddingBottom(120) // نرفعه عن الفوتر
                        .PaddingHorizontal(40) // محاذاة مع هوامش الصفحة
                        .AlignBottom()
                        .ContentFromLeftToRight() // لضمان التحكم الفيزيائي الصارم (LTR)
                        .Row(row =>
                        {
                            // اليسار الفيزيائي: التوقيع واسم المدير (نزحفه لليمين قليلاً بزيادة الـ PaddingLeft)
                            row.RelativeItem().PaddingLeft(50).AlignLeft().AlignBottom().ContentFromRightToLeft().Column(sig =>
                            {
                                if (!string.IsNullOrWhiteSpace(book.SignatoryName))
                                {
                                    sig.Item().AlignCenter().Text(book.SignatoryName).SemiBold().FontSize(15);
                                    if (!string.IsNullOrWhiteSpace(book.SignatoryTitle))
                                        sig.Item().AlignCenter().Text(book.SignatoryTitle).FontSize(13).FontColor(Colors.Grey.Darken2);
                                }
                            });

                            // اليمين الفيزيائي: الباركود
                            row.AutoItem().AlignRight().AlignBottom().Width(70).Column(qr =>
                            {
                                qr.Item().AlignCenter().Image(assets.QrPng).FitWidth();
                                qr.Item().AlignCenter().Text("امسح الرمز للتحقق").FontSize(8).FontColor(Colors.Grey.Darken3);
                            });
                        });

                    // ترقيم الصفحات: لا يظهر في الصفحة الأولى، ويظهر من الصفحة الثانية فصاعداً
                    layers.Layer()
                        .SkipOnce() // يتخطى الصفحة الأولى
                        .AlignBottom()
                        .AlignCenter()
                        .PaddingBottom(20)
                        .Text(text =>
                        {
                            text.Span("- ").FontSize(12);
                            text.CurrentPageNumber().FontSize(12);
                            text.Span(" -").FontSize(12);
                        });
                });
            });
        });
    }
}
