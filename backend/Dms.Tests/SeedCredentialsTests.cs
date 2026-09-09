using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس بيانات أوّل مدير (<see cref="SeedCredentials"/>).
///
/// 🔴 **العيب المُقاس:** في الإنتاج كان <c>config["Seed:AdminUsername"]</c> يعيد <c>""</c>
///    لا <c>null</c> (لأن <c>appsettings.json</c> يشحن سلسلةً فارغة)، فيمرّ <c>?? "admin"</c>
///    بلا أثر ويُنشَأ سوبر أدمن **باسمٍ وكلمة مرورٍ فارغين** — ولا حسابَ آخر يُصلحه.
///    فالحرّاس هنا تفحص **الفراغ** لا الغياب وحده.
/// </summary>
public class SeedCredentialsTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\t")]
    public void EmptyOrMissing_FallsBackToDefaults(string? configured)
    {
        Assert.Equal(SeedCredentials.DefaultUsername, SeedCredentials.Username(configured));
        Assert.Equal(SeedCredentials.DefaultPassword, SeedCredentials.Password(configured));
    }

    [Fact]
    public void ConfiguredValues_AreUsedAsIs()
    {
        Assert.Equal("owner", SeedCredentials.Username("owner"));
        Assert.Equal("S3cret!Pass", SeedCredentials.Password("S3cret!Pass"));
    }

    /// <summary>🔴 الحارس الذي يمنع عودة العيب: لا يُنشأ حسابٌ بلا اسمٍ أو بلا كلمة مرور.</summary>
    [Fact]
    public void Result_IsNeverBlank()
    {
        foreach (var input in new string?[] { null, "", " ", "\r\n" })
        {
            Assert.False(string.IsNullOrWhiteSpace(SeedCredentials.Username(input)));
            Assert.False(string.IsNullOrWhiteSpace(SeedCredentials.Password(input)));
        }
    }

    /// <summary>⚠️ والافتراض يجب أن يبقى مقبولاً لسياسة كلمة المرور (٨ أحرف فأكثر).</summary>
    [Fact]
    public void DefaultPassword_SatisfiesMinimumLength()
        => Assert.True(SeedCredentials.DefaultPassword.Length >= 8);
}
