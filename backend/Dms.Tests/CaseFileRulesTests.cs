using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس قواعد **المعاملة** (ADR-045).
/// </summary>
/// <remarks>
/// ⚠️ **موضعُ القواعد في `Dms.Domain` شرطُ وجود هذا الملفّ**: مشروع الاختبارات يشير إلى
/// المجال والمستندات **فقط** — فقاعدةٌ تُكتب داخل `CaseFileService` لا تُختبر أبداً.
/// </remarks>
public class CaseFileRulesTests
{
    // ─────────────────────────── العنوان ───────────────────────────

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("ab")]        // حرفان — دون الحدّ
    [InlineData("  a  ")]     // يُقلَّم قبل القياس
    public void ShortOrEmptyTitles_AreRejected(string? title)
    {
        var ex = Assert.Throws<ValidationException>(() => CaseFileRules.EnsureTitle(title));

        // الرسالة تقول **لماذا** يُطلب العنوان لا «حقل مطلوب» مجرّدة.
        Assert.Contains("عنوان المعاملة", ex.Message);
        Assert.Contains("القوائم", ex.Message);
    }

    [Fact]
    public void ValidTitle_IsTrimmed()
        => Assert.Equal("مناقصة المجاري", CaseFileRules.EnsureTitle("  مناقصة المجاري  "));

    [Fact]
    public void OverlongTitle_IsRejected_MirroringTheColumn()
    {
        // ⚠️ الحدّ مرآةُ عمود القاعدة — ورفضُه هنا يعطي رسالةً عربية بدل خطأ قصٍّ من SQL.
        var ex = Assert.Throws<ValidationException>(
            () => CaseFileRules.EnsureTitle(new string('م', CaseFileRules.MaxTitleLength + 1)));
        Assert.Contains($"{CaseFileRules.MaxTitleLength}", ex.Message);
    }

    [Fact]
    public void TitleAtExactlyTheLimit_IsAccepted()
    {
        // حارسُ الحافّة: `>` لا `>=` — وخطأٌ بواحد هنا يرفض عنواناً سليماً.
        var t = new string('م', CaseFileRules.MaxTitleLength);
        Assert.Equal(t, CaseFileRules.EnsureTitle(t));
    }

    // ─────────────────────────── الضمّ ───────────────────────────

    [Theory]
    [InlineData(IncomingStatus.New)]
    [InlineData(IncomingStatus.InReview)]
    [InlineData(IncomingStatus.Replied)]
    [InlineData(IncomingStatus.Closed)]
    [InlineData(IncomingStatus.Archived)]   // 🔴 قرار المالك — وهو نصفُ قيمة الميزة
    public void EveryStatusCanJoinACaseFile(IncomingStatus status)
        => Assert.True(CaseFileRules.CanJoin(status));

    [Fact]
    public void JoiningIsWiderThanLinkingAReply_BecauseOneIsASignalAndTheOtherAnAction()
    {
        // 🔴 **الفرق المقصود**: الضمّ **إشارة** لا تمسّ حالةً ولا رقماً، فيُقبل على المؤرشف؛
        //    وربطُ الردّ **إجراءٌ يغيّر حالة السجلّ الرسميّ** فيُرفض عليه.
        //    وتوحيدُهما «تبسيطاً» يُسقط أحد المعنيين.
        Assert.True(CaseFileRules.CanJoin(IncomingStatus.Archived));
        Assert.False(BookReplyRules.CanLink(IncomingStatus.Archived));
    }

    // ─────────────────────────── الدمج ───────────────────────────

    [Fact]
    public void MergingACaseFileWithItself_IsRejected()
    {
        // 🔴 أخطرُ حالةٍ في العملية كلّها: «انقل ثم احذف المصدر» على السجلّ نفسه يُفرغه
        //    **بعد** أن نقل كتبه إليه ⇒ تخرج كلُّها بلا معاملة **والخيط يختفي بلا أثر**.
        var ex = Assert.Throws<ValidationException>(
            () => CaseFileRules.EnsureCanMerge(7, 7, 3, 3, 3, 3));
        Assert.Contains("بنفسها", ex.Message);
    }

    [Fact]
    public void MergingIsAllowed_WhenTheActorSeesEveryBookInBoth()
        => CaseFileRules.EnsureCanMerge(1, 2, sourceVisible: 3, sourceTotal: 3, targetVisible: 4, targetTotal: 4);

    [Theory]
    [InlineData(2, 3, 4, 4)]   // المصدر فيه محجوب
    [InlineData(3, 3, 2, 4)]   // الهدف فيه محجوب
    [InlineData(1, 3, 1, 4)]   // كلاهما
    public void MergingIsRejected_WhenAnyBookIsHidden(
        int sourceVisible, int sourceTotal, int targetVisible, int targetTotal)
    {
        // 🔐 مَن يرى ٣ من ٥ لا يملك أن يقرّر مصير الخمسة. والحارس **بالعدد لا بالهويّة**،
        //    فلا يُسمّى له كتابٌ محجوب ولا يُكشف وجودُ واحدٍ بعينه.
        var ex = Assert.Throws<ForbiddenException>(() => CaseFileRules.EnsureCanMerge(
            1, 2, sourceVisible, sourceTotal, targetVisible, targetTotal));
        Assert.Contains("خارج صلاحيتك", ex.Message);
    }

    [Fact]
    public void SelfMergeIsCheckedBeforeVisibility_SoTheWorstCaseNeverSlipsThrough()
    {
        // ⚠️ ترتيبُ الفحصين ليس تفصيلاً: لو قُدّم فحص الرؤية لَمرّ دمجُ معاملةٍ بنفسها
        //    كلّما كان صاحبها يرى كتبها كلَّها — وهي الحالة **الشائعة** لا النادرة.
        Assert.Throws<ValidationException>(
            () => CaseFileRules.EnsureCanMerge(5, 5, sourceVisible: 0, sourceTotal: 9,
                targetVisible: 0, targetTotal: 9));
    }

    // ─────────────────────────── الطيّ ───────────────────────────

    [Fact]
    public void EmptyCaseFile_IsRetired()
        => Assert.True(CaseFileRules.ShouldRetire(0));

    [Theory]
    [InlineData(1)]
    [InlineData(5)]
    public void CaseFileWithBooks_IsKept(int remaining)
        => Assert.False(CaseFileRules.ShouldRetire(remaining));
}
