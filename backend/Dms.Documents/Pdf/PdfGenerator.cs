using Dms.Documents.Fonts;
using Dms.Documents.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Pdf;

/// <summary>الصور الجاهزة للقالب (تأتي من الشركة في الإنتاج، ومن المولّد البديل في الاختبار).</summary>
public sealed record DocumentAssets(byte[] Header, byte[] Footer, byte[] Watermark, byte[]? QrPng);

/// <summary>الـPDF ومعه صفحةُ نهاية المتن وعددُ الصفحات وهل حُجزت مساحة التوقيع في كل صفحة.</summary>
public sealed record PdfRenderResult(byte[] Pdf, int BodyEndPage, int TotalPages, bool ReservedEveryPage);

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

    public byte[] Generate(BookDocument book, DocumentAssets assets) => Render(book, assets).Pdf;

    /// <summary>
    /// يرسم الكتاب ويُعيد معه ما يلزم للتحقّق من التخطيط. 🔴 **في «الأخيرة وحدها» لا تبقى صفحةٌ أخيرة فيها التوقيع
    /// وحده** (بلاغ المالك 2026-10-05): تفريغُ مساحة التوقيع من الصفحات يجعل كتلتَه المحجوزة تنتقل وحدها إلى صفحةٍ جديدة
    /// إن انتهى المتن في أسفل الصفحة — وقاسها المسحُ في ثلث الحالات (33 من 112). فإن وقع ذلك يُعاد الرسم **بالحجز في
    /// كل صفحة**: آخرُ صفحةٍ من المتن تبقى فيها مساحةُ التوقيع دائماً، والتوقيع والختم يبقيان في الأخيرة وحدها.
    /// </summary>
    public PdfRenderResult Render(BookDocument book, DocumentAssets assets)
    {
        var reserve = PrintPageRules.ReserveEveryPage(book.SignatureMode);
        var probe = new LayoutProbe();
        var pdf = BuildDocument(book, assets, reserve, probe).GeneratePdf();
        if (!reserve && PrintPageRules.SignatureAlone(probe.BodyEndPage, probe.TotalPages))
        {
            reserve = true;
            probe = new LayoutProbe();
            pdf = BuildDocument(book, assets, reserve, probe).GeneratePdf();
        }
        return new PdfRenderResult(pdf, probe.BodyEndPage, probe.TotalPages, reserve);
    }

    /// <summary>معاينة الصفحات كصور PNG (للفحص البصري/الاختبار) — نفس محرّك العرض وقرار الحجز نفسه.</summary>
    public IEnumerable<byte[]> GeneratePreviewImages(BookDocument book, DocumentAssets assets)
        => BuildDocument(book, assets, Render(book, assets).ReservedEveryPage, new LayoutProbe()).GenerateImages();

    /// <summary>يسجّل أثناء الرسم صفحةَ نهاية المتن وعددَ الصفحات (آخرُ مرورٍ للتخطيط هو الذي يبقى).</summary>
    private sealed class LayoutProbe
    {
        public int BodyEndPage;
        public int TotalPages;
    }

    private static IDocument BuildDocument(BookDocument book, DocumentAssets assets, bool reserveEveryPage, LayoutProbe probe)
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
                // المساحة المحجوزة للتوقيع والختم: في كل صفحة ما دام شيءٌ منهما يُطبع في كل صفحة (ADR-057)،
                // وفي «الأخيرة وحدها» تُفرَّغ من الصفحات الأخرى فيمتدّ فيها المتن — وتُحجز في آخره فقط (أدناه)،
                // إلا إن انتقل الحجز وحده إلى صفحةٍ فارغة فيُعاد الرسم بالحجز في كل صفحة (`Render`).
                page.Content()
                    .PaddingHorizontal(40)
                    .PaddingTop(5)
                    .PaddingBottom(reserveEveryPage ? PrintPageRules.SignatureZonePt : 0)
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
                            if (book.PrintEntity || book.PrintSubject)
                                col.Item().PaddingTop(10).AlignCenter().Column(c =>
                                {
                                    c.Spacing(5);
                                    if (book.PrintEntity)
                                        c.Item().AlignCenter().Text(book.Entity).SemiBold().FontSize(15);
                                    if (book.PrintSubject)
                                        c.Item().AlignCenter().Text($"الموضوع / {book.Subject}").SemiBold().FontSize(14);
                                });

                            // المتن الرئيسي للكتاب (نستخدم المترجم الجديد للـ HTML لدعم التنسيقات والمحاذاة)
                            col.Item().PaddingTop(15)
                                .DefaultTextStyle(x => x.FontFamily(HtmlToQuestPdf.BodyFontFamily).FontSize(HtmlToQuestPdf.BaseFontSize))
                                .Column(bodyCol =>
                                {
                                    bodyCol.RenderHtml(book.Body, book.Tables);
                                    // علامةٌ بلا ارتفاع في آخر المتن: تسجّل الصفحة التي انتهى فيها (لا تُغيّر التخطيط).
                                    bodyCol.Item().Height(0).ShowIf(ctx => { probe.BodyEndPage = ctx.PageNumber; return true; });
                                });

                            // «الأخيرة وحدها»: كتلةٌ فارغة بارتفاع المساحة المحجوزة **لا تنقسم** — إن لم يتّسع لها آخر الصفحة
                            // انتقلت إلى صفحةٍ جديدة، فيجد التوقيع والختم مكانهما دائماً ولا يعلوان نصّاً.
                            if (!reserveEveryPage)
                                col.Item().ShowEntire().Height(PrintPageRules.SignatureZonePt);

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
                            row.RelativeItem().PaddingLeft(50).AlignLeft().AlignBottom()
                                .ShowIf(ctx => PrintPageRules.ShowSignature(book.SignatureMode, ctx.PageNumber, ctx.TotalPages))
                                .ContentFromRightToLeft().Column(sig =>
                            {
                                if (!string.IsNullOrWhiteSpace(book.SignatoryName))
                                {
                                    sig.Item().AlignCenter().Text(book.SignatoryName).SemiBold().FontSize(15);
                                    if (!string.IsNullOrWhiteSpace(book.SignatoryTitle))
                                        sig.Item().AlignCenter().Text(book.SignatoryTitle).FontSize(13).FontColor(Colors.Grey.Darken2);
                                }
                            });

                            // اليمين الفيزيائي: الباركود (يُخفى في المعاينة)
                            if (assets.QrPng != null)
                            {
                                row.AutoItem().AlignRight().AlignBottom().Width(70)
                                    .ShowIf(ctx => PrintPageRules.ShowStamp(book.SignatureMode, ctx.PageNumber, ctx.TotalPages))
                                    .Column(qr =>
                                {
                                    qr.Item().AlignCenter().Image(assets.QrPng).FitWidth();
                                    qr.Item().AlignCenter().Text("امسح الرمز للتحقق").FontSize(8).FontColor(Colors.Grey.Darken3);
                                });
                            }
                            else
                            {
                                row.AutoItem().AlignRight().AlignBottom().Width(70).Height(70)
                                    .ShowIf(ctx => PrintPageRules.ShowStamp(book.SignatureMode, ctx.PageNumber, ctx.TotalPages))
                                    .AlignCenter().AlignMiddle()
                                    .Border(1).BorderColor(Colors.Grey.Medium)
                                    .Background(Colors.Grey.Lighten4)
                                    .Padding(5)
                                    .Text("نسخة\nللمعاينة").FontSize(10).FontColor(Colors.Grey.Darken3).AlignCenter();
                            }
                        });

                    // عدّاد الصفحات للتحقّق (لا يرسم شيئاً)
                    layers.Layer().ShowIf(ctx =>
                    {
                        if (ctx.TotalPages is int total) probe.TotalPages = total;
                        return false;
                    });

                    // ترقيم الصفحات (ADR-057): «صفحة 1 من 5» يبدأ من الأولى، بخيارٍ لكل كتاب — ولا ترقيم في الكتاب
                    // ذي الصفحة الواحدة (قرار المالك). كان «- 2 -» يتخطّى الأولى دائماً.
                    // وموضعه من القالب (بلاغ المالك 2026-10-05): يمين · وسط · يسار بهامش المتن، وإزاحةٌ بالمليمتر — الوسط بلا
                    // إزاحةٍ هو السلوك السابق نفسه.
                    var number = layers.Layer()
                        .ShowIf(ctx => PrintPageRules.ShowPageNumber(book.PageNumbers, ctx.TotalPages))
                        .AlignBottom()
                        .PaddingBottom(20)
                        .ContentFromLeftToRight()
                        .PaddingHorizontal(book.PageNumberAlign == "center" ? 0 : 40)
                        .OffsetX(book.PageNumberOffsetXPt)
                        .OffsetY(-book.PageNumberOffsetYPt);
                    number = book.PageNumberAlign switch
                    {
                        "right" => number.AlignRight(),
                        "left" => number.AlignLeft(),
                        _ => number.AlignCenter(),
                    };
                    number.ContentFromRightToLeft()
                        .Text(text =>
                        {
                            text.Span("صفحة ").FontSize(12);
                            text.CurrentPageNumber().FontSize(12);
                            text.Span(" من ").FontSize(12);
                            text.TotalPages().FontSize(12);
                        });
                });
            });
        });
    }
}
