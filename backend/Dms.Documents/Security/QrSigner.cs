using System.Security.Cryptography;
using System.Text;
using Dms.Documents.Models;
using QRCoder;

namespace Dms.Documents.Security;

/// <summary>
/// توقيع رقمي غير متماثل (ECDSA P-256) لمحتوى الـ QR + التحقق منه.
///
/// المبدأ:
///  - المفتاح الخاص يبقى على السيرفر (في الإنتاج: Azure Key Vault).
///  - محتوى الـ QR = بيانات الكتاب + توقيع. أي تعديل في البيانات يُبطل التوقيع → كشف فوري للتزوير.
///  - ECDSA P-256 يعطي توقيعاً صغيراً (~64 بايت) يناسب سعة الـ QR (بخلاف RSA).
///  - التحقق من التوقيع يعمل حتى دون اتصال (بالمفتاح العام)، ثم تُطابَق البيانات بالسجل في قاعدة البيانات.
/// </summary>
public static class QrSigner
{
    private const string Prefix = "DMS1"; // إصدار صيغة المحتوى
    private const char Sep = '|';

    /// <summary>توليد زوج مفاتيح ECDSA P-256. (PrivatePkcs8, PublicSpki) بصيغة Base64.</summary>
    public static (string PrivateKeyBase64, string PublicKeyBase64) GenerateKeyPair()
    {
        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var priv = Convert.ToBase64String(ecdsa.ExportPkcs8PrivateKey());
        var pub = Convert.ToBase64String(ecdsa.ExportSubjectPublicKeyInfo());
        return (priv, pub);
    }

    /// <summary>ينشئ محتوى الـ QR الموقّع لكتاب معيّن.</summary>
    public static string CreateQrContent(BookDocument book, string privateKeyBase64)
    {
        var canonical = BuildCanonical(book);

        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        ecdsa.ImportPkcs8PrivateKey(Convert.FromBase64String(privateKeyBase64), out _);

        var signature = ecdsa.SignData(
            Encoding.UTF8.GetBytes(canonical),
            HashAlgorithmName.SHA256); // P-256 → توقيع 64 بايت (r||s)

        return canonical + Sep + Base64Url.Encode(signature);
    }

    /// <summary>
    /// يتحقق من توقيع محتوى QR. يعيد النتيجة + البيانات المستخرجة.
    /// IsValid=false يعني أن المحتوى مزوّر أو معطوب.
    /// </summary>
    public static QrVerificationResult Verify(string qrContent, string publicKeyBase64)
    {
        try
        {
            var lastSep = qrContent.LastIndexOf(Sep);
            if (lastSep <= 0) return QrVerificationResult.Invalid("صيغة المحتوى غير صحيحة");

            var canonical = qrContent[..lastSep];
            var sigB64Url = qrContent[(lastSep + 1)..];
            var signature = Base64Url.Decode(sigB64Url);

            using var ecdsa = ECDsa.Create();
            ecdsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(publicKeyBase64), out _);

            var valid = ecdsa.VerifyData(
                Encoding.UTF8.GetBytes(canonical),
                signature,
                HashAlgorithmName.SHA256);

            if (!valid) return QrVerificationResult.Invalid("التوقيع غير مطابق — احتمال تزوير");

            var fields = canonical.Split(Sep);
            // [0]=Prefix [1]=Number [2]=Date [3]=Entity [4]=AmountInIqd
            return new QrVerificationResult(
                IsValid: true,
                Number: fields.ElementAtOrDefault(1) ?? "",
                Date: fields.ElementAtOrDefault(2) ?? "",
                Entity: fields.ElementAtOrDefault(3) ?? "",
                AmountInIqd: fields.ElementAtOrDefault(4) ?? "",
                Message: "توقيع صحيح");
        }
        catch (Exception ex)
        {
            return QrVerificationResult.Invalid($"خطأ في التحقق: {ex.Message}");
        }
    }

    /// <summary>يولّد صورة الـ QR كـ PNG (PngByteQRCode — بلا System.Drawing، يعمل على أي منصّة).</summary>
    public static byte[] CreateQrPng(string content, int pixelsPerModule = 10)
    {
        using var gen = new QRCodeGenerator();
        using var data = gen.CreateQrCode(content, QRCodeGenerator.ECCLevel.Q);
        var png = new PngByteQRCode(data);
        return png.GetGraphic(pixelsPerModule);
    }

    private static string BuildCanonical(BookDocument book)
    {
        var amountIqd = book.AmountInIqd?.ToString("0") ?? "-";
        // ملاحظة: في الإنتاج نُرمّز الحقول (Base64Url) لتفادي حرف الفاصل داخل القيم.
        return string.Join(Sep,
            Prefix,
            book.Number,
            book.Date.ToString("yyyy-MM-dd"),
            book.Entity,
            amountIqd);
    }
}

public sealed record QrVerificationResult(
    bool IsValid,
    string Number,
    string Date,
    string Entity,
    string AmountInIqd,
    string Message)
{
    public static QrVerificationResult Invalid(string message) =>
        new(false, "", "", "", "", message);
}

internal static class Base64Url
{
    public static string Encode(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static byte[] Decode(string s)
    {
        var b64 = s.Replace('-', '+').Replace('_', '/');
        b64 = (b64.Length % 4) switch
        {
            2 => b64 + "==",
            3 => b64 + "=",
            _ => b64
        };
        return Convert.FromBase64String(b64);
    }
}
