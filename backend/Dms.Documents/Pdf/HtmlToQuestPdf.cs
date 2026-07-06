using HtmlAgilityPack;
using QuestPDF.Fluent;
using QuestPDF.Infrastructure;

namespace Dms.Documents.Pdf;

public static class HtmlToQuestPdf
{
    public static void RenderHtml(this TextDescriptor textDescriptor, string html)
    {
        if (string.IsNullOrWhiteSpace(html))
            return;

        var doc = new HtmlDocument();
        doc.LoadHtml(html);

        if (doc.DocumentNode != null)
        {
            ProcessNode(doc.DocumentNode, textDescriptor, isBold: false, isItalic: false, isUnderline: false);
        }
    }

    private static void ProcessNode(HtmlNode node, TextDescriptor textDescriptor, bool isBold, bool isItalic, bool isUnderline)
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
            }
            return;
        }

        if (node.NodeType == HtmlNodeType.Element)
        {
            string tag = node.Name.ToLowerInvariant();

            bool bold = isBold || tag == "b" || tag == "strong";
            bool italic = isItalic || tag == "i" || tag == "em";
            bool underline = isUnderline || tag == "u";

            if (tag == "br")
            {
                textDescriptor.Span("\n");
            }

            foreach (var child in node.ChildNodes)
            {
                ProcessNode(child, textDescriptor, bold, italic, underline);
            }

            // إذا كان العنصر يمثل فقرة أو سطر مستقل، نضيف سطر جديد بعده (إلا إذا كان الأخير)
            if (tag == "p" || tag == "div" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "li")
            {
                // إذا لم يكن هذا العنصر هو الأخير، أضف مسافة سطر جديد
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
                ProcessNode(child, textDescriptor, isBold, isItalic, isUnderline);
            }
        }
    }
}
