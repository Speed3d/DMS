using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Models;
using Dms.Documents.Pdf;

namespace Dms.Documents.Word;

/// <summary>
/// تصدير الكتاب إلى Word **طبق الأصل من الـPDF** (ADR-057، قرار المالك ت١٤) — ليعدّل عليه المالك في Word إن احتاج.
/// </summary>
/// <remarks>
/// 📐 **ما يُنقل**: صفحة A4 بهوامش الـPDF · صورة الترويسة والتذييل بعرض الصفحة · العلامة المائية خلف النصّ · الرقم والتاريخ
/// والعبارة · الجهة والموضوع بحسب خيارَي الطباعة · المتن بخطوطه وأحجامه وألوانه · **الجداول** · «صفحة X من Y» بحقلَي
/// <c>PAGE</c>/<c>NUMPAGES</c> (ولا ترقيم في الصفحة الواحدة) · التوقيع وصورة الختم بحسب النمط.
/// <para>
/// ⚠️ **حدودٌ مُعلَنة** — Word محرّكٌ آخر: تقسيم الصفحات قد يختلف قليلاً عن الـPDF، **والـPDF هو النسخة الرسمية**.
/// و«في الأخيرة وحدها» يعني في Word: بعد نهاية المتن (لا في تذييل الصفحة الأخيرة — Word لا يعرف تذييلاً للأخيرة وحدها)،
/// وما يُطبع في كل صفحة يوضع في التذييل. وسطور الرأس بـTimes New Roman (Amiri قد لا يكون مثبّتاً على الجهاز).
/// </para>
/// </remarks>
public sealed class WordExporter
{
    // أبعاد الصفحة والهوامش بالـtwips (نقطة = 20) — مطابقةٌ لـPdfGenerator
    private const int PageW = 11906, PageH = 16838;
    private const int SideMargin = 800;          // 40 نقطة
    private const int TopMargin = 2900;          // ترويسة 140 + 5
    private const int BottomMargin = 2000;       // تذييل 100

    private const string HeadFont = "Times New Roman";

    public byte[] Generate(BookDocument book, DocumentAssets? assets = null)
    {
        using var ms = new MemoryStream();
        using (var doc = WordprocessingDocument.Create(ms, WordprocessingDocumentType.Document))
        {
            var main = doc.AddMainDocumentPart();
            main.Document = new Document();
            var body = main.Document.AppendChild(new Body());

            var headerPart = main.AddNewPart<HeaderPart>();
            headerPart.Header = BuildHeader(headerPart, assets);
            var footerPart = main.AddNewPart<FooterPart>();
            footerPart.Footer = BuildFooter(footerPart, book, assets);

            // ١) سطر الرأس: الرقم والتاريخ يساراً · العبارة في الوسط (كالـPDF)
            body.AppendChild(TopRow(book));

            // ٢) الجهة والموضوع — بحسب خيارَي الطباعة (والقيمتان مسجّلتان في النظام دائماً)
            if (book.PrintEntity) body.AppendChild(Centered(book.Entity, 30, bold: true, before: 200));
            if (book.PrintSubject) body.AppendChild(Centered($"الموضوع / {book.Subject}", 28, bold: true, before: book.PrintEntity ? 100 : 200));
            body.AppendChild(Spacer(300));

            // ٣) المتن بجداوله
            var tables = book.Tables;
            foreach (var block in WordHtml.Blocks(book.Body, i => i < tables.Count ? WordTables.Build(tables[i]) : null, inCell: false))
                body.AppendChild(block);

            // ٤) التوقيع والختم بعد نهاية المتن — لما لا يُطبع في كل صفحة
            var sigAtEnd = book.SignatureMode != PrintSignatureMode.EveryPage;
            var stampAtEnd = book.SignatureMode == PrintSignatureMode.LastPage;
            if (sigAtEnd || stampAtEnd)
            {
                body.AppendChild(Spacer(400));
                body.AppendChild(SignatureRow(main, book, assets, sigAtEnd, stampAtEnd));
            }

            body.AppendChild(new SectionProperties(
                new HeaderReference { Type = HeaderFooterValues.Default, Id = main.GetIdOfPart(headerPart) },
                new FooterReference { Type = HeaderFooterValues.Default, Id = main.GetIdOfPart(footerPart) },
                new PageSize { Width = PageW, Height = PageH },
                new PageMargin
                {
                    Top = TopMargin, Bottom = BottomMargin, Left = (uint)SideMargin, Right = (uint)SideMargin,
                    Header = 0, Footer = 0, Gutter = 0,
                },
                new BiDi()));

            main.Document.Save();
        }
        return ms.ToArray();
    }

