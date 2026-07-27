using System.Net;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Models;
using HtmlAgilityPack;

namespace Dms.Documents.Word;

/// <summary>
/// تصدير الكتاب إلى .docx بـ OpenXML (أصلي، بلا أدوات خارجية).
/// يضبط الاتجاه RTL والخط العربي للنص المعقّد (Complex Script).
/// </summary>
public sealed class WordExporter
{
    private const string FontCs = "Amiri"; // خط النص العربي (Complex Script)

    public byte[] Generate(BookDocument book)
    {
        using var ms = new MemoryStream();
        using (var doc = WordprocessingDocument.Create(ms, WordprocessingDocumentType.Document))
        {
            var main = doc.AddMainDocumentPart();
            main.Document = new Document();
            var body = main.Document.AppendChild(new Body());

            body.AppendChild(Para($"العدد: {book.Number}", bold: true));
            body.AppendChild(Para($"التاريخ: {book.Date:yyyy-MM-dd}", bold: true));
            body.AppendChild(Para($"الجهة: {book.Entity}", bold: true));
            body.AppendChild(Para($"الموضوع / {book.Subject}", bold: true));
            body.AppendChild(Para(""));
            AppendHtmlBody(body, book.Body);

            if (book.HasFinancials)
            {
                body.AppendChild(Para(""));
                body.AppendChild(Para("التفاصيل المالية:", bold: true));
                body.AppendChild(Para($"المبلغ: {book.Amount:#,0} {(IsUsd(book) ? "دولار" : "دينار")}"));
                if (IsUsd(book))
                    body.AppendChild(Para($"سعر الصرف: {book.ExchangeRate:#,0}"));
                body.AppendChild(Para($"المعادل بالدينار العراقي: {book.AmountInIqd:#,0} د.ع", bold: true));
            }

            main.Document.Save();
        }
        return ms.ToArray();
    }

    private static bool IsUsd(BookDocument b) =>
        string.Equals(b.Currency, "USD", StringComparison.OrdinalIgnoreCase);

    // ─────────────────────────── متن الكتاب (HTML → فقرات Word) ───────────────────────────

    /// <summary>
    /// يحوّل متن الكتاب (HTML من محرّر Quill) إلى فقرات Word حقيقية.
    /// </summary>
    /// <remarks>
    /// ⚠️ كان المتن يُحقن **خامّاً** (<c>Para(book.Body)</c>)، فيفتح المستخدم ملف Word فيجد
    /// <c>&lt;p&gt;نص&lt;/p&gt;</c> مكتوبةً حرفياً. لم يُكتشف طويلاً لأن **الزرّ لم يكن موصولاً
    /// بالواجهة أصلاً** (الفجوة G7) — فميزةٌ بلا مدخل لا أحد يجرّبها.
    ///
    /// يُغطّى هنا ما يُنتجه المحرّر فعلياً: فقرات · أسطر · عريض/مائل/تحته خط · قوائم · عناوين.
    /// أما الخط والحجم واللون فيبقيان لمسار الـPDF (<c>HtmlToQuestPdf</c>) — الـPDF هو المستند
    /// الرسمي المختوم، وWord صيغة عمل قابلة للتحرير.
    /// </remarks>
    private static void AppendHtmlBody(Body body, string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) { body.AppendChild(Para("")); return; }

        // نصّ بلا وسوم (كتب قديمة أو مُدخَل بسيط): يُكتب كما هو.
        if (!html.Contains('<')) { body.AppendChild(Para(WebUtility.HtmlDecode(html))); return; }

        var doc = new HtmlDocument();
        doc.LoadHtml(html);
        var root = doc.DocumentNode;

