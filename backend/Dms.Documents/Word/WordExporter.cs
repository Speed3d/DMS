using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Models;

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
            body.AppendChild(Para(book.Body));

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

    /// <summary>فقرة عربية RTL مع ضبط الخط للنص المعقّد.</summary>
    private static Paragraph Para(string text, bool bold = false, int sizeHalfPoints = 26)
    {
        var pPr = new ParagraphProperties(
            new BiDi(),                              // فقرة من اليمين لليسار
            new Justification { Val = JustificationValues.Right });

        var rPr = new RunProperties(
            new RunFonts { ComplexScript = FontCs, Ascii = FontCs, HighAnsi = FontCs },
            new RightToLeftText(),                   // اتجاه النص داخل الـ run
            new FontSizeComplexScript { Val = sizeHalfPoints.ToString() },
            new FontSize { Val = sizeHalfPoints.ToString() });
        if (bold)
        {
            rPr.AppendChild(new Bold());
            rPr.AppendChild(new BoldComplexScript());
        }

        var run = new Run(rPr, new Text(text) { Space = SpaceProcessingModeValues.Preserve });
        return new Paragraph(pPr, run);
    }
}
