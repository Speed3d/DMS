using Dms.Domain;
using Xunit;
using U = Dms.Domain.BackupRetention.FullBackupUrgency;
using W = Dms.Domain.BackupHealth.Warning;

namespace Dms.Tests;

/// <summary>
/// صحّة النسخ ككلّ (ADR-062) — التنبيه كان يسأل عن عمر النسخة الكاملة وحده، فسكت عن جدولةٍ متوقّفة
/// وعشرة أيامٍ بلا نسخة وسجلّين ملفّاهما مفقودان (جهاز التطوير، 2026-10-15).
/// </summary>
public class BackupHealthTests
{
    private static readonly DateTime Now = new(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void All_good_is_ok_with_no_warnings()
    {
        var a = BackupHealth.Assess(Now.AddDays(-3), Now.AddHours(-10), scheduleOn: true, missingFiles: 0, Now);
        Assert.Equal(U.Ok, a.Urgency);
        Assert.Empty(a.Warnings);
        Assert.Equal(0, a.DaysSinceAnyBackup);
    }

    [Fact]
    public void Owner_dev_machine_case_raises_all_three()
    {
        // ما وُجد فعلاً: آخر نسخة كاملة 5 أكتوبر · الجدولة متوقّفة · سجلّان ملفّاهما مفقودان.
        var last = new DateTime(2026, 10, 5, 12, 31, 45, DateTimeKind.Utc);
        var a = BackupHealth.Assess(last, last, scheduleOn: false, missingFiles: 2, Now);
        Assert.Equal(U.Urgent, a.Urgency);
        Assert.Equal(U.Ok, a.FullUrgency);          // ⚠️ عمر الكاملة وحده كان «سليماً» — وهذا ما أسكت التنبيه
        Assert.Equal([W.ScheduleOff, W.Stale, W.MissingFiles], a.Warnings);
        Assert.Equal(9, a.DaysSinceAnyBackup);
    }

    [Fact]
    public void Schedule_off_alone_is_soon()
    {
        var a = BackupHealth.Assess(Now.AddDays(-1), Now.AddDays(-1), scheduleOn: false, missingFiles: 0, Now);
        Assert.Equal(U.Soon, a.Urgency);
        Assert.Equal([W.ScheduleOff], a.Warnings);
    }

    [Fact]
    public void Missing_files_alone_is_soon()
    {
        var a = BackupHealth.Assess(Now.AddDays(-1), Now.AddDays(-1), scheduleOn: true, missingFiles: 1, Now);
        Assert.Equal(U.Soon, a.Urgency);
        Assert.Equal([W.MissingFiles], a.Warnings);
    }

    [Theory]
    [InlineData(47, false)]     // يومان إلا ساعة
    [InlineData(48, false)]     // يومان تماماً — «أكثر من يومين» لم يبلغ
    [InlineData(49, true)]
    [InlineData(240, true)]
    public void Stale_after_more_than_two_days(int hoursAgo, bool stale)
    {
        var a = BackupHealth.Assess(Now.AddDays(-1), Now.AddHours(-hoursAgo), scheduleOn: true, missingFiles: 0, Now);
        Assert.Equal(stale, a.Warnings.Contains(W.Stale));
        Assert.Equal(stale ? U.Urgent : U.Ok, a.Urgency);
    }

    [Fact]
    public void No_backup_ever_is_overdue_and_stale()
    {
        // التثبيت الجديد: لا نسخة والجدولة متوقّفة افتراضاً — فشلٌ مغلق.
        var a = BackupHealth.Assess(null, null, scheduleOn: false, missingFiles: 0, Now);
        Assert.Equal(U.Overdue, a.Urgency);
        Assert.Null(a.DaysSinceAnyBackup);
        Assert.Contains(W.Stale, a.Warnings);
        Assert.Contains(W.ScheduleOff, a.Warnings);
    }

    [Fact]
    public void Full_overdue_wins_over_lighter_warnings()
    {
        // الجدولة اليومية تعمل (قاعدة فقط) والكاملة تجاوزت 30 يوماً — يبقى أحمر.
        var a = BackupHealth.Assess(Now.AddDays(-40), Now.AddHours(-5), scheduleOn: true, missingFiles: 1, Now);
        Assert.Equal(U.Overdue, a.Urgency);
        Assert.Equal(U.Overdue, a.FullUrgency);
        Assert.Equal([W.MissingFiles], a.Warnings);
    }
}
