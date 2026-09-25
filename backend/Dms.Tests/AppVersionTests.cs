using System.Reflection;
using System.Runtime.CompilerServices;
using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>رقم إصدار البرنامج (ADR-054).</summary>
public class AppVersionTests
{
    [Theory]
    [InlineData("0.9.0", 0, 9, 0, null)]
    [InlineData("1.12.3", 1, 12, 3, null)]
    [InlineData("0.9.0+2850189abcdef", 0, 9, 0, "2850189abcdef")]
    [InlineData(" 2.0.1 ", 2, 0, 1, null)]
    public void Parse_ReadsPlainAndInformational(string text, int major, int minor, int patch, string? commit)
    {
        var v = AppVersion.Parse(text)!;
        Assert.Equal((major, minor, patch, commit), (v.Major, v.Minor, v.Patch, v.Commit));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("0.9")]
    [InlineData("0.9.x")]
    [InlineData("1.2.3.4")]
    [InlineData("-1.0.0")]
    public void Parse_RejectsWhatIsNotAVersion(string? text) => Assert.Null(AppVersion.Parse(text));

    [Fact]
    public void Compare_IsNumericNotTextual()
    {
        // 🔴 **مقارنةُ نصٍّ تقول إن 0.10.0 أقدم من 0.9.0** — والترتيب هنا ما يرفض استعادةَ نسخةٍ أحدث.
        Assert.True(AppVersion.Parse("0.10.0")!.IsNewerThan(AppVersion.Parse("0.9.0")!));
        Assert.True(AppVersion.Parse("1.0.0")!.IsNewerThan(AppVersion.Parse("0.99.99")!));
        Assert.False(AppVersion.Parse("0.9.0")!.IsNewerThan(AppVersion.Parse("0.9.1")!));
    }

    [Fact]
    public void Commit_DoesNotAffectOrder()
    {
        var a = AppVersion.Parse("0.9.0+aaaaaaa")!;
        var b = AppVersion.Parse("0.9.0+bbbbbbb")!;
        Assert.True(a.SameReleaseAs(b));
        Assert.False(a.IsNewerThan(b));
    }

    [Fact]
    public void ShortCommit_IsSevenChars_LikeGit()
    {
        Assert.Equal("2850189", AppVersion.Parse("0.9.0+2850189abcdef0123")!.ShortCommit);
        Assert.Null(AppVersion.Parse("0.9.0")!.ShortCommit);
        Assert.Equal("0.9.0", AppVersion.Parse("0.9.0+abc")!.Display);
    }

    /// <summary>
    /// 🔴 **الحارس الحقيقيّ: ما يُبنى = ما في `VERSION`.** لو سقط `Directory.Build.props` أو قُرئ ملفٌّ
    /// آخر، لحمل الخادم إصداراً افتراضياً (1.0.0) بصمت — **فيكذب «حول النظام» ويكذب فحص النسخ**.
    /// </summary>
    [Fact]
    public void BuiltAssemblyVersion_MatchesTheVersionFile()
    {
        var file = FindUp("VERSION");
        Assert.True(file is not null, "ملف VERSION غير موجود في جذر المستودع");
        var expected = AppVersion.Parse(File.ReadAllText(file!))!;

        var informational = typeof(AppVersion).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()!.InformationalVersion;
        var built = AppVersion.Parse(informational);

        Assert.NotNull(built);
        Assert.True(built!.SameReleaseAs(expected), $"المبنيّ {built} والملف {expected}");
    }

    // ⚠️ **صعوداً من ملفّ الاختبار المصدريّ لا من مجلد التشغيل** — الاختبارات قد تُبنى إلى مجلدٍ خارج
    //    المستودع (خادمُ التطوير يقفل `bin`)، فيضيع الطريق إلى الجذر.
    private static string? FindUp(string name, [CallerFilePath] string source = "")
    {
        for (var dir = new FileInfo(source).Directory; dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, name);
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}