    // ─────────────────────────── الترويسة والتذييل ───────────────────────────

    private static Header BuildHeader(HeaderPart part, DocumentAssets? assets)
    {
        var p = FullBleed();
        if (assets is not null)
        {
            var (w, h) = WordImages.Fit(assets.Header, 595, 140);
            p.AppendChild(WordImages.Inline(part, assets.Header, w, h, "Header"));
            // العلامة المائية خلف النصّ في وسط كل صفحة — 300×300 نقطة كما في الـPDF، وشفافيتها في الصورة نفسها.
            var (ww, wh) = WordImages.Fit(assets.Watermark, 300, 300);
            p.AppendChild(WordImages.Behind(part, assets.Watermark, ww, wh, "Watermark"));
        }
        return new Header(p);
    }

    private static Footer BuildFooter(FooterPart part, BookDocument book, DocumentAssets? assets)
    {
        var footer = new Footer();
        // ما يُطبع في كل صفحة: الختم (نمطا «الختم في كل صفحة» و«الاثنان») والتوقيع («الاثنان»)
        var sigEvery = book.SignatureMode == PrintSignatureMode.EveryPage;
        var stampEvery = book.SignatureMode != PrintSignatureMode.LastPage;
        if (sigEvery || stampEvery) footer.AppendChild(SignatureRow(part, book, assets, sigEvery, stampEvery));

        if (book.PageNumbers) footer.AppendChild(PageNumber(book));

        var p = FullBleed();
        if (assets is not null)
        {
            var (w, h) = WordImages.Fit(assets.Footer, 595, 100);
            p.AppendChild(WordImages.Inline(part, assets.Footer, w, h, "Footer"));
        }
        footer.AppendChild(p);
        return footer;
    }

    /// <summary>فقرةٌ تمتدّ إلى حافتي الصفحة (هامشٌ سالب) — لصورتي الترويسة والتذييل بعرض الصفحة كما في الـPDF.</summary>
    private static Paragraph FullBleed() => new(new ParagraphProperties(
        new SpacingBetweenLines { Before = "0", After = "0", Line = "240", LineRule = LineSpacingRuleValues.Auto },
        new Indentation { Left = (-SideMargin).ToString(), Right = (-SideMargin).ToString() },
        new Justification { Val = JustificationValues.Center }));

    /// <summary>
    /// «صفحة X من Y» — و<b>لا ترقيم في الصفحة الواحدة</b> (قرار المالك) بحقلٍ شرطيّ:
    /// <c>{ IF { NUMPAGES } > 1 "صفحة { PAGE } من { NUMPAGES }" "" }</c> يحدّثه Word عند الفتح والطباعة.
    /// </summary>
    private static Paragraph PageNumber(BookDocument book)
    {
        var s = new WordHtml.Style(HalfPoints: 24);
        Run Code(string c) => new(WordHtml.Props(s, rtl: true), new FieldCode(c) { Space = SpaceProcessingModeValues.Preserve });
        Run Ch(FieldCharValues v) => new(WordHtml.Props(s, rtl: true), new FieldChar { FieldCharType = v });
        Run Txt(string t) => new(WordHtml.Props(s, rtl: true), new Text(t) { Space = SpaceProcessingModeValues.Preserve });
        IEnumerable<Run> Field(string name, string placeholder) =>
            [Ch(FieldCharValues.Begin), Code($" {name} "), Ch(FieldCharValues.Separate), Txt(placeholder), Ch(FieldCharValues.End)];

        var runs = new List<Run> { Ch(FieldCharValues.Begin), Code(" IF ") };
        runs.AddRange(Field("NUMPAGES", "2"));
        runs.Add(Code(" > 1 \"صفحة "));
        runs.AddRange(Field("PAGE", "1"));
        runs.Add(Code(" من "));
        runs.AddRange(Field("NUMPAGES", "2"));
        runs.Add(Code("\" \"\" "));
        runs.Add(Ch(FieldCharValues.Separate));
        runs.Add(Txt("صفحة 1 من 2"));
        runs.Add(Ch(FieldCharValues.End));

        var p = new Paragraph(PageNumberPlacement(book));
        foreach (var r in runs) p.AppendChild(r);
        return p;
    }

