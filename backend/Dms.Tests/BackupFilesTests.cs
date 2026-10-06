using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>ملفاتُ نسخٍ بلا سجلّ (ADR-059) — الاسم يدخل في مسار ملف، والحديث قد يكون نسخةً تُكتب الآن.</summary>
public class BackupFilesTests
{
    [Theory]
    [InlineData("backup-20261005-153145.zip", true)]
    [InlineData("uploaded-20260925-173946.zip", true)]
    [InlineData("backup-20261005-153145.ZIP", false)]
    [InlineData("../backup-20261005-153145.zip", false)]          // 🔐 خروجٌ من المجلد
    [InlineData("..\\backup-20261005-153145.zip", false)]
    [InlineData("sub/backup-20261005-153145.zip", false)]
    [InlineData("backup-20261005-153145.zip.bak", false)]
    [InlineData("upload-check-20261005153145-abc.bak", false)]    // ملفّ فحصٍ مؤقّت لا نسخة
    [InlineData("restore-20261005-153145", false)]                // مجلد استعادةٍ مؤقّت
    [InlineData("backup-2026105-153145.zip", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void OnlyTheSystemsOwnNames_AreAccepted(string? name, bool ok) => Assert.Equal(ok, BackupFiles.IsBackupFileName(name));

    private static readonly DateTime Now = new(2026, 10, 6, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void RecordedFile_IsNeverUnrecorded()
    {
        var recorded = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "backup-20261005-153145.zip" };
        Assert.False(BackupFiles.IsUnrecorded("backup-20261005-153145.zip", Now.AddDays(-1), recorded, Now));
        Assert.False(BackupFiles.IsUnrecorded("BACKUP-20261005-153145.zip", Now.AddDays(-1), recorded, Now));
    }

    [Fact]
    public void FreshFile_MayBeABackupBeingWritten_SoItIsLeftAlone()
    {
        var none = new HashSet<string>();
        Assert.False(BackupFiles.IsUnrecorded("backup-20261006-115500.zip", Now.AddMinutes(-5), none, Now));
        Assert.True(BackupFiles.IsUnrecorded("backup-20261006-114000.zip", Now - BackupFiles.MinAge, none, Now));
    }

    [Fact]
    public void ForeignFiles_InTheFolder_AreNeverListed()
        => Assert.False(BackupFiles.IsUnrecorded("notes.zip", Now.AddDays(-30), new HashSet<string>(), Now));
}
