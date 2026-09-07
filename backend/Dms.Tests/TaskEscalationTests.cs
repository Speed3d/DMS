using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس سُلّم التصعيد (ADR-039).
/// </summary>
public class TaskEscalationTests
{
    [Theory]
    [InlineData(0, 0)]    // موعدُ اليوم ليس متأخراً
    [InlineData(1, 1)]
    [InlineData(2, 1)]
    [InlineData(3, 2)]    // عتبة المديرين
    [InlineData(6, 2)]
    [InlineData(7, 3)]    // عتبة الرئاسة
    [InlineData(30, 3)]
    public void LevelFor_FollowsTheLadder(int daysOverdue, int expected)
        => Assert.Equal(expected, TaskEscalation.LevelFor(daysOverdue));

    [Fact]
    public void NothingOverdue_MeansNoEscalation()
    {
        // 🔴 **صفرٌ لِما لم يتأخّر بعد**: مهمةٌ موعدها اليوم ليست متأخرة (قاعدة `LocalClock`)،
        //    وتصعيدُها إزعاجٌ **يعلّم المستخدم تجاهل التصعيد** — فيضيع النافع مع الضارّ.
        Assert.Equal(0, TaskEscalation.LevelFor(0));
        Assert.Equal(0, TaskEscalation.LevelFor(-5));
        Assert.False(TaskEscalation.ShouldEscalate(0, 0));
    }

    [Fact]
    public void EachLevelFiresOnce_NotDaily()
    {
        // 🔴 **إشعارٌ واحد لكل (مهمة × مستوى)** — مهمةٌ متأخرة أسبوعين × خمسة مديرين =
        //    **70 إشعاراً بلا معلومةٍ جديدة**. والتصعيد يقول «ساءت الحال»، والحال تسوء
        //    **حين تعبر عتبة** لا كل يوم.
        Assert.True(TaskEscalation.ShouldEscalate(1, 0));    // أوّل تأخّر
        Assert.False(TaskEscalation.ShouldEscalate(1, 1));   // اليوم التالي — لا شيء جديد
        Assert.True(TaskEscalation.ShouldEscalate(2, 1));    // عبَرَ عتبة المديرين
        Assert.False(TaskEscalation.ShouldEscalate(2, 2));
        Assert.True(TaskEscalation.ShouldEscalate(3, 2));    // عبَرَ عتبة الرئاسة
        Assert.False(TaskEscalation.ShouldEscalate(3, 3));
    }

    [Fact]
    public void GoingBackDownDoesNotRefire()
    {
        // 🔴 **المقارنة «أكبر من» لا «لا يساوي»**: مهمةٌ صُعِّدت إلى 3 ثم مُدّد موعدها فصار
        //    تأخّرها يوماً **لا تُصعَّد إلى 1 ثانيةً** — فذلك إشعارٌ يقول «ساءت الحال» وقد
        //    تحسّنت. والتصفير يقع عند التأجيل وإعادة الإسناد وإعادة الفتح **صراحةً**.
        Assert.False(TaskEscalation.ShouldEscalate(1, 3));
        Assert.False(TaskEscalation.ShouldEscalate(2, 3));
    }

    [Fact]
    public void AfterResetTheLadderStartsOver()
    {
        // إعادة الفتح تُصفّر الأعمدة الثلاثة ⇒ يُستأنف التصعيد من الصفر.
        Assert.True(TaskEscalation.ShouldEscalate(1, 0));
    }

    [Fact]
    public void ThresholdsAreNamedNotScattered()
    {
        // رقمٌ سحريّ في ثلاثة مواضع يتباعد عند أول تعديل — والقاعدة تعيش هنا وحدها.
        Assert.Equal(3, TaskEscalation.ManagersThresholdDays);
        Assert.Equal(7, TaskEscalation.PresidencyThresholdDays);
        Assert.Equal(2, TaskEscalation.LevelFor(TaskEscalation.ManagersThresholdDays));
        Assert.Equal(3, TaskEscalation.LevelFor(TaskEscalation.PresidencyThresholdDays));
    }

    [Fact]
    public void EveryLevelHasAnArabicTitle()
    {
        for (var level = 1; level <= 3; level++)
        {
            var title = TaskEscalation.TitleFor(level);
            Assert.False(string.IsNullOrWhiteSpace(title));
            Assert.Contains("متأخرة", title);
        }

        // والمستويان الأعلى يُميَّزان عن الأول — فمن يقرأ العنوان يعرف مدى الأمر.
        Assert.NotEqual(TaskEscalation.TitleFor(1), TaskEscalation.TitleFor(2));
        Assert.NotEqual(TaskEscalation.TitleFor(2), TaskEscalation.TitleFor(3));
    }

    [Fact]
    public void DedupKeysDifferPerLevel_SoEachLevelGetsItsOwnNotification()
    {
        // مفتاحٌ واحد لكل المستويات كان يبتلع التصعيد الثاني والثالث — **فلا يعلم المدير**.
        var l1 = NotificationKeys.TaskEscalation(42, 1);
        var l2 = NotificationKeys.TaskEscalation(42, 2);
        var l3 = NotificationKeys.TaskEscalation(42, 3);

        Assert.Equal(3, new[] { l1, l2, l3 }.Distinct().Count());

        // ومفاتيح مهمّتين مختلفتين لا تتصادم.
        Assert.NotEqual(NotificationKeys.TaskEscalation(42, 1),
                        NotificationKeys.TaskEscalation(43, 1));
    }
}
