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
        // ⚠️ **يُبدَّل محرفٌ في المتن المُوقَّع لا في نصٍّ عربيّ ظاهر** — فمنذ `DMS2` صارت
        //    الحقول مُرمَّزة، والاستبدالُ بالاسم العربي لم يعُد يجد شيئاً **فكان الاختبار
        //    يمرّ بلا أن يُبدّل حرفاً**. هذه الصيغة تعمل مع أي إصدار.
        var (priv, pub) = QrSigner.GenerateKeyPair();
        var content = QrSigner.CreateQrContent(SampleBook(), priv);

        var sep = content.LastIndexOf('|');
        var canonical = content[..sep];
        var flipped = canonical[..^1] + (canonical[^1] == 'A' ? 'B' : 'A');
        var tampered = flipped + content[sep..];

        Assert.NotEqual(canonical, flipped); // الحارس يقيس شيئاً فعلاً
        Assert.False(QrSigner.Verify(tampered, pub).IsValid);
    }

    [Fact]
    public void FieldContainingSeparator_SurvivesRoundTrip()
    {
        // 🔴 **العيب الذي عالجه `DMS2`**: كانت الحقول خامّة، فاسمُ جهةٍ فيه `|` يُزيح
        //    الحقول كلَّها — يبقى التوقيع صحيحاً وتُقرأ القيم في مواضع غيرها.
        var (priv, pub) = QrSigner.GenerateKeyPair();
        var book = SampleBook() with { Entity = "وزارة الإعمار | دائرة العقود" };

        var result = QrSigner.Verify(QrSigner.CreateQrContent(book, priv), pub);

        Assert.True(result.IsValid);
        Assert.Equal("وزارة الإعمار | دائرة العقود", result.Entity);
        Assert.Equal("DEN-2026-00124", result.Number);
        Assert.Equal("2026-06-28", result.Date);
        Assert.Equal("32750000", result.AmountInIqd);
    }

    [Fact]
    public void LegacyDms1Content_StillVerifies()
    {
        // 🔴 **الورق لا يُعاد طبعُه**: كتابٌ اعتُمد بالصيغة الأولى يبقى رمزُه صالحاً للأبد.
        var (priv, pub) = QrSigner.GenerateKeyPair();

        var canonical = string.Join('|',
            "DMS1", "DEN-2026-00124", "2026-06-28", "وزارة الإعمار", "32750000");

        using var ecdsa = System.Security.Cryptography.ECDsa.Create();
        ecdsa.ImportPkcs8PrivateKey(Convert.FromBase64String(priv), out _);
        var sig = ecdsa.SignData(
            System.Text.Encoding.UTF8.GetBytes(canonical),
            System.Security.Cryptography.HashAlgorithmName.SHA256);

        var legacy = canonical + '|' +
            Convert.ToBase64String(sig).TrimEnd('=').Replace('+', '-').Replace('/', '_');

        var result = QrSigner.Verify(legacy, pub);

        Assert.True(result.IsValid);
        Assert.Equal("وزارة الإعمار", result.Entity);   // تُقرأ خامّة لا مُرمَّزة
        Assert.Equal("32750000", result.AmountInIqd);
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