    /// <summary>
    /// موضع الترقيم من القالب (بلاغ المالك 2026-10-05): المحاذاة **فيزيائية** — فالفقرة بلا <c>bidi</c> (Word يقلب يمين/يسار
    /// في الفقرة العربية) والنصّ العربيّ في مقاطع RTL. والإزاحة الأفقية مسافةٌ بادئة، والعمودية تباعدٌ قبل السطر أو بعده.
    /// ⚠️ تقريبٌ لموضع الـPDF — والـPDF هو النسخة الرسمية.
    /// </summary>
    private static ParagraphProperties PageNumberPlacement(BookDocument book)
    {
        static int Twips(float pt) => (int)Math.Round(pt * 20);
        var x = Twips(book.PageNumberOffsetXPt);
        var y = Twips(book.PageNumberOffsetYPt);
        var (jc, ind) = book.PageNumberAlign switch
        {
            "right" => (JustificationValues.Right, x == 0 ? null : new Indentation { Right = (-x).ToString() }),
            "left" => (JustificationValues.Left, x == 0 ? null : new Indentation { Left = x.ToString() }),
            // الوسط يتحرّك نصفَ المسافة البادئة ⟵ تُضاعف
            _ => (JustificationValues.Center, x == 0 ? null : x > 0 ? new Indentation { Left = (2 * x).ToString() } : new Indentation { Right = (-2 * x).ToString() }),
        };
        var props = new ParagraphProperties(new SpacingBetweenLines
        {
            Before = (60 + Math.Max(0, -y)).ToString(),
            After = (60 + Math.Max(0, y)).ToString(),
        });
        if (ind is not null) props.AppendChild(ind);
        props.AppendChild(new Justification { Val = jc });
        return props;
    }

    // ─────────────────────────── كتل الرأس والتوقيع ───────────────────────────

    /// <summary>سطر الرأس: جدولٌ بلا حدود — الرقم والتاريخ (يسار، LTR) · العبارة (وسط) · فراغ (يمين).</summary>
    private static Table TopRow(BookDocument book)
    {
        var third = WordTables.ContentWidthTwips / 4;
        var left = new TableCell(CellProps(third),
            LtrPara($"No: {book.Number}"), LtrPara($"Date: {book.Date:yyyy-MM-dd}"));
        var middle = new TableCell(CellProps(third * 2),
            string.IsNullOrWhiteSpace(book.HeaderPhrase) ? new Paragraph() : Centered(book.HeaderPhrase!, 30, bold: true, before: 700));
        var right = new TableCell(CellProps(third), new Paragraph());
        return Borderless([third, third * 2, third], new TableRow(left, middle, right));
    }

    /// <summary>كتلة التوقيع (يسار) والختم (يمين) — بموضعهما في الـPDF. الغائب منهما خليةٌ فارغة.</summary>
    private static Table SignatureRow(OpenXmlPart owner, BookDocument book, DocumentAssets? assets, bool withSignature, bool withStamp)
    {
        // أعمدةٌ ثابتة بلا اعتمادٍ على محاذاة الفقرة: [هامش 50 نقطة | التوقيع 180 | فراغ | الختم 80] من اليسار —
        // 🐛 في فقرةٍ عربية يقلب Word «يسار/يمين» فخرج التوقيع لاصقاً بالختم يميناً، والـPDF يضعه يساراً.
        const int padW = 1000, sigW = 3600, stampW = 1600;
        var gapW = WordTables.ContentWidthTwips - padW - sigW - stampW;

        var sig = new TableCell(CellProps(sigW, TableVerticalAlignmentValues.Bottom));
        if (withSignature && !string.IsNullOrWhiteSpace(book.SignatoryName))
        {
            // التوقيع على يسار الصفحة كالـPDF: فقرةٌ يسرى بوسطٍ بعرضٍ محدود
            sig.AppendChild(SigLine(book.SignatoryName!, 30, bold: true, color: null));
            if (!string.IsNullOrWhiteSpace(book.SignatoryTitle))
                sig.AppendChild(SigLine(book.SignatoryTitle!, 26, bold: false, color: "595959"));
        }
        else sig.AppendChild(new Paragraph());

        var stamp = new TableCell(CellProps(stampW, TableVerticalAlignmentValues.Bottom));
        if (withStamp && assets?.QrPng is { } qr)
        {
            var p = Centered("", 16, bold: false, before: 0);
            p.RemoveAllChildren<Run>();
            p.AppendChild(WordImages.Inline(owner, qr, 70, 70, "QR"));
            stamp.AppendChild(p);
            stamp.AppendChild(Centered("امسح الرمز للتحقق", 16, bold: false, before: 0, color: "404040"));
        }
        else if (withStamp)
        {
            // المسودّة: مربّع «نسخة للمعاينة» مكان الختم كما في الـPDF
            var box = Centered("نسخة للمعاينة", 20, bold: false, before: 0, color: "404040");
            box.ParagraphProperties!.InsertAt(new ParagraphBorders(
                new TopBorder { Val = BorderValues.Single, Size = 6, Color = "999999" },
                new LeftBorder { Val = BorderValues.Single, Size = 6, Color = "999999" },
                new BottomBorder { Val = BorderValues.Single, Size = 6, Color = "999999" },
                new RightBorder { Val = BorderValues.Single, Size = 6, Color = "999999" }), 0);   // pBdr قبل bidi في ترتيب المخطّط
            stamp.AppendChild(box);
        }
        else stamp.AppendChild(new Paragraph());

        // بلا bidiVisual: الأعمدة من اليسار — التوقيع يسار الصفحة والختم يمينها، كما في الـPDF.
        var pad = new TableCell(CellProps(padW), new Paragraph());
        var gap = new TableCell(CellProps(gapW), new Paragraph());
        return Borderless([padW, sigW, gapW, stampW], new TableRow(pad, sig, gap, stamp));
    }

