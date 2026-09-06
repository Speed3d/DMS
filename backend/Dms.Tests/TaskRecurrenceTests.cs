using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس حساب موعد النسخة التالية — ومنها **الحالة الحدّية التي تنفجر** (ADR-037).
/// </summary>
public class TaskRecurrenceTests
{
    private static readonly DateTime Jan31 = new(2026, 1, 31);

    [Fact]
    public void Daily_AddsTheInterval()
    {
        var next = TaskRecurrence.NextDueDate(new DateTime(2026, 3, 10), DmsRecurrencePattern.Daily, 3, null);
        Assert.Equal(new DateTime(2026, 3, 13), next);
    }

    [Fact]
    public void Weekly_AddsSevenPerInterval()
    {
        var next = TaskRecurrence.NextDueDate(new DateTime(2026, 3, 10), DmsRecurrencePattern.Weekly, 2, null);
        Assert.Equal(new DateTime(2026, 3, 24), next);
    }

    [Fact]
    public void Monthly_AddsMonths()
    {
        var next = TaskRecurrence.NextDueDate(new DateTime(2026, 3, 10), DmsRecurrencePattern.Monthly, 1, null);
        Assert.Equal(new DateTime(2026, 4, 10), next);
    }

    [Fact]
    public void Monthly_FromJan31_ClampsToFebruary_AndTheSequenceSlidesDown()
    {
        // 🔴 **درس شباط حرفياً**: `AddMonths` يقصّ نهاية الشهر ولا يعود إلى 31.
        //    القرار **مقبولٌ ومقصود** (سلوك .NET القياسي وأبسط ما يُشرَح) — لكنه **موثَّقٌ
        //    بحارس**، فالحالة الحدّية بلا حارسٍ هي التي تنفجر.
        var feb = TaskRecurrence.NextDueDate(Jan31, DmsRecurrencePattern.Monthly, 1, null);
        Assert.Equal(new DateTime(2026, 2, 28), feb);   // 2026 ليست كبيسة

        var mar = TaskRecurrence.NextDueDate(feb!.Value, DmsRecurrencePattern.Monthly, 1, null);
        Assert.Equal(new DateTime(2026, 3, 28), mar);   // لا يعود إلى 31 — ينزلق
    }

    [Fact]
    public void Monthly_FromJan31_InALeapYear_ClampsTo29()
    {
        var feb = TaskRecurrence.NextDueDate(new DateTime(2028, 1, 31), DmsRecurrencePattern.Monthly, 1, null);
        Assert.Equal(new DateTime(2028, 2, 29), feb);
    }

    [Fact]
    public void PastTheEndDate_ReturnsNull_SoTheChainStops()
    {
        var next = TaskRecurrence.NextDueDate(
            new DateTime(2026, 3, 10), DmsRecurrencePattern.Weekly, 1, new DateTime(2026, 3, 15));

        Assert.Null(next);
    }

    [Fact]
    public void LandingExactlyOnTheEndDate_IsAllowed()
    {
        // ⚠️ نهايةُ التكرار **يومٌ**، فنسخةٌ موعدها نفسُ ذلك اليوم مقبولة — والمقارنة بالتاريخ
        //    لا باللحظة، وإلا أسقطت ساعةٌ واحدة نسخةً صحيحة.
        var end = new DateTime(2026, 3, 17, 23, 59, 0);
        var next = TaskRecurrence.NextDueDate(new DateTime(2026, 3, 10), DmsRecurrencePattern.Weekly, 1, end);

        Assert.Equal(new DateTime(2026, 3, 17), next);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public void InvalidInterval_IsTreatedAsOne_NotThrown(int interval)
    {
        // الخدمة الخلفية تمرّ على كل المهام المتكررة — وصفٌّ واحدٌ مشوّه يجب ألّا يوقف الدورة
        // كلَّها. (نظير قرار «نقص سعر الصرف لا يمنع التوليد» في الرواتب.)
        var next = TaskRecurrence.NextDueDate(new DateTime(2026, 3, 10), DmsRecurrencePattern.Daily, interval, null);
        Assert.Equal(new DateTime(2026, 3, 11), next);
    }

    [Fact]
    public void EveryPattern_HasAnArabicName()
    {
        foreach (var p in Enum.GetValues<DmsRecurrencePattern>())
            Assert.NotEqual(p.ToString(), TaskRecurrence.ArabicName(p));
    }
}
