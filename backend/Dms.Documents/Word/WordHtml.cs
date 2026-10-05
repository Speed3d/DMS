using System.Globalization;
using System.Net;
using System.Text.RegularExpressions;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Wordprocessing;
using HtmlAgilityPack;

namespace Dms.Documents.Word;

/// <summary>
/// HTML المحرّر ⟵ فقرات Word (ADR-057) — للمتن ولخلايا الجداول معاً، **بالتنسيق المختلط** (عريض · مائل · تسطير ·
/// شطب · لون · حجم · خط · محاذاة) كما يرسمه الـPDF.
/// </summary>
/// <remarks>
/// ⚠️ كان المتن يُصدَّر بالعريض والمائل والتسطير وحدها ويُسقط الخط والحجم واللون («الـPDF هو الرسمي») — والمالك طلب نسخةً
/// **طبق الأصل** يعدّل عليها في Word (ت١٤)، فصار ما يُرى في الـPDF يُرى في Word.
/// </remarks>
internal static partial class WordHtml
{
    public const string BodyFont = "Times New Roman";
    public const int BodyHalfPoints = 24;   // 12 نقطة — Times New Roman 12 (قرار المالك)

    private static readonly Dictionary<string, string> Fonts = new(StringComparer.OrdinalIgnoreCase)
    {
        ["amiri"] = "Amiri", ["cairo"] = "Cairo", ["arial"] = "Arial",
        ["times"] = "Times New Roman", ["times new roman"] = "Times New Roman",
    };

    /// <summary>تنسيق النصّ المتوارث أثناء النزول في الشجرة.</summary>
    public sealed record Style(
        bool Bold = false, bool Italic = false, bool Underline = false, bool Strike = false,
        string? Color = null, int? HalfPoints = null, string? Font = null);

