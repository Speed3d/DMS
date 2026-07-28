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

    /// <summary>
    /// 🔴 **الحارس الأهم:** لا نسخة مجدولة تكون «كاملة» مهما كان اليوم.
    /// </summary>
    /// <remarks>
    /// ترقيةُ المجدولة إلى كاملة كانت تعني ٣٦ نسخة × 80 غيغا = **2.9 تيرابايت** بعد استيراد
    /// الأرشيف الورقي. أيّ عودة لهذا السلوك تُفجّر القرص بصمت — فيُحرَس صراحةً.
    /// </remarks>
    [Theory]
    [InlineData(2026, 8, 1)]    // أول الشهر
    [InlineData(2026, 8, 7)]    // جمعة
    [InlineData(2026, 8, 5)]    // يوم عادي
    [InlineData(2026, 5, 1)]    // أول الشهر وجمعة معاً
    public void ScheduledBackups_AreNeverFull(int y, int m, int d)
    {
        var (scope, _) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, new DateTime(y, m, d));
        Assert.Equal(BackupScope.DbOnly, scope);
    }

    [Fact]
    public void FirstOfMonth_IsMonthlyCategory()
    {
        var (_, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, new DateTime(2026, 8, 1));
        Assert.Equal(RetentionCategory.Monthly, category);
    }

    [Fact]
    public void Friday_IsWeeklyCategory()
    {
        // 2026-08-07 يوم جمعة (وليس أول الشهر) — التصنيف يتدرّج وإن ثبت النطاق.
        var date = new DateTime(2026, 8, 7);
        Assert.Equal(DayOfWeek.Friday, date.DayOfWeek);
        var (_, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Daily, date);
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
    public void WeeklyFrequency_IsWeeklyDbOnly()
    {
        var (scope, category) = BackupRetention.ClassifyScheduled(BackupFrequency.Weekly, new DateTime(2026, 8, 5));
        Assert.Equal(BackupScope.DbOnly, scope);
        Assert.Equal(RetentionCategory.Weekly, category);
    }

    // ─────────────── تذكير النسخة الكاملة (يدوية بقرار المالك) ───────────────

    [Fact]
    public void NoFullBackupEver_IsOverdue()
    {
        // فشل مغلق: «لم تُؤخذ قط» ليست حالة سليمة — بل أسوأ الحالات.
        Assert.Equal(BackupRetention.FullBackupUrgency.Overdue,
            BackupRetention.ClassifyFullBackupAge(null, DateTime.UtcNow));
    }

    [Theory]
    [InlineData(0, BackupRetention.FullBackupUrgency.Ok)]
    [InlineData(20, BackupRetention.FullBackupUrgency.Ok)]
    [InlineData(26, BackupRetention.FullBackupUrgency.Ok)]
    [InlineData(27, BackupRetention.FullBackupUrgency.Soon)]     // ٣ أيام متبقّية
    [InlineData(28, BackupRetention.FullBackupUrgency.Urgent)]   // يومان
    [InlineData(29, BackupRetention.FullBackupUrgency.Urgent)]   // يوم
    [InlineData(30, BackupRetention.FullBackupUrgency.Overdue)]
    [InlineData(45, BackupRetention.FullBackupUrgency.Overdue)]
    public void FullBackupAge_EscalatesAsDeadlineApproaches(int daysAgo, BackupRetention.FullBackupUrgency expected)
    {
        var now = new DateTime(2026, 8, 1, 12, 0, 0, DateTimeKind.Utc);
        Assert.Equal(expected, BackupRetention.ClassifyFullBackupAge(now.AddDays(-daysAgo), now));
    }
}
