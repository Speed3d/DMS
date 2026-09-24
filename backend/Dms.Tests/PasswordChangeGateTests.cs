using Dms.Domain;

namespace Dms.Tests;

/// <summary>حرّاس «تغيير الكلمة المؤقتة يفرضه الخادم» (G19).</summary>
public class PasswordChangeGateTests
{
    [Theory]
    [InlineData("/api/auth/change-password")]
    [InlineData("/api/auth/logout")]
    [InlineData("/api/auth/me")]
    [InlineData("/api/auth/refresh")]
    [InlineData("/api/system/status")]
    [InlineData("/API/Auth/Change-Password/")]
    [InlineData("/v/abc123")]
    [InlineData("/api/verify")]
    public void OnlyWhatTheChangeNeeds_IsAllowed(string path)
        => Assert.True(PasswordChangeGate.IsAllowedBeforeChange(path));

    [Theory]
    [InlineData("/api/outgoing")]
    [InlineData("/api/users")]
    [InlineData("/api/system/control")]
    [InlineData("/api/auth/change-password-now")]
    [InlineData("/api/backup/run")]
    [InlineData("")]
    [InlineData(null)]
    public void EverythingElse_IsBlocked(string? path)
        => Assert.False(PasswordChangeGate.IsAllowedBeforeChange(path));

    // 🔴 **الجديدة تختلف عن المؤقتة** — وإلا بقي المدير الذي أعطاها يعرفها.
    [Fact]
    public void NewPassword_MustDifferFromCurrent()
        => Assert.Throws<ValidationException>(() => PasswordChangeGate.ValidateNew("Temp@12345", "Temp@12345"));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("short1!")]
    public void NewPassword_MinLength(string? next)
        => Assert.Throws<ValidationException>(() => PasswordChangeGate.ValidateNew("Temp@12345", next));

    [Fact]
    public void ValidChange_Passes()
        => PasswordChangeGate.ValidateNew("Temp@12345", "Mine@98765");
}