    private static Paragraph SigLine(string text, int halfPoints, bool bold, string? color)
    {
        var p = new Paragraph(new ParagraphProperties(
            new BiDi(),
            new SpacingBetweenLines { Before = "0", After = "0" },
            new Justification { Val = JustificationValues.Center }));   // الوسط لا ينقلب في الفقرة العربية
        p.AppendChild(WordHtml.Run(text, new WordHtml.Style(Bold: bold, HalfPoints: halfPoints, Font: HeadFont, Color: color)));
        return p;
    }

    private static Table Borderless(int[] widths, TableRow row)
    {
        var props = new TableProperties(
            new TableWidth { Width = widths.Sum().ToString(), Type = TableWidthUnitValues.Dxa },
            new TableBorders(
                new TopBorder { Val = BorderValues.Nil }, new LeftBorder { Val = BorderValues.Nil },
                new BottomBorder { Val = BorderValues.Nil }, new RightBorder { Val = BorderValues.Nil },
                new InsideHorizontalBorder { Val = BorderValues.Nil }, new InsideVerticalBorder { Val = BorderValues.Nil }),
            new TableLayout { Type = TableLayoutValues.Fixed });
        return new Table(props, new TableGrid(widths.Select(w => new GridColumn { Width = w.ToString() })), row);
    }

    private static TableCellProperties CellProps(int width, TableVerticalAlignmentValues? v = null)
    {
        var p = new TableCellProperties(new TableCellWidth { Width = width.ToString(), Type = TableWidthUnitValues.Dxa });
        if (v is { } va) p.AppendChild(new TableCellVerticalAlignment { Val = va });
        return p;
    }

    private static Paragraph LtrPara(string text)
    {
        var p = new Paragraph(new ParagraphProperties(
            new SpacingBetweenLines { Before = "0", After = "0" },
            new Justification { Val = JustificationValues.Left }));
        p.AppendChild(WordHtml.Run(text, new WordHtml.Style(Bold: true, HalfPoints: 26, Font: HeadFont)));
        return p;
    }

    private static Paragraph Centered(string text, int halfPoints, bool bold, int before, string? color = null)
    {
        var p = new Paragraph(new ParagraphProperties(
            new BiDi(),
            new SpacingBetweenLines { Before = before.ToString(), After = "0" },
            new Justification { Val = JustificationValues.Center }));
        p.AppendChild(WordHtml.Run(text, new WordHtml.Style(Bold: bold, HalfPoints: halfPoints, Font: HeadFont, Color: color)));
        return p;
    }

    private static Paragraph Spacer(int twips) => new(new ParagraphProperties(
        new SpacingBetweenLines { Before = "0", After = twips.ToString(), Line = "240", LineRule = LineSpacingRuleValues.Auto }));
}
