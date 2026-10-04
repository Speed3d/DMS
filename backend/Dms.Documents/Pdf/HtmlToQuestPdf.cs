using System.Globalization;
using System.Text.RegularExpressions;
using Dms.Documents.Models;
using HtmlAgilityPack;
using QuestPDF.Fluent;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Pdf;

public static class HtmlToQuestPdf
{
    /// <summary>
    /// الحجم الأساسي للمتن بالنقاط — **Times New Roman 12** (قرار المالك، ADR-057)، ويطابقه نمط المتن في PdfGenerator.
    /// </summary>
    public const float BaseFontSize = 12f;

    /// <summary>خط المتن والجداول الافتراضيّ (قرار المالك — كما في كتبه على Word).</summary>
    public const string BodyFontFamily = "Times New Roman";

    /// <summary>هامش الخلية الداخليّ بالنقاط.</summary>
    private const float CellPadding = 4f;

    /// <summary>عائلات الخطوط المسجّلة فعلياً في QuestPDF (انظر ArabicFonts.EnsureRegistered).</summary>
    private static readonly HashSet<string> RegisteredFonts =
        new(StringComparer.OrdinalIgnoreCase) { "Amiri", "Cairo", "Arial", "Times New Roman" };

    /// <summary>خرائط أسماء/قيم شائعة → عائلة مسجّلة (تحمّل اختلاف الحالة أو القيمة المختصرة).</summary>
    private static readonly Dictionary<string, string> FontAlias = new(StringComparer.OrdinalIgnoreCase)
    {
        ["cairo"] = "Cairo",
        ["arial"] = "Arial",
        ["times"] = "Times New Roman",
        ["times new roman"] = "Times New Roman",
        ["amiri"] = "Amiri",
    };

    /// <summary>يحوّل قيمة font-size (px/pt/em) إلى نقاط PDF.</summary>
    private static float? ParseFontSize(string style)
    {
        var m = Regex.Match(style, @"font-size:\s*([\d.]+)\s*(px|pt|em|rem)?", RegexOptions.IgnoreCase);
        if (!m.Success || !float.TryParse(m.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var val))
            return null;
        return m.Groups[2].Value.ToLowerInvariant() switch
        {
            "px" => val * 0.75f,               // px → pt
            "em" or "rem" => BaseFontSize * val, // نسبي للأساس
            _ => val,                           // pt أو بلا وحدة
        };
    }

    /// <summary>يستخرج عائلة الخط من font-family ويردّها فقط إن كانت مسجّلة (وإلا الافتراضي).</summary>
    private static string? ResolveFontFamily(string style)
    {
        var m = Regex.Match(style, @"font-family:\s*([^;]+)", RegexOptions.IgnoreCase);
        if (!m.Success) return null;
        var first = m.Groups[1].Value.Split(',')[0].Trim().Trim('\'', '"');
        if (FontAlias.TryGetValue(first, out var mapped) && RegisteredFonts.Contains(mapped)) return mapped;
        return RegisteredFonts.Contains(first) ? first : null;
    }

    /// <summary>
    /// يرسم متن الكتاب: فقراتٌ ونصوص، و<b>جداول</b> (ADR-057) — كلُّ وسم <c>data-dms-table</c> يأخذ الجدول التالي من
    /// <paramref name="tables"/> بترتيبه (والقائمة أعدّتها طبقة البنية من الوسوم نفسها بعد الفحص والحساب).
    /// </summary>
    public static void RenderHtml(this ColumnDescriptor column, string html, IReadOnlyList<PrintTable>? tables = null)
        => RenderBlocks(column, html, tables, inCell: false);

