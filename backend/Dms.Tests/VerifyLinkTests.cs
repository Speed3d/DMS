using Dms.Infrastructure.Documents;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// رمزُ رابط التحقق من نصٍّ ممسوح أو ملصوق (ADR-061) — الختم المطبوع يحمل رابطاً، والكاميرا داخل النظام تقرؤه.
/// </summary>
public class VerifyLinkTests
{
    private const string Token = "AAAAB3n6Tq8xYk2ZpQ9wLA";   // 22 حرفاً Base64Url كالرمز الحقيقيّ

    [Theory]
    [InlineData("https://dms.nociraq.com/v/" + Token)]
    [InlineData("http://localhost:5080/v/" + Token)]
    [InlineData("  https://dms.nociraq.com/v/" + Token + "  ")]
    [InlineData("https://dms.nociraq.com/v/" + Token + "/")]
    [InlineData("https://dms.nociraq.com/v/" + Token + "?src=qr")]
    [InlineData("https://dms.nociraq.com/v/" + Token + "#top")]
    [InlineData("dms.nociraq.com/v/" + Token)]
    [InlineData("/v/" + Token)]                               // الرابط النسبيّ كما يحمله verifyUrl
    [InlineData("HTTPS://DMS.NOCIRAQ.COM/v/" + Token)]
    public void TokenFromLink_ReadsThePrintedLink_WhateverTheHost(string input)
        => Assert.Equal(Token, PublicBookVerifier.TokenFromLink(input));

    [Fact]
    public void TokenFromLink_PdfLink_GivesTheBookToken()
        => Assert.Equal(Token, PublicBookVerifier.TokenFromLink("https://dms.nociraq.com/v/" + Token + "/pdf"));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("DMS2|abc|def")]                        // المحتوى الموقّع الخامّ — يمرّ بطريقه القديم
    [InlineData("https://dms.nociraq.com/verify/abc")]  // ليس رابط تحقّق
    [InlineData("https://dms.nociraq.com/v/")]
    [InlineData("https://dms.nociraq.com/v/abc")]       // أقصر من أيّ رمز
    [InlineData("https://dms.nociraq.com/v/../../etc")] // 🔐 لا رموز خارج Base64Url
    [InlineData("https://dms.nociraq.com/v/ab<script>")]
    [InlineData("DMS2|ab/v/AAAAB3n6Tq8xYk2ZpQ9wLA|cd")]   // 🔴 محتوى موقّع حوى ترميزُه «/v/» صدفةً — ليس رابطاً
    [InlineData("انظر https://dms.nociraq.com/v/AAAAB3n6Tq8xYk2ZpQ9wLA")]  // نصٌّ قبل الرابط ليس ما يطبعه الختم
    public void TokenFromLink_RejectsWhatIsNotAVerifyLink(string? input)
        => Assert.Null(PublicBookVerifier.TokenFromLink(input));

    [Fact]
    public void Verdicts_MatchThePublicPageWording()
    {
        Assert.Equal("تم التلاعب بالكتاب", PublicBookVerifier.TamperedVerdict().Title);
        Assert.Equal(PublicVerdict.Withdrawn, PublicBookVerifier.WithdrawnVerdict("X-1").Verdict);
        Assert.Equal("X-1", PublicBookVerifier.WithdrawnVerdict("X-1").Number);
    }
}
