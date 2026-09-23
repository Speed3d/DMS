using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس قاعدة إيقاف النظام (ADR-050): مَن يمرّ أثناء الإيقاف ومتى يُرفض الدخول.
/// </summary>
public class SystemAccessTests
{
    [Theory]
    [InlineData("/api/system/status")]
    [InlineData("/api/auth/login")]
    [InlineData("/api/auth/refresh")]
    [InlineData("/api/auth/logout")]
    [InlineData("/api/verify")]
    [InlineData("/API/Auth/Login/")]
    [InlineData("/v/abc123")]
    [InlineData("/v/abc123/pdf")]
    public void OpenPaths_PassForAnonymous(string path)
        => Assert.False(SystemAccess.ShouldBlock(true, path, authenticated: false, isSuperAdmin: false, hasBearer: false));

    [Theory]
    [InlineData("/api/outgoing")]
    [InlineData("/api/incoming/5")]
    [InlineData("/api/system/control")]
    [InlineData("/api/auth/me")]
    [InlineData("/api/auth/change-password")]
    [InlineData("/api/verify-something")]
    [InlineData("/api/v/abc")]
    [InlineData("/")]
    [InlineData("")]
    public void OtherPaths_BlockAuthenticatedNonSuperAdmin(string path)
        => Assert.True(SystemAccess.ShouldBlock(true, path, authenticated: true, isSuperAdmin: false, hasBearer: true));

    [Fact]
    public void SuperAdmin_PassesEverywhere()
    {
        Assert.False(SystemAccess.ShouldBlock(true, "/api/outgoing", true, true, true));
        Assert.False(SystemAccess.ShouldBlock(true, "/api/backup/run", true, true, true));
    }

    [Fact]
    public void NotLockedDown_NobodyBlocked()
        => Assert.False(SystemAccess.ShouldBlock(false, "/api/outgoing", true, false, true));

    // 🔴 رمزٌ منتهٍ يمرّ ليأخذ 401 فيجدّده صاحبه — وإلا بقي السوبر أدمن محجوباً عن نظامه.
    [Fact]
    public void ExpiredBearer_PassesToGet401_NotBlocked()
        => Assert.False(SystemAccess.ShouldBlock(true, "/api/outgoing", authenticated: false, isSuperAdmin: false, hasBearer: true));

    [Fact]
    public void AnonymousWithoutToken_OnClosedPath_Blocked()
        => Assert.True(SystemAccess.ShouldBlock(true, "/api/companies/1/logo", false, false, false));

    [Theory]
    [InlineData(UserRole.President)]
    [InlineData(UserRole.Manager)]
    [InlineData(UserRole.Employee)]
    [InlineData(UserRole.Reader)]
    public void SignIn_RejectedForEveryoneButSuperAdmin(UserRole role)
    {
        Assert.True(SystemAccess.RejectsSignIn(true, role));
        Assert.False(SystemAccess.RejectsSignIn(false, role));
    }

    [Fact]
    public void SignIn_SuperAdminAlwaysAllowed()
        => Assert.False(SystemAccess.RejectsSignIn(true, UserRole.SuperAdmin));

    [Fact]
    public void NormalizeText_RequiredAndLength()
    {
        Assert.Throws<ValidationException>(() => SystemAccess.NormalizeText("   ", required: true, "النص"));
        Assert.Null(SystemAccess.NormalizeText("  ", required: false, "النص"));
        Assert.Equal("نص", SystemAccess.NormalizeText("  نص  ", required: true, "النص"));
        Assert.Throws<ValidationException>(() =>
            SystemAccess.NormalizeText(new string('ا', SystemAccess.MaxTextLength + 1), required: true, "النص"));
    }
}
