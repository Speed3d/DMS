using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس «متى يلزم سبب؟» (ADR-037، بقرار المالك 2026-09-06).
/// </summary>
public class TaskChangeReasonTests
{
    private static readonly DateTime Due = new(2026, 9, 20);

    private static bool Edit(
        string oldTitle = "عنوان", string newTitle = "عنوان",
        DateTime? oldDue = null, DateTime? newDue = null,
        DmsTaskPriority oldP = DmsTaskPriority.Normal, DmsTaskPriority newP = DmsTaskPriority.Normal,
        int? oldDep = null, int? newDep = null)
        => TaskChangeReason.EditNeedsReason(
            oldTitle, newTitle, oldDue ?? Due, newDue ?? Due, oldP, newP, oldDep, newDep);

    [Fact]
    public void EditingWhatOthersRead_NeedsAReason()
    {
        // العنوان يُقرأ في القوائم والتقارير · والموعد يحكم التأخّر والتصعيد ·
        // والأولوية تحكم الترتيب · والقسم **يحكم مَن يرى**.
        Assert.True(Edit(newTitle: "عنوانٌ آخر"));
        Assert.True(Edit(newDue: Due.AddDays(3)));
        Assert.True(Edit(newP: DmsTaskPriority.Urgent));
        Assert.True(Edit(oldDep: 1, newDep: 2));
        Assert.True(Edit(oldDep: null, newDep: 2));
        Assert.True(Edit(oldDep: 2, newDep: null));
    }

    [Fact]
    public void EditingOnlyYourOwnDetail_DoesNot()
    {
        // 🔴 **قرار المالك**: تصحيحُ إملاءٍ في الوصف أو الملاحظات يمرّ بلا سؤال. واشتراطُ
        //    تعليلٍ لكل حرفٍ يدفع الناس إلى كتابة «تعديل» — **فيصير الحقل شكليّاً، وحقلٌ
        //    شكليّ أسوأ من غيابه** لأنه يوهم القارئ أن ثمّة تعليلاً.
        Assert.False(Edit());
    }

    [Fact]
    public void WhitespaceOnlyTitleChange_IsNotAChange()
    {
        // مسافةٌ زائدة ليست تعديلاً يمسّ أحداً — ولا تستحقّ حواريّة سبب.
        Assert.False(Edit(oldTitle: "عنوان", newTitle: "  عنوان  "));
    }

    [Fact]
    public void SameDayDifferentTime_IsNotADateChange()
    {
        // الموعد **يومٌ لا لحظة** — واختلافُ الساعة ليس تغييراً في الموعد.
        Assert.False(Edit(oldDue: Due, newDue: Due.AddHours(9)));
    }

    [Fact]
    public void ProgressGoingBackwards_NeedsAReason()
    {
        // 🔴 من رفع النسبة إلى 75% أعلن إنجازاً، ومن أعادها إلى 25% **نقض إعلاناً سابقاً**.
        Assert.True(TaskChangeReason.ProgressNeedsReason(75, 25));
        Assert.True(TaskChangeReason.ProgressNeedsReason(100, 99));
        Assert.True(TaskChangeReason.ProgressNeedsReason(1, 0));
    }

    [Fact]
    public void ProgressGoingForwardOrStayingPut_DoesNot()
    {
        Assert.False(TaskChangeReason.ProgressNeedsReason(25, 75));
        Assert.False(TaskChangeReason.ProgressNeedsReason(0, 0));
        // ⚠️ المساواة ليست تراجعاً — إعادةُ الضبط على القيمة نفسها لا تُنقص شيئاً.
        Assert.False(TaskChangeReason.ProgressNeedsReason(50, 50));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("قصير")]      // أربعة أحرف
    [InlineData("  ابc  ")]   // يُقلَّم قبل القياس
    public void ShortOrEmptyReasons_AreRejected(string? reason)
    {
        var ex = Assert.Throws<ValidationException>(
            () => TaskChangeReason.EnsureReason(reason, "تعديل المهمة"));

        // الرسالة تسمّي الفعل **وتقول لماذا يُطلب** — لا «حقل مطلوب» مجرّدة.
        Assert.Contains("تعديل المهمة", ex.Message);
        Assert.Contains("سجلّ المهمة", ex.Message);
    }

    [Fact]
    public void AReasonOfFiveCharactersOrMore_Passes()
    {
        TaskChangeReason.EnsureReason("تأجيل", "تعديل المهمة");           // خمسة
        TaskChangeReason.EnsureReason("انكشف عملٌ ناقص", "تقليل النسبة");
    }

    [Fact]
    public void MinLength_MatchesTheRepositoryPrecedent()
    {
        // نظير سبب فكّ الأرشفة (ADR-021) وتعديل الشهر المُسدَّد (ADR-026) — خمسة أحرف.
        Assert.Equal(5, TaskChangeReason.MinLength);
    }
}
