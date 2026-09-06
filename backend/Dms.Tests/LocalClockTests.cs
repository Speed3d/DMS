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
    public void Today_CarriesNoTimeZone_SoItSerializesWithoutZ()
    {
        // 🔴 **عيبٌ وقع فعلاً وكشفه `tasks-e2e`**: `DateTime.UtcNow + Offset` يرث `Kind=Utc`،
        //    فعاد `StartDate` بلاحقة `Z` بعد الكتابة وبلا لاحقة بعد القراءة من `datetime2`
        //    — **صيغتان للحقل الواحد على السلك**. وتاريخٌ تقويميّ بـ`Z` يُنقص يوماً عند
        //    عميلٍ بإزاحةٍ سالبة، وهو عطل ADR-032 معكوساً.
        Assert.Equal(DateTimeKind.Unspecified, LocalClock.Today.Kind);
        Assert.Equal(DateTimeKind.Unspecified, LocalClock.Now.Kind);

        // والبرهان على السلك لا في النوع: التسلسل بلا `Z`.
        var json = System.Text.Json.JsonSerializer.Serialize(LocalClock.Today);
        Assert.DoesNotContain("Z", json);
    }

    [Fact]
    public void CalendarDate_NormalisesWhateverTheClientSent()
    {
        // العميل قد يرسل `Z` أو إزاحةً أو لا شيء — والتخزين يجب أن يكون واحداً.
        var utc = new DateTime(2026, 9, 13, 21, 30, 0, DateTimeKind.Utc);
        var local = new DateTime(2026, 9, 13, 21, 30, 0, DateTimeKind.Local);
        var unspecified = new DateTime(2026, 9, 13, 21, 30, 0, DateTimeKind.Unspecified);

        foreach (var v in new[] { utc, local, unspecified })
        {
            var c = LocalClock.CalendarDate(v);
            Assert.Equal(DateTimeKind.Unspecified, c.Kind);
            Assert.Equal(TimeSpan.Zero, c.TimeOfDay);

            // 🔴 **واليوم لا يتزحزح**: التطبيع يقصّ الوقت ولا يحوّل المنطقة — فتحويلُ
            //    **يومٍ** يُنقصه يوماً، وهو العطل المعكوس الذي تحرسه هذه الحالة.
            Assert.Equal(new DateTime(2026, 9, 13), c.Date);
        }

        Assert.Null(LocalClock.CalendarDate((DateTime?)null));
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
