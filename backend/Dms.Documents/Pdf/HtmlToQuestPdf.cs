using HtmlAgilityPack;
using QuestPDF.Fluent;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Pdf;

public static class HtmlToQuestPdf
{
    public static void RenderHtml(this ColumnDescriptor column, string html)
    {
        if (string.IsNullOrWhiteSpace(html))
            return;

        var doc = new HtmlDocument();
        doc.LoadHtml(html);

        if (doc.DocumentNode != null)
        {
            foreach (var node in doc.DocumentNode.ChildNodes)
            {
                if (node.NodeType == HtmlNodeType.Element || (node.NodeType == HtmlNodeType.Text && !string.IsNullOrWhiteSpace(node.InnerText)))
                {
                    var align = GetAlignment(node);
                    column.Item().Text(text => 
                    {
                        text.DefaultTextStyle(x => x.LineHeight(1.6f));
                        ApplyAlignment(text, align);
                        ProcessNode(node, text, isBold: false, isItalic: false, isUnderline: false, color: null);
                    });
                }
            }
        }
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

    private static void ApplyAlignment(TextDescriptor text, string align)
    {
        switch (align)
        {
            case "center": text.AlignCenter(); break;
            case "left": text.AlignLeft(); break;
            case "right": text.AlignRight(); break;
            case "justify": text.Justify(); break;
            default: text.Justify(); break; // الافتراضي
        }
    }

    private static void ProcessNode(HtmlNode node, TextDescriptor textDescriptor, bool isBold, bool isItalic, bool isUnderline, string? color)
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
            }
            return;
        }

        if (node.NodeType == HtmlNodeType.Element)
        {
            string tag = node.Name.ToLowerInvariant();

            bool bold = isBold || tag == "b" || tag == "strong";
            bool italic = isItalic || tag == "i" || tag == "em";
            bool underline = isUnderline || tag == "u";
            
            string? nodeColor = color;
            var style = node.GetAttributeValue("style", "");
            if (!string.IsNullOrEmpty(style))
            {
                var colorMatch = System.Text.RegularExpressions.Regex.Match(style, @"color:\s*([^;]+)");
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
                        var rgbMatch = System.Text.RegularExpressions.Regex.Match(nodeColor, @"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)");
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
                ProcessNode(child, textDescriptor, bold, italic, underline, nodeColor);
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
                ProcessNode(child, textDescriptor, isBold, isItalic, isUnderline, color);
            }
        }
    }
}
