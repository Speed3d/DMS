using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// هل تُستعاد هذه النسخة على هذا الخادم؟ (ADR-055) — والرفضُ قبل أن يُلمس شيء.
/// </summary>
public class BackupCompatibilityTests
{
    private static readonly AppVersion Server = AppVersion.Parse("0.10.0")!;
    private static readonly string[] Migrations = ["20260101_A", "20260924_AddClientRequests"];
    private const int Sql2022 = 16;

    private static BackupVerdict Verdict(string? app, string? migration, int? sql) =>
        BackupCompatibility.Check(new BackupOrigin(AppVersion.Parse(app), migration, sql), Server, Migrations, Sql2022).Verdict;

    [Fact]
    public void SameOrOlder_IsAllowed_AndUpgradedOnBoot()
    {
        Assert.Equal(BackupVerdict.Ok, Verdict("0.10.0", "20260924_AddClientRequests", 16));
        Assert.Equal(BackupVerdict.Ok, Verdict("0.9.0", "20260101_A", 16));
        Assert.Equal(BackupVerdict.Ok, Verdict("0.9.0", "20260101_A", 15));   // SQL أقدم يُستعاد على أحدث
    }

    [Fact]
    public void OldBackupWithoutInfo_IsAllowed_WithNotice()
    {
        // نسخٌ قبل ADR-055 بلا `backup-info.json` — لا تُرفض (بياناتٌ حقيقية قد تكون فيها).
        var r = BackupCompatibility.Check(new BackupOrigin(null, null, null), Server, Migrations, Sql2022);
        Assert.Equal(BackupVerdict.OkUnknownVersion, r.Verdict);
        Assert.True(BackupCompatibility.Allows(r.Verdict));
        Assert.Contains("تُرقّى", r.Message);
    }

    [Fact]
    public void NewerSqlServer_IsRejected_BeforeAnythingElse()
    {
        // 🔴 قيدٌ في SQL Server نفسه — نسخةٌ من 2022 لا تُستعاد على 2019 مهما كان الإصدار.
        var r = BackupCompatibility.Check(new BackupOrigin(AppVersion.Parse("0.9.0"), "20260101_A", 16),
            Server, Migrations, serverSqlMajor: 15);
        Assert.Equal(BackupVerdict.NewerSqlServer, r.Verdict);
        Assert.False(BackupCompatibility.Allows(r.Verdict));
        Assert.Contains("2022", r.Message);
        Assert.Contains("2019", r.Message);
    }

    [Fact]
    public void UnknownMigration_IsRejected_EvenWithoutVersion()
    {
        // 🔑 المهاجرة أدقّ دليلٍ على المخطّط — قاعدةٌ متقدّمةٌ على الكود تُسقط كلَّ شاشة.
        Assert.Equal(BackupVerdict.UnknownMigration, Verdict(null, "20261231_FromTheFuture", 16));
        Assert.Equal(BackupVerdict.UnknownMigration, Verdict("0.10.0", "20261231_FromTheFuture", 16));
    }

    [Fact]
    public void NewerApp_IsRejected_EvenWithSameSchema()
    {
        var r = BackupCompatibility.Check(
            new BackupOrigin(AppVersion.Parse("0.11.0"), "20260924_AddClientRequests", 16), Server, Migrations, Sql2022);
        Assert.Equal(BackupVerdict.NewerApp, r.Verdict);
        Assert.Contains("0.11.0", r.Message);
        Assert.Contains("حدِّث البرنامج", r.Message);
    }

    [Fact]
    public void VersionOrder_IsNumeric_NotTextual()
    {
        // 0.9.9 نصّاً «أكبر» من 0.10.0 — ولو قورنا نصّاً لرُفضت نسخةٌ أقدم.
        Assert.Equal(BackupVerdict.Ok, Verdict("0.9.9", "20260101_A", 16));
    }

    [Theory]
    [InlineData(16, "2022")]
    [InlineData(15, "2019")]
    [InlineData(99, "الإصدار 99")]
    public void SqlName_IsReadable(int major, string expected) =>
        Assert.Equal(expected, BackupCompatibility.SqlName(major));
}