        var emitted = false;
        foreach (var block in EnumerateBlocks(root))
        {
            body.AppendChild(block);
            emitted = true;
        }
        if (!emitted) body.AppendChild(Para(""));
    }

    /// <summary>يمشي على العُقد ويُخرج فقرةً لكل كتلة؛ النصوص السائبة تُجمَّع في فقرة واحدة.</summary>
    private static IEnumerable<Paragraph> EnumerateBlocks(HtmlNode parent)
    {
        var pending = new List<Run>();

        foreach (var node in parent.ChildNodes)
        {
            if (node.NodeType == HtmlNodeType.Element && IsBlock(node.Name))
            {
                // نُفرِغ ما تجمّع من نصّ سائب قبل الكتلة حتى لا يُبتلع.
                if (pending.Count > 0) { yield return Wrap(pending); pending = new List<Run>(); }

                // القوائم حاوية لا فقرة — ننزل إلى عناصرها.
                if (node.Name is "ul" or "ol")
                {
                    foreach (var p in EnumerateBlocks(node)) yield return p;
                    continue;
                }

                var runs = new List<Run>();
                CollectRuns(node, runs, new Fmt());
                // بادئة القائمة: المحرّر لا يُرسل ترقيماً، فنُبقيها علامةً بسيطة تُقرأ صحيحاً في RTL.
                if (node.Name == "li") runs.Insert(0, MakeRun("• ", new Fmt()));
                var heading = node.Name.Length == 2 && node.Name[0] == 'h' && char.IsDigit(node.Name[1]);
                yield return Wrap(runs, bold: heading);
            }
            else
            {
                CollectRuns(node, pending, new Fmt());
            }
        }

        if (pending.Count > 0) yield return Wrap(pending);
    }

    private static bool IsBlock(string name) =>
        name is "p" or "div" or "li" or "ul" or "ol" or "h1" or "h2" or "h3" or "h4" or "h5" or "h6"
             or "blockquote" or "pre";

    /// <summary>سمات التنسيق المتوارثة أثناء النزول في الشجرة.</summary>
    private readonly record struct Fmt(bool Bold = false, bool Italic = false, bool Underline = false)
    {
        public Fmt With(string tag) => tag switch
        {
            "b" or "strong" => this with { Bold = true },
            "i" or "em" => this with { Italic = true },
            "u" or "ins" => this with { Underline = true },
            _ => this,
        };
    }

    private static void CollectRuns(HtmlNode node, List<Run> runs, Fmt fmt)
    {
        switch (node.NodeType)
        {
            case HtmlNodeType.Text:
                var text = WebUtility.HtmlDecode(node.InnerText);
                if (!string.IsNullOrEmpty(text)) runs.Add(MakeRun(text, fmt));
                return;

            case HtmlNodeType.Element when node.Name == "br":
                runs.Add(new Run(RunProps(new Fmt()), new Break()));
                return;

            case HtmlNodeType.Element:
                var inner = fmt.With(node.Name);
                foreach (var child in node.ChildNodes) CollectRuns(child, runs, inner);
                return;
        }
    }

    private static Paragraph Wrap(List<Run> runs, bool bold = false)
    {
        var p = new Paragraph(ParaProps());
        if (runs.Count == 0) { p.AppendChild(MakeRun("", new Fmt())); return p; }
        foreach (var r in runs)
        {
            if (bold)
            {
                var rPr = r.GetFirstChild<RunProperties>();
                rPr?.AppendChild(new Bold());
                rPr?.AppendChild(new BoldComplexScript());
            }
            p.AppendChild(r);
        }
        return p;
    }

    /// <summary>فقرة عربية RTL مع ضبط الخط للنص المعقّد.</summary>
    private static Paragraph Para(string text, bool bold = false, int sizeHalfPoints = 26) =>
        new(ParaProps(), MakeRun(text, new Fmt(Bold: bold), sizeHalfPoints));

    /// <summary>خصائص الفقرة: اتجاه من اليمين لليسار ومحاذاة يمين.</summary>
    private static ParagraphProperties ParaProps() => new(
        new BiDi(),                                  // فقرة من اليمين لليسار
        new Justification { Val = JustificationValues.Right });

    /// <summary>خصائص الـrun: الخط العربي واتجاه النص والحجم، مع سمات التنسيق.</summary>
    private static RunProperties RunProps(Fmt fmt, int sizeHalfPoints = 26)
    {
        var rPr = new RunProperties(
            new RunFonts { ComplexScript = FontCs, Ascii = FontCs, HighAnsi = FontCs },
            new RightToLeftText(),                   // اتجاه النص داخل الـ run
            new FontSizeComplexScript { Val = sizeHalfPoints.ToString() },
            new FontSize { Val = sizeHalfPoints.ToString() });

        // ⚠️ العربية نصّ معقّد (Complex Script): كل سمة تحتاج توأمها ‎*ComplexScript‎ وإلا
        //    ظهر التنسيق على اللاتيني وحده وبقي العربي عادياً.
        if (fmt.Bold) { rPr.AppendChild(new Bold()); rPr.AppendChild(new BoldComplexScript()); }
        if (fmt.Italic) { rPr.AppendChild(new Italic()); rPr.AppendChild(new ItalicComplexScript()); }
        if (fmt.Underline) rPr.AppendChild(new Underline { Val = UnderlineValues.Single });

        return rPr;
    }

    private static Run MakeRun(string text, Fmt fmt, int sizeHalfPoints = 26) =>
        new(RunProps(fmt, sizeHalfPoints),
            new Text(text) { Space = SpaceProcessingModeValues.Preserve });
}
