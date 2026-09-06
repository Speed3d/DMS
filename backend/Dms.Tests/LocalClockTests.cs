using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس ساعة التوقيت المحلّي — «ما اليوم عند المستخدم؟» في موضعٍ واحد (ADR-037).
/// </summary>
public class LocalClockTests
{
    [Fact]
    public void Offset_IsBaghdad_AndFixed()
    {
        // العراق ألغى التوقيت الصيفي منذ 2015 — فالإزاحة ثابتة، ولا تُشتقّ من قاعدة مناطق
        // النظام (تختلف بين ويندوز ولينكس وقد تُحدَّث تحت أقدامنا).
        Assert.Equal(TimeSpan.FromHours(3), LocalClock.Offset);
    }

    [Fact]
    public void Now_IsThreeHoursAheadOfUtc()
    {
        var delta = LocalClock.Now - DateTime.UtcNow;

        // هامشٌ واسع لأن الاستدعاءين ليسا في اللحظة نفسها.
        Assert.InRange(delta.TotalMinutes, 179, 181);
    }

    [Fact]
    public void Today_HasNoTimeComponent()
    {
        Assert.Equal(TimeSpan.Zero, LocalClock.Today.TimeOfDay);
    }

    [Fact]
    public void DaysOverdue_IsZeroForTodayAndTheFuture()
    {
        // 🔴 **موعدُ اليوم ليس متأخراً**: اليوم لم ينتهِ بعد. وهذا هو الفرق كلُّه بين
        //    «الموعد يومٌ» و«الموعد لحظة».
        Assert.Equal(0, LocalClock.DaysOverdue(LocalClock.Today));
        Assert.Equal(0, LocalClock.DaysOverdue(LocalClock.Today.AddHours(23)));
        Assert.Equal(0, LocalClock.DaysOverdue(LocalClock.Today.AddDays(5)));
    }

    [Fact]
    public void DaysOverdue_CountsWholeDaysPast()
    {
        Assert.Equal(1, LocalClock.DaysOverdue(LocalClock.Today.AddDays(-1)));
        Assert.Equal(10, LocalClock.DaysOverdue(LocalClock.Today.AddDays(-10)));
    }

    [Fact]
    public void DaysOverdue_IgnoresTheTimeOfDayOnTheDueDate()
    {
        // موعدٌ خُزِّن بلحظةٍ متأخّرة من يوم الأمس ما زال متأخّراً يوماً واحداً لا صفراً.
        var yesterdayLate = LocalClock.Today.AddDays(-1).AddHours(23).AddMinutes(59);
        Assert.Equal(1, LocalClock.DaysOverdue(yesterdayLate));
    }
}