    /// <summary>
    /// 🔑 **راسمُ فقراتٍ واحد للمتن ولخلايا الجداول** — فالتنسيق المختلط داخل الخلية (عريض · لون · حجم · خط · محاذاة)
    /// يُرسم بالقواعد نفسها التي يُرسم بها المتن، لا بنسخةٍ ثانيةٍ تتباعد.
    /// </summary>
    private static void RenderBlocks(ColumnDescriptor column, string html, IReadOnlyList<PrintTable>? tables, bool inCell)
    {
        if (string.IsNullOrWhiteSpace(html))
            return;

        var doc = new HtmlDocument();
        doc.LoadHtml(html);
        if (doc.DocumentNode == null) return;

        var tableIndex = 0;
        foreach (var node in doc.DocumentNode.ChildNodes)
        {
            if (!inCell && node.NodeType == HtmlNodeType.Element && node.Attributes.Contains("data-dms-table"))
            {
                // الجدول بترتيبه — وغيابُه (قائمةٌ أقصر) يُتخطّى بلا انهيار: لا يُرسم ما لم يُفحص.
                if (tables is not null && tableIndex < tables.Count)
                {
                    var t = tables[tableIndex];
                    column.Item().PaddingVertical(6).Element(c => RenderTable(c, t));
                }
                tableIndex++;
                continue;
            }

            if (node.NodeType == HtmlNodeType.Element || (node.NodeType == HtmlNodeType.Text && !string.IsNullOrWhiteSpace(node.InnerText)))
            {
                var align = GetAlignment(node);
                column.Item().Text(text =>
                {
                    // الخلية أضيق وأكثف من المتن: تباعدٌ أقلّ، ومحاذاةٌ لبداية السطر افتراضاً (لا ضبط).
                    text.DefaultTextStyle(x => x.LineHeight(inCell ? 1.25f : 1.6f));
                    ApplyAlignment(text, align, inCell ? "start" : "justify");
                    ProcessNode(node, text, isBold: false, isItalic: false, isUnderline: false, color: null, fontSize: null, fontFamily: null);
                });
            }
        }
    }

    // ─────────────────────────── الجداول (ADR-057) ───────────────────────────

    /// <summary>جدولٌ بعرضه ومحاذاته — والأضيق من المتن يُوضع في صفٍّ بفراغين نسبيّين.</summary>
    private static void RenderTable(IContainer container, PrintTable t)
    {
        if (t.WidthPct >= 100)
        {
            DrawTable(container, t);
            return;
        }

        var rest = 100f - t.WidthPct;
        var (before, after) = t.Align switch
        {
            "start" => (0f, rest),
            "end" => (rest, 0f),
            _ => (rest / 2, rest / 2),
        };
        container.Row(row =>
        {
            if (before > 0) row.RelativeItem(before);
            row.RelativeItem(t.WidthPct).Element(c => DrawTable(c, t));
            if (after > 0) row.RelativeItem(after);
        });
    }

    private static void DrawTable(IContainer container, PrintTable t)
    {
        // اتجاه الجدول نفسه (عربيّ يبدأ من اليمين · إنجليزيّ من اليسار) — والنصّ في كل خلية يحدّد اتجاهه بنفسه.
        var directed = t.Rtl ? container.ContentFromRightToLeft() : container.ContentFromLeftToRight();
        directed.Table(table =>
        {
            table.ColumnsDefinition(cols =>
            {
                foreach (var w in t.ColumnWeights) cols.RelativeColumn(w);
            });

            // صفوف العناوين: تتكرّر في أعلى كل صفحة (table.Header) — أو تُرسم صفوفاً عادية «في البداية فقط».
            var headerSeparate = t.RepeatHeader && t.HeaderRows > 0;
            if (headerSeparate)
                table.Header(h =>
                {
                    foreach (var cell in t.Cells.Where(c => c.Row < t.HeaderRows))
                        DrawCell(h.Cell(), cell, rowOffset: 0, t);
                });

            foreach (var cell in t.Cells.Where(c => !headerSeparate || c.Row >= t.HeaderRows))
                DrawCell(table.Cell(), cell, rowOffset: headerSeparate ? t.HeaderRows : 0, t);
        });
    }

