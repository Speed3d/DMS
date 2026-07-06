using System.Text;
using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Documents.Storage;
using Dms.Documents.Word;

Console.OutputEncoding = Encoding.UTF8;

// وضع توليد المفاتيح: dotnet run --project Dms.Spike -- keygen
if (args is ["keygen"])
{
    var (priv, pub) = QrSigner.GenerateKeyPair();
    var jwt = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(64));
    Console.WriteLine("JWT_KEY=" + jwt);
    Console.WriteLine("QR_PRIV=" + priv);
    Console.WriteLine("QR_PUB=" + pub);
    return;
}

// وضع تجزئة كلمة مرور: dotnet run --project Dms.Spike -- hash <password>
if (args.Length == 2 && args[0] == "hash")
{
    Console.WriteLine("HASH=" + BCrypt.Net.BCrypt.HashPassword(args[1], 12));
    return;
}

var outputDir = Path.Combine(Directory.GetCurrentDirectory(), "output");
Directory.CreateDirectory(outputDir);
var storage = new LocalFileStorage(Path.Combine(outputDir, "storage"));

Console.WriteLine("===========================================================");
Console.WriteLine("  Phase 0 — الاختبار التقني (DMS Spike)");
Console.WriteLine("===========================================================\n");

// ---------------------------------------------------------------------------
// كتاب نموذجي (عربي + حقول مالية بالدولار لاختبار سعر الصرف والمعادل بالدينار)
// ---------------------------------------------------------------------------
var book = new BookDocument
{
    CompanyName = "أرض العرين للتجارة والمقاولات",
    Number = "DEN-2026-00124",
    Date = new DateOnly(2026, 6, 28),
    Entity = "وزارة الإعمار والإسكان والبلديات",
    Subject = "تجهيز ومدّ شبكة مياه لمشروع سكني",
    Body = "تحية طيبة وبعد،\n" +
           "نحيطكم علماً بأن شركتنا قد أنجزت المرحلة الأولى من أعمال تجهيز ومدّ شبكة المياه " +
           "الخاصة بالمشروع السكني وفق المواصفات الفنية المعتمدة، ونرفق لكم تقريراً مفصّلاً بالأعمال المنجزة. " +
           "راجين التفضّل بالاطلاع والموافقة على صرف المستحقات المالية حسب العقد المبرم.\n" +
           "مع فائق الاحترام والتقدير.",
    Amount = 25000m,
    Currency = "USD",
    ExchangeRate = 1310m,
};

// ---------------------------------------------------------------------------
// 1) QR بتوقيع ECDSA P-256 + التحقق + كشف التزوير
// ---------------------------------------------------------------------------
Console.WriteLine("【1】 QR + التوقيع الرقمي (ECDSA P-256)");
var (privateKey, publicKey) = QrSigner.GenerateKeyPair();
Console.WriteLine("   • تم توليد زوج مفاتيح (المفتاح الخاص يُحفظ في Key Vault بالإنتاج).");

var qrContent = QrSigner.CreateQrContent(book, privateKey);
Console.WriteLine($"   • محتوى الـ QR ({qrContent.Length} حرف): {qrContent}");

var qrPng = QrSigner.CreateQrPng(qrContent);
var qrPath = Path.Combine(outputDir, "qr.png");
File.WriteAllBytes(qrPath, qrPng);

var ok = QrSigner.Verify(qrContent, publicKey);
Console.WriteLine($"   • التحقق من الأصل  : {(ok.IsValid ? "✅ صحيح" : "❌ فاشل")} — {ok.Message}");
Console.WriteLine($"     (الرقم={ok.Number} | التاريخ={ok.Date} | المبلغ بالدينار={ok.AmountInIqd})");

// محاكاة تزوير: تعديل الجهة مع إبقاء التوقيع القديم
var idx = qrContent.LastIndexOf('|');
var tampered = qrContent[..idx].Replace(book.Entity, "جهة مزوّرة") + qrContent[idx..];
var bad = QrSigner.Verify(tampered, publicKey);
Console.WriteLine($"   • التحقق من نسخة مزوّرة: {(bad.IsValid ? "❌ لم يُكتشف!" : "✅ كُشف التزوير")} — {bad.Message}\n");

// ---------------------------------------------------------------------------
// 2) صور القالب البديلة (هيدر/فوتر/علامة مائية بشفافية)
// ---------------------------------------------------------------------------
Console.WriteLine("【2】 صور القالب (محاكاة لصور الشركة)");
var assets = new DocumentAssets(
    Header: PlaceholderImages.CreateHeader(),
    Footer: PlaceholderImages.CreateFooter(),
    Watermark: PlaceholderImages.CreateWatermark(opacityPercent: 8),
    QrPng: qrPng);
Console.WriteLine("   • تم توليد الهيدر/الفوتر/العلامة المائية (شفافية 8%).\n");

// ---------------------------------------------------------------------------
// 3) توليد PDF عربي بـ QuestPDF + الحفظ عبر تجريد التخزين
// ---------------------------------------------------------------------------
Console.WriteLine("【3】 توليد PDF عربي (QuestPDF)");
var generator = new PdfGenerator();
var pdf = generator.Generate(book, assets);
var pdfKey = await storage.SaveAsync("DEN-2026-00124.pdf", pdf);
var pdfOut = Path.Combine(outputDir, "book.pdf");
File.WriteAllBytes(pdfOut, await storage.ReadAsync(pdfKey)); // قراءة عبر التجريد ثم نسخ للعرض
Console.WriteLine($"   • حُفظ في التخزين بمفتاح: {pdfKey}");
Console.WriteLine($"   • حجم الـ PDF: {pdf.Length / 1024} KB");

// معاينة بصرية (PNG) للتحقق من سلامة العربية RTL
var previewPath = Path.Combine(outputDir, "preview.png");
File.WriteAllBytes(previewPath, generator.GeneratePreviewImages(book, assets).First());
Console.WriteLine($"   • معاينة الصفحة: {previewPath}\n");

// ---------------------------------------------------------------------------
// 4) تصدير Word (OpenXML)
// ---------------------------------------------------------------------------
Console.WriteLine("【4】 تصدير Word (OpenXML)");
var docx = new WordExporter().Generate(book);
var docxOut = Path.Combine(outputDir, "book.docx");
File.WriteAllBytes(docxOut, docx);
Console.WriteLine($"   • حجم الـ Word: {docx.Length / 1024} KB\n");

// ---------------------------------------------------------------------------
Console.WriteLine("===========================================================");
Console.WriteLine("  ✅ اكتمل الاختبار. الملفات الناتجة:");
Console.WriteLine($"     PDF : {pdfOut}");
Console.WriteLine($"     Word: {docxOut}");
Console.WriteLine($"     QR  : {qrPath}");
Console.WriteLine("===========================================================");
