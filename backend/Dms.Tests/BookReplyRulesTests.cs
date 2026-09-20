using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس قواعد ربط الردّ (ADR-045) — كثيرٌ إلى كثير بين الوارد والصادر.
/// </summary>
/// <remarks>
/// ⚠️ **سبب وجودها:** القاعدتان هنا وُلدتا من كسرِ افتراضين في العمل الفعليّ — صادرٌ واحد
/// أجاب ثلاثة واردات، وواردٌ يُجاب بردٍّ أوّليّ ثم نهائيّ. وكلُّ حالةٍ حدّية أدناه **وقعت
/// في التحليل قبل الكتابة** لا اختُرعت.
/// </remarks>
public class BookReplyRulesTests
{
    // ─────────────────────────── CanLink ───────────────────────────

    [Theory]
    [InlineData(IncomingStatus.New)]        // لم يُراجَع بعد — والردّ الفوريّ وارد
    [InlineData(IncomingStatus.InReview)]   // الحالة الشائعة
    [InlineData(IncomingStatus.Replied)]    // 🔴 الردّ الثاني: أوّليّ ثم نهائيّ
    public void CanLink_AllowsBooksStillInProcess(IncomingStatus status)
        => Assert.True(BookReplyRules.CanLink(status));

    [Theory]
    [InlineData(IncomingStatus.Closed)]     // الإغلاق قرارٌ مستقلّ استقرّ
    [InlineData(IncomingStatus.Archived)]   // سجلٌّ رسميّ مغلق
    public void CanLink_RejectsSettledBooks(IncomingStatus status)
        => Assert.False(BookReplyRules.CanLink(status));

    [Fact]
    public void CanLink_IsWiderThanIsOperable_ByRepliedExactly()
    {
        // 🔴 **الحارس الذي يمنع «التبسيط» الخاطئ**: مَن يرى القاعدتين متشابهتين قد يوحّدهما،
        //    فينفتح بابُ **الإحالة** على كتابٍ مُجابٍ عنه — وهي قاعدةٌ لم تتغيّر.
        //    فيُثبَّت هنا أن الفرق بينهما **حالةٌ واحدة بعينها لا أكثر ولا أقلّ**.
        var difference = Enum.GetValues<IncomingStatus>()
            .Where(s => BookReplyRules.CanLink(s) != IncomingWorkflow.IsOperable(s))
            .ToArray();

        Assert.Equal(new[] { IncomingStatus.Replied }, difference);
    }

    [Fact]
    public void CanLink_CoversEveryEnumValue_SoANewStatusCannotSlipThrough()
    {
        // حارسُ «كل قيمة في الـenum»: حالةٌ جديدة تُضاف غداً يجب أن يُبتّ فيها هنا بوعي،
        // لا أن ترث `false` صامتةً من تعبيرٍ لا يذكرها.
        var known = new[]
        {
            IncomingStatus.New, IncomingStatus.InReview, IncomingStatus.Replied,
            IncomingStatus.Closed, IncomingStatus.Archived,
        };
        Assert.Equal(known.Length, Enum.GetValues<IncomingStatus>().Length);
    }

    // ─────────────────── StatusAfterUnlink ───────────────────

    [Fact]
    public void RemainingReply_KeepsRepliedStatus()
    {
        // ① واردٌ له ردّان فُكّ أحدهما ما زال مردوداً عليه. وتنزيلُه يكذب على القارئ
        //    **ويُبطل حارسَ الملاحظة الإلزامية** في تغيير الحالة.
        var after = BookReplyRules.StatusAfterUnlink(
            IncomingStatus.Replied, remainingReplies: 1,
            hasAssignments: true, becameRepliedByLink: true);

        Assert.Equal(IncomingStatus.Replied, after);
    }

    [Fact]
    public void LastReplyRemoved_ReturnsToInReview_WhenBookWasForwarded()
    {
        var after = BookReplyRules.StatusAfterUnlink(
            IncomingStatus.Replied, remainingReplies: 0,
            hasAssignments: true, becameRepliedByLink: true);

        Assert.Equal(IncomingStatus.InReview, after);
    }

    [Fact]
    public void LastReplyRemoved_ReturnsToNew_WhenBookWasNeverForwarded()
    {
        // ③ 🔴 العودةُ الثابتة إلى «قيد المراجعة» كانت تُرقّي كتاباً **لم يمرّ على قسمٍ قطّ**
        //    إلى حالةٍ لم يبلغها بأيّ طريق — عيبٌ كان قائماً في المسار المفرد.
        var after = BookReplyRules.StatusAfterUnlink(
            IncomingStatus.Replied, remainingReplies: 0,
            hasAssignments: false, becameRepliedByLink: true);

        Assert.Equal(IncomingStatus.New, after);
    }

    [Fact]
    public void ManuallyMarkedReplied_IsNeverDowngraded_SoThePaperTrailSurvives()
    {
        // ② 🔴 مَن وضع «تم الرد» يدوياً بملاحظةٍ إلزامية وثّق **ردّاً ورقياً خارج النظام**.
        //    فلو رُبط ردّ ثم فُكّ لهبطت الحالة **وضاع التوثيق** الذي فرضه الحارس أصلاً.
        var after = BookReplyRules.StatusAfterUnlink(
            IncomingStatus.Replied, remainingReplies: 0,
            hasAssignments: true, becameRepliedByLink: false);

        Assert.Equal(IncomingStatus.Replied, after);
    }

    [Theory]
    [InlineData(IncomingStatus.Closed)]
    [InlineData(IncomingStatus.Archived)]
    [InlineData(IncomingStatus.New)]
    [InlineData(IncomingStatus.InReview)]
    public void NonRepliedStatuses_AreNeverTouchedByUnlinking(IncomingStatus status)
    {
        // الإغلاق والأرشفة قراراتٌ مستقلّة عن الربط — وفكُّ ردٍّ لا ينقض قراراً آخر.
        var after = BookReplyRules.StatusAfterUnlink(
            status, remainingReplies: 0, hasAssignments: true, becameRepliedByLink: true);

        Assert.Equal(status, after);
    }

    [Fact]
    public void EveryFlagActuallyChangesTheOutcome_SoNoGuardIsDecorative()
    {
        // 🔴 **الحارس السلبيّ**: لو أُهمل أيّ مُدخَلٍ في التطبيق لمرّت الاختبارات أعلاه
        //    وهي تقيس قاعدةً منقوصة. هنا نُثبت أن **لكلٍّ من الثلاثة أثراً يقلب النتيجة**.
        const IncomingStatus replied = IncomingStatus.Replied;

        // remainingReplies يقلب
        Assert.NotEqual(
            BookReplyRules.StatusAfterUnlink(replied, 0, true, true),
            BookReplyRules.StatusAfterUnlink(replied, 1, true, true));

        // hasAssignments يقلب
        Assert.NotEqual(
            BookReplyRules.StatusAfterUnlink(replied, 0, true, true),
            BookReplyRules.StatusAfterUnlink(replied, 0, false, true));

        // becameRepliedByLink يقلب
        Assert.NotEqual(
            BookReplyRules.StatusAfterUnlink(replied, 0, true, true),
            BookReplyRules.StatusAfterUnlink(replied, 0, true, false));
    }
}
