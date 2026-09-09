using System.Text.Json;
using Dms.Documents.Models;
using Dms.Documents.Security;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حارس **مفاتيح توقيع بيئة التطوير** — وُلد من عيبٍ صامتٍ وُجد في 2026-09-10.
/// </summary>
/// <remarks>
/// 🔴 **العيب:** كان المفتاح العام في `appsettings.Development.json` **65 بايتاً** بينما
/// SPKI لمنحنى P-256 يحتاج **91**، والمفتاحان ليسا زوجاً أصلاً. فكان `QrSigner.Verify`
/// يرمي، **ويبتلع الاستثناءَ `catch` فيعيد «خطأ في التحقق»** — أي أن **التحقق لم يكن يعمل
/// في التطوير إطلاقاً**، ومهارة `verify-backend` تتوقّع `isValid=True`.
///
/// ⚠️ **ولم يكشفه أيّ اختبار** لأن اختبارات `QrSigner` كلَّها **تولّد مفاتيحها بنفسها** —
/// فتُثبت أن الخوارزمية سليمة ولا تمسّ ما هو مضبوطٌ فعلاً في الملفّ.
/// 🔑 **والدرس: اختبارٌ يصنع عيّنته بيده لا يحرس الإعداد الحقيقي** (نظير درس `RowVersion`).
/// </remarks>
public class DevSigningKeysTests
{
    [Fact]
    public void DevelopmentKeys_AreAValidPair_AndActuallyVerify()
    {
        var path = Path.Combine(AppContext.BaseDirectory,
            "..", "..", "..", "..", "Dms.Api", "appsettings.Development.json");

        if (!File.Exists(path)) return; // الملفّ خارج git — يُتخطّى حيث لا يوجد

        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        if (!doc.RootElement.TryGetProperty("QrSigning", out var qr)) return;

        var priv = qr.GetProperty("PrivateKeyBase64").GetString() ?? "";
        var pub = qr.GetProperty("PublicKeyBase64").GetString() ?? "";
        Assert.False(string.IsNullOrWhiteSpace(priv), "مفتاح التوقيع الخاص فارغ");
        Assert.False(string.IsNullOrWhiteSpace(pub), "مفتاح التوقيع العام فارغ");

        // 🔴 **الحارس الحقيقي: دورةٌ كاملة بالمفاتيح المضبوطة فعلاً** — لا فحصُ طولٍ فقط.
        var book = new BookDocument
        {
            CompanyName = "شركة الاختبار",
            Number = "DEV-2026-00001",
            Date = new DateOnly(2026, 1, 1),
            Entity = "جهة الاختبار",
            Subject = "موضوع",
            Body = "متن",
        };

        var result = QrSigner.Verify(QrSigner.CreateQrContent(book, priv), pub);

        Assert.True(result.IsValid,
            $"مفاتيح التطوير لا تُنتج توقيعاً يُتحقَّق منه — الرسالة: {result.Message}");
        Assert.Equal("DEV-2026-00001", result.Number);
    }
}