    private static void DrawCell(QuestPDF.Elements.Table.ITableCellContainer slot, PrintCell cell, int rowOffset, PrintTable t)
    {
        IContainer c = slot
            .Row((uint)(cell.Row - rowOffset + 1)).Column((uint)(cell.Col + 1))
            .RowSpan((uint)cell.RowSpan).ColumnSpan((uint)cell.ColSpan);

        if (t.BorderPt > 0) c = c.Border(t.BorderPt).BorderColor(t.BorderColor);
        if (!string.IsNullOrEmpty(cell.Bg)) c = c.Background(cell.Bg);
        c = c.Padding(CellPadding);
        c = cell.VAlign switch
        {
            "top" => c.AlignTop(),
            "bottom" => c.AlignBottom(),
            _ => c.AlignMiddle(),
        };

        if (IsNumeric(cell.Html))
        {
            // 🔑 **الرقم لا ينكسر على سطرين** (قرار المالك): ارتفاعُ سطرٍ واحد + تصغيرٌ عند الضيق — في Word انكسر
            //    «1,425,00 / 0» لضيق العمود، وهنا يصغر الرقم قليلاً ويبقى كاملاً.
            var size = MaxFontSize(cell.Html) ?? BaseFontSize;
            c.Height(size * 1.45f).ScaleToFit().AlignMiddle().Column(col => RenderBlocks(col, cell.Html, null, inCell: true));
        }
        else
        {
            c.Column(col => RenderBlocks(col, cell.Html, null, inCell: true));
        }
    }

    /// <summary>خليةٌ نصُّها رقمٌ خالص (بفواصل أو كسرٍ أو أرقامٍ هندية) — تُحرس من الانكسار.</summary>
    public static bool IsNumeric(string html)
    {
        var text = HtmlEntity.DeEntitize(Regex.Replace(html ?? "", "<[^>]*>", "")).Trim();
        return text.Length > 0 && NumberText.IsMatch(text);
    }

    private static readonly Regex NumberText =
        new(@"^[-\u2212]?[0-9\u0660-\u0669\u06F0-\u06F9][0-9\u0660-\u0669\u06F0-\u06F9,.\u066B\u066C\s\u00A0]*$", RegexOptions.Compiled);

    private static float? MaxFontSize(string html)
    {
        float? max = null;
        foreach (Match m in Regex.Matches(html, @"font-size:[^;""']+", RegexOptions.IgnoreCase))
            if (ParseFontSize(m.Value) is { } v && (max is null || v > max)) max = v;
        if (Regex.IsMatch(html, @"<h[1-3]\b", RegexOptions.IgnoreCase)) max = Math.Max(max ?? 0, BaseFontSize * 1.5f);
        return max;
    }

    private static string GetAlignment(HtmlNode node)
    {
        if (node.NodeType != HtmlNodeType.Element) return "default";

        var cls = node.GetAttributeValue("class", "");
        if (cls.Contains("ql-align-center")) return "center";
        if (cls.Contains("ql-align-right")) return "right";
        if (cls.Contains("ql-align-left")) return "left";
        if (cls.Contains("ql-align-justify")) return "justify";

        var style = node.GetAttributeValue("style", "");
        if (style.Contains("text-align: center") || style.Contains("text-align:center")) return "center";
        if (style.Contains("text-align: right") || style.Contains("text-align:right")) return "right";
        if (style.Contains("text-align: left") || style.Contains("text-align:left")) return "left";
        if (style.Contains("text-align: justify") || style.Contains("text-align:justify")) return "justify";

        return "default";
    }

    private static void ApplyAlignment(TextDescriptor text, string align, string fallback = "justify")
    {
        switch (align == "default" ? fallback : align)
        {
            case "center": text.AlignCenter(); break;
            case "left": text.AlignLeft(); break;
            case "right": text.AlignRight(); break;
            case "start": text.AlignStart(); break;
            default: text.Justify(); break;
        }
    }

