using Dms.Domain;

namespace Dms.Tests;

/// <summary>حرّاس مفتاح منع التكرار (ADR-051). وسلوكُ الخدمة نفسها أمام قاعدةٍ حقيقية في <c>drafts-e2e</c>.</summary>
public class IdempotencyKeyTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Missing_MeansNoProtection_NotAnError(string? raw)
        => Assert.Null(IdempotencyKey.Normalize(raw));

    [Theory]
    [InlineData("3f2b8c1e-7d4a-4e1b-9c2d-1a2b3c4d5e6f:outgoing")]
    [InlineData("draft_1:entity")]
    [InlineData("ABC-123")]
    public void ValidKeys_PassTrimmed(string raw)
        => Assert.Equal(raw, IdempotencyKey.Normalize("  " + raw + " "));

    [Theory]
    [InlineData("مفتاح")]
    [InlineData("has space")]
    [InlineData("semi;colon")]
    [InlineData("slash/key")]
    public void MalformedKeys_Rejected(string raw)
        => Assert.Throws<ValidationException>(() => IdempotencyKey.Normalize(raw));

    [Fact]
    public void TooLong_Rejected()
        => Assert.Throws<ValidationException>(() => IdempotencyKey.Normalize(new string('a', IdempotencyKey.MaxLength + 1)));

    [Fact]
    public void Retention_OutlivesAnyRealisticOutage()
    {
        // مسوّدةٌ تنتظر إرسالها أيّاماً (إجازةٌ ثم عودة) — ومفتاحها يجب أن يبقى أطول من ذلك.
        Assert.True(IdempotencyKey.Retention >= TimeSpan.FromDays(14));
        Assert.True(IdempotencyKey.StaleReservation < TimeSpan.FromMinutes(10));
    }
}