    /// <summary>
    /// كتل المتن بترتيبها: فقرات، و<b>جدولٌ</b> مكان كل وسم <c>data-dms-table</c> (من <paramref name="table"/> بالترتيب).
    /// </summary>
    public static IEnumerable<OpenXmlElement> Blocks(string? html, Func<int, OpenXmlElement?>? table, bool inCell)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            yield return Paragraph([], "default", inCell, Plain(""));
            yield break;
        }
        if (!html.Contains('<'))
        {
            yield return Paragraph([Run(WebUtility.HtmlDecode(html), new Style())], "default", inCell, html);
            yield break;
        }

        var doc = new HtmlDocument();
        doc.LoadHtml(html);
        var tableIndex = 0;
        var pending = new List<Run>();
        var emitted = false;

        foreach (var node in doc.DocumentNode.ChildNodes)
        {
            if (!inCell && node.NodeType == HtmlNodeType.Element && node.Attributes.Contains("data-dms-table"))
            {
                if (pending.Count > 0) { yield return Paragraph(pending, "default", inCell, ""); pending = []; }
                if (table?.Invoke(tableIndex) is { } t) { yield return t; emitted = true; }
                tableIndex++;
                continue;
            }

            if (node.NodeType == HtmlNodeType.Element && IsBlock(node.Name))
            {
                if (pending.Count > 0) { yield return Paragraph(pending, "default", inCell, ""); pending = []; }
                foreach (var p in BlockParagraphs(node, inCell)) { yield return p; emitted = true; }
            }
            else
            {
                Collect(node, pending, new Style());
            }
        }
        if (pending.Count > 0) { yield return Paragraph(pending, "default", inCell, ""); emitted = true; }
        if (!emitted) yield return Paragraph([], "default", inCell, "");
    }

    private static IEnumerable<Paragraph> BlockParagraphs(HtmlNode node, bool inCell)
    {
        if (node.Name is "ul" or "ol")
        {
            foreach (var li in node.ChildNodes.Where(n => n.NodeType == HtmlNodeType.Element))
                foreach (var p in BlockParagraphs(li, inCell)) yield return p;
            yield break;
        }

        var runs = new List<Run>();
        var style = new Style();
        var scale = node.Name switch { "h1" => 2.0, "h2" => 1.5, "h3" => 1.17, "h5" => 0.83, "h6" => 0.67, _ => 0 };
        if (node.Name.Length == 2 && node.Name[0] == 'h' && char.IsDigit(node.Name[1]))
            style = style with { Bold = true, HalfPoints = scale > 0 ? (int)Math.Round(BodyHalfPoints * scale) : null };
        Collect(node, runs, style);
        if (node.Name == "li") runs.Insert(0, Run("• ", style));
        yield return Paragraph(runs, Alignment(node), inCell, node.InnerText);
    }

    private static bool IsBlock(string name) =>
        name is "p" or "div" or "li" or "ul" or "ol" or "h1" or "h2" or "h3" or "h4" or "h5" or "h6" or "blockquote" or "pre";

    private static void Collect(HtmlNode node, List<Run> runs, Style style)
    {
        switch (node.NodeType)
        {
            case HtmlNodeType.Text:
                var text = WebUtility.HtmlDecode(node.InnerText).Replace("\r", "").Replace("\n", "");
                if (text.Length > 0) runs.Add(Run(text, style));
                return;
            case HtmlNodeType.Element when node.Name == "br":
                runs.Add(new Run(Props(style, rtl: false), new Break()));
                return;
            case HtmlNodeType.Element:
                var inner = Apply(node, style);
                foreach (var child in node.ChildNodes) Collect(child, runs, inner);
                return;
        }
    }

    /// <summary>وسمٌ ونمطُه ⟵ تنسيقٌ متوارث.</summary>
    private static Style Apply(HtmlNode node, Style s)
    {
        s = node.Name switch
        {
            "b" or "strong" => s with { Bold = true },
            "i" or "em" => s with { Italic = true },
            "u" or "ins" => s with { Underline = true },
            "s" or "strike" or "del" => s with { Strike = true },
            _ => s,
        };
        var css = node.GetAttributeValue("style", "");
        if (css.Length == 0) return s;

        if (ColorRx().Match(css) is { Success: true } c && Hex(c.Groups[1].Value.Trim()) is { } hex) s = s with { Color = hex };
        if (SizeRx().Match(css) is { Success: true } z
            && float.TryParse(z.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            var pt = z.Groups[2].Value.ToLowerInvariant() switch
            {
                "px" => v * 0.75f,
                "em" or "rem" => BodyHalfPoints / 2f * v,
                _ => v,
            };
            if (pt > 0) s = s with { HalfPoints = (int)Math.Round(pt * 2) };
        }
        if (FontRx().Match(css) is { Success: true } f)
        {
            var name = f.Groups[1].Value.Split(',')[0].Trim().Trim('\'', '"');
            if (Fonts.TryGetValue(name, out var font)) s = s with { Font = font };
        }
        return s;
    }

    /// <summary>لونٌ CSS ⟵ <c>RRGGBB</c> لـWord (سداسيّ أو rgb()).</summary>
    private static string? Hex(string css)
    {
        if (css.StartsWith('#') && css.Length is 7 or 9) return css.Substring(1, 6).ToUpperInvariant();
        var m = RgbRx().Match(css);
        return m.Success ? $"{int.Parse(m.Groups[1].Value):X2}{int.Parse(m.Groups[2].Value):X2}{int.Parse(m.Groups[3].Value):X2}" : null;
    }

    private static string Alignment(HtmlNode node)
    {
        var cls = node.GetAttributeValue("class", "");
        var css = node.GetAttributeValue("style", "").Replace(" ", "");
        foreach (var a in new[] { "center", "right", "left", "justify" })
            if (cls.Contains($"ql-align-{a}") || css.Contains($"text-align:{a}")) return a;
        return "default";
    }

    /// <summary>فقرة: اتجاهها من نصّها (عربيّ ⟵ من اليمين)، ومحاذاتها من المحرّر أو الافتراض (المتن مضبوط · الخلية يمين).</summary>
    public static Paragraph Paragraph(List<Run> runs, string align, bool inCell, string text)
    {
        var rtl = HasArabic(text) || runs.Any(r => r.InnerText is { } t && HasArabic(t));
        var jc = (align == "default" ? (inCell ? "right" : "justify") : align) switch
        {
            "center" => JustificationValues.Center,
            "left" => JustificationValues.Left,
            "justify" => JustificationValues.Both,
            _ => JustificationValues.Right,
        };
        var pPr = new ParagraphProperties();
        if (rtl) pPr.AppendChild(new BiDi());
        pPr.AppendChild(new SpacingBetweenLines { After = "0", Line = inCell ? "276" : "384", LineRule = LineSpacingRuleValues.Auto });
        pPr.AppendChild(new Justification { Val = jc });
        var p = new Paragraph(pPr);
        if (runs.Count == 0) p.AppendChild(Run("", new Style()));
        foreach (var r in runs) p.AppendChild(r);
        return p;
    }

    public static Run Run(string text, Style s) =>
        new(Props(s, HasArabic(text)), new Text(text) { Space = SpaceProcessingModeValues.Preserve });

    private static string Plain(string s) => s;

    public static RunProperties Props(Style s, bool rtl)
    {
        var font = s.Font ?? BodyFont;
        var size = (s.HalfPoints ?? BodyHalfPoints).ToString(CultureInfo.InvariantCulture);
        var rPr = new RunProperties(new RunFonts { Ascii = font, HighAnsi = font, ComplexScript = font, EastAsia = font });
        // ⚠️ العربية «نصٌّ معقّد»: كل سمةٍ تحتاج توأمها *ComplexScript وإلا ظهرت على اللاتينيّ وحده.
        if (s.Bold) { rPr.AppendChild(new Bold()); rPr.AppendChild(new BoldComplexScript()); }
        if (s.Italic) { rPr.AppendChild(new Italic()); rPr.AppendChild(new ItalicComplexScript()); }
        if (s.Strike) rPr.AppendChild(new Strike());
        if (s.Color is not null) rPr.AppendChild(new Color { Val = s.Color });
        rPr.AppendChild(new FontSize { Val = size });
        rPr.AppendChild(new FontSizeComplexScript { Val = size });
        if (s.Underline) rPr.AppendChild(new Underline { Val = UnderlineValues.Single });
        if (rtl) rPr.AppendChild(new RightToLeftText());
        return rPr;
    }

    public static bool HasArabic(string text) => ArabicRx().IsMatch(text);

    [GeneratedRegex(@"(?<![-\w])color:\s*([^;""']+)", RegexOptions.IgnoreCase)] private static partial Regex ColorRx();
    [GeneratedRegex(@"font-size:\s*([\d.]+)\s*(px|pt|em|rem)?", RegexOptions.IgnoreCase)] private static partial Regex SizeRx();
    [GeneratedRegex(@"font-family:\s*([^;""]+)", RegexOptions.IgnoreCase)] private static partial Regex FontRx();
    [GeneratedRegex(@"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)")] private static partial Regex RgbRx();
    [GeneratedRegex(@"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")] private static partial Regex ArabicRx();
}