    private static void ProcessNode(HtmlNode node, TextDescriptor textDescriptor, bool isBold, bool isItalic, bool isUnderline, string? color, float? fontSize, string? fontFamily)
    {
        if (node.NodeType == HtmlNodeType.Text)
        {
            var text = HtmlEntity.DeEntitize(node.InnerText);
            // إزالة الفراغات والأسطر الناتجة عن تنسيق كود الـ HTML نفسه
            text = text.Replace("\n", "").Replace("\r", "");

            if (!string.IsNullOrEmpty(text))
            {
                var span = textDescriptor.Span(text);

                if (isBold) span.SemiBold(); // نستخدم SemiBold لأنه أوضح وأجمل للغة العربية
                if (isItalic) span.Italic();
                if (isUnderline) span.Underline();
                if (!string.IsNullOrEmpty(color))
                {
                    span.FontColor(color);
                }
                if (fontSize.HasValue) span.FontSize(fontSize.Value);
                if (!string.IsNullOrEmpty(fontFamily)) span.FontFamily(fontFamily);
            }
            return;
        }

        if (node.NodeType == HtmlNodeType.Element)
        {
            string tag = node.Name.ToLowerInvariant();

            // العناوين تُعدّ عريضة تلقائياً كما في المتصفح.
            bool bold = isBold || tag is "b" or "strong" or "h1" or "h2" or "h3" or "h4" or "h5" or "h6";
            bool italic = isItalic || tag == "i" || tag == "em";
            bool underline = isUnderline || tag == "u";

            string? nodeColor = color;
            float? nodeFontSize = fontSize;
            string? nodeFontFamily = fontFamily;

            // Hint: زرّ العناوين في المحرر يُنتج <h1>…<h6> بلا style، فبدون هذا التدرّج تُرسم بحجم النص العادي
            //       (يبدو للمستخدم أن «حجم الخط لا يعمل»). النسب مقاربة لما يعرضه المتصفح.
            var headingScale = tag switch
            {
                "h1" => 2.0f,
                "h2" => 1.5f,
                "h3" => 1.17f,
                "h4" => 1.0f,
                "h5" => 0.83f,
                "h6" => 0.67f,
                _ => 0f,
            };
            if (headingScale > 0f) nodeFontSize = BaseFontSize * headingScale;

            var style = node.GetAttributeValue("style", "");
            if (!string.IsNullOrEmpty(style))
            {
                var parsedSize = ParseFontSize(style);
                if (parsedSize.HasValue) nodeFontSize = parsedSize;
                var parsedFamily = ResolveFontFamily(style);
                if (parsedFamily != null) nodeFontFamily = parsedFamily;

                var colorMatch = Regex.Match(style, @"color:\s*([^;]+)");
                if (colorMatch.Success)
                {
                    nodeColor = colorMatch.Groups[1].Value.Trim().Trim('\'', '"');

                    // تحويل #RRGGBBAA إلى #RRGGBB لتجنب أي مشاكل مع QuestPDF
                    if (nodeColor.StartsWith("#") && nodeColor.Length == 9)
                    {
                        nodeColor = nodeColor.Substring(0, 7);
                    }

                    // QuestPDF supports hex colors (#RRGGBB) or named colors.
                    // If it's rgb(...), we might need to parse it, but QuestPDF supports hex out of the box.
                    if (nodeColor.StartsWith("rgb", StringComparison.OrdinalIgnoreCase))
                    {
                        var rgbMatch = Regex.Match(nodeColor, @"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)");
                        if (rgbMatch.Success)
                        {
                            int r = int.Parse(rgbMatch.Groups[1].Value);
                            int g = int.Parse(rgbMatch.Groups[2].Value);
                            int b = int.Parse(rgbMatch.Groups[3].Value);
                            nodeColor = $"#{r:X2}{g:X2}{b:X2}";
                        }
                    }
                }
            }

            if (tag == "br")
            {
                textDescriptor.Span("\n");
            }

            foreach (var child in node.ChildNodes)
            {
                ProcessNode(child, textDescriptor, bold, italic, underline, nodeColor, nodeFontSize, nodeFontFamily);
            }

            // لم نعد بحاجة لإضافة سطر جديد بين الفقرات الجذرية لأننا فصلناها إلى Items،
            // لكن إذا كان هناك عناصر داخلية (مثل li) نضيف سطر جديد
            if (tag == "li" || tag == "div")
            {
                if (node.NextSibling != null)
                {
                    textDescriptor.Span("\n");
                }
            }
        }
        else
        {
            foreach (var child in node.ChildNodes)
            {
                ProcessNode(child, textDescriptor, isBold, isItalic, isUnderline, color, fontSize, fontFamily);
            }
        }
    }
}
