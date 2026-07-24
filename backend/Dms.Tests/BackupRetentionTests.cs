using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// اختبارات سياسة الاحتفاظ وتصنيف النسخ المجدولة (نمط الجد/الأب/الابن).
/// Hint: منطق نقي قابل للاختبار بلا قاعدة بيانات — يحمي من تراكم النسخ بلا حدّ.
/// </summary>
public class BackupRetentionTests
{
    [Theory]
    [InlineData(RetentionCategory.Daily, 7)]
    [InlineData(RetentionCategory.Weekly, 4)]
    [InlineData(RetentionCategory.Monthly, 12)]
    [InlineData(RetentionCategory.Manual, 20)]
    public void KeepFor_MatchesPlan(RetentionCategory category, int expected)
        => Assert.Equal(expected, BackupRetention.KeepFor(category));

    [Fact]
    public void TotalScheduledRetention_IsBounded()
    {
        // 7 + 4 + 12 = 23 نسخة مجدولة كحدّ أقصى (بدل ~365 بلا سياسة).
        var total = BackupRetention.KeepDaily + BackupRetention.KeepWeekly + BackupRetention.KeepMonthly;
        Assert.Equal(23, total);
    }

    [Fact]
    public void FirstOfMonth_IsMonthlyFull()
    {
        var (scope, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, new DateTime(2026, 8, 1));
        Assert.Equal(BackupScope.Full, scope);
        Assert.Equal(RetentionCategory.Monthly, category);
    }

    [Fact]
    public void Friday_IsWeeklyFull()
    {
        // 2026-08-07 يوم جمعة (وليس أول الشهر).
        var date = new DateTime(2026, 8, 7);
        Assert.Equal(DayOfWeek.Friday, date.DayOfWeek);
        var (scope, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, date);
        Assert.Equal(BackupScope.Full, scope);
        Assert.Equal(RetentionCategory.Weekly, category);
    }

    [Fact]
    public void OrdinaryDay_IsDailyDbOnly()
    {
        // 2026-08-05 يوم أربعاء عادي.
        var (scope, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, new DateTime(2026, 8, 5));
        Assert.Equal(BackupScope.DbOnly, scope);
        Assert.Equal(RetentionCategory.Daily, category);
    }

    [Fact]
    public void MonthlyBeatsWeekly_WhenFirstIsFriday()
    {
        // 2026-05-01 أول الشهر وجمعة معاً ⇒ الأولوية للشهري.
        var date = new DateTime(2026, 5, 1);
        Assert.Equal(DayOfWeek.Friday, date.DayOfWeek);
        var (_, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, date);
        Assert.Equal(RetentionCategory.Monthly, category);
    }

    [Fact]
    public void WeeklyFrequency_AlwaysWeeklyFull()
    {
        // عند اختيار التكرار «أسبوعي» صراحةً: كل نسخة كاملة بتصنيف أسبوعي بغضّ النظر عن اليوم.
        var (scope, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Weekly, new DateTime(2026, 8, 5));
        Assert.Equal(BackupScope.Full, scope);
        Assert.Equal(RetentionCategory.Weekly, category);
    }
}
