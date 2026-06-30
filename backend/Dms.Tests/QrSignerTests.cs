using Dms.Documents.Models;
using Dms.Documents.Security;
using Xunit;

namespace Dms.Tests;

public class QrSignerTests
{
    private static BookDocument SampleBook() => new()
    {
        CompanyName = "أرض العرين",
        Number = "DEN-2026-00124",
        Date = new DateOnly(2026, 6, 28),
        Entity = "وزارة الإعمار",
        Subject = "موضوع تجريبي",
        Body = "نص الكتاب",
        Amount = 25000m,
        Currency = "USD",
        ExchangeRate = 1310m,
    };

    [Fact]
    public void Sign_Then_Verify_IsValid()
    {
        var (priv, pub) = QrSigner.GenerateKeyPair();
        var content = QrSigner.CreateQrContent(SampleBook(), priv);

        var result = QrSigner.Verify(content, pub);

        Assert.True(result.IsValid);
        Assert.Equal("DEN-2026-00124", result.Number);
        Assert.Equal("2026-06-28", result.Date);
        Assert.Equal("32750000", result.AmountInIqd); // 25000 × 1310
    }

    [Fact]
    public void TamperedContent_FailsVerification()
    {
        var (priv, pub) = QrSigner.GenerateKeyPair();
        var content = QrSigner.CreateQrContent(SampleBook(), priv);

        // تعديل الجهة مع إبقاء التوقيع الأصلي
        var sep = content.LastIndexOf('|');
        var tampered = content[..sep].Replace("وزارة الإعمار", "جهة مزوّرة") + content[sep..];

        var result = QrSigner.Verify(tampered, pub);
        Assert.False(result.IsValid);
    }

    [Fact]
    public void WrongPublicKey_FailsVerification()
    {
        var (priv, _) = QrSigner.GenerateKeyPair();
        var (_, otherPub) = QrSigner.GenerateKeyPair();
        var content = QrSigner.CreateQrContent(SampleBook(), priv);

        var result = QrSigner.Verify(content, otherPub);
        Assert.False(result.IsValid);
    }

    [Fact]
    public void MalformedContent_FailsGracefully()
    {
        var (_, pub) = QrSigner.GenerateKeyPair();
        var result = QrSigner.Verify("not-a-valid-qr", pub);
        Assert.False(result.IsValid);
    }

    [Fact]
    public void CreateQrPng_ProducesPngBytes()
    {
        var (priv, _) = QrSigner.GenerateKeyPair();
        var content = QrSigner.CreateQrContent(SampleBook(), priv);
        var png = QrSigner.CreateQrPng(content);

        Assert.NotEmpty(png);
        // توقيع ملف PNG: 0x89 'P' 'N' 'G'
        Assert.Equal(0x89, png[0]);
        Assert.Equal((byte)'P', png[1]);
        Assert.Equal((byte)'N', png[2]);
        Assert.Equal((byte)'G', png[3]);
    }
}
