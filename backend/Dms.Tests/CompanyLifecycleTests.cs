using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس دورة حياة الشركة (ADR-047) — **وُلدت كلُّها من حادثةٍ وقعت 2026-09-21**:
/// بابان مغلقان بلا سببٍ مفهوم، فذهب المالك إلى زرّ تصفير القاعدة.
/// </summary>
public class CompanyLifecycleTests
{
    private static CompanyContents Contents(
        int liveOut = 0, int deadOut = 0, int liveIn = 0, int deadIn = 0,
        int archive = 0, int employees = 0, int tasks = 0, int cases = 0, int sole = 0)
        => new(liveOut, deadOut, liveIn, deadIn, archive, employees, tasks, cases,
               Users: 0, SoleCompanyUsers: sole, Departments: 0, Entities: 0, Templates: 0);

    // ─────────────────────── التعطيل ───────────────────────

    [Fact]
    public void Deactivate_Allowed_WhenNoOneDependsOnIt()
        => Assert.Equal(CompanyBlockReason.None, CompanyLifecycle.CanDeactivate(0));

    [Fact]
    public void Deactivate_Blocked_WhenSomeoneHasNoOtherCompany()
    {
        // 🔴 تعطيلُها يُخرجها من رمز المستخدم ⇒ بلا شركةٍ فعّالة ⇒ **لا يرى شيئاً ولا
        //    رسالةَ تشرح**. والحارس وجوديّ لا تجميليّ.
        Assert.Equal(CompanyBlockReason.SoleCompanyUsers, CompanyLifecycle.CanDeactivate(1));
        Assert.Equal(CompanyBlockReason.SoleCompanyUsers, CompanyLifecycle.CanDeactivate(9));
    }

    // ─────────────────────── الحذف: العطل المُبلَّغ عنه ───────────────────────

    [Fact]
    public void Delete_Allowed_WhenOnlySoftDeletedRecordsRemain()
    {
        // 🔴 **هذا بعينه بلاغُ المالك**: أنشأ شركةً وصادراً واعتمده، ثم حذف الصادر —
        //    فبقي الحذف ممنوعاً لأن الحارس القديم كان يعدّ المحذوف.
        //    وقرارُ المالك (2026-09-21): **المحذوف ناعماً لا يمنع**.
        var c = Contents(liveOut: 0, deadOut: 3, deadIn: 2);

        var r = CompanyLifecycle.CanDelete(
            isEnabled: false, isActiveCompany: false, isLastCompany: false,
            contents: c, name: "شركة التجربة", confirmation: "شركة التجربة");

        Assert.Equal(CompanyBlockReason.None, r);
        Assert.Equal(0, c.LiveRecords);
        Assert.Equal(5, c.WillBeErased);   // ⚠️ ويُعلَن أنه سيُمحى فعلياً
    }

    [Theory]
    [InlineData(1, 0, 0, 0, 0, 0)]   // صادر حيّ
    [InlineData(0, 1, 0, 0, 0, 0)]   // وارد حيّ
    [InlineData(0, 0, 1, 0, 0, 0)]   // أرشيف
    [InlineData(0, 0, 0, 1, 0, 0)]   // موظف
    [InlineData(0, 0, 0, 0, 1, 0)]   // مهمة
    [InlineData(0, 0, 0, 0, 0, 1)]   // معاملة
    public void Delete_Blocked_ByAnyLiveRecord(int o, int i, int a, int e, int t, int cf)
    {
        // ⚠️ **الستّة كلُّها تمنع** — لا الكتب وحدها: شركةٌ فيها موظفٌ ليست «فارغة».
        var c = Contents(liveOut: o, liveIn: i, archive: a, employees: e, tasks: t, cases: cf);

        var r = CompanyLifecycle.CanDelete(false, false, false, c, "س", "س");

        Assert.Equal(CompanyBlockReason.HasLiveRecords, r);
    }

    // ─────────────────────── طبقات الأمان الأربع ───────────────────────

    [Fact]
    public void Delete_Blocked_WhileStillEnabled()
    {
        // 🔴 **خطوتان لا واحدة** — فلا تقع بضغطةٍ خاطئة.
        var r = CompanyLifecycle.CanDelete(
            isEnabled: true, isActiveCompany: false, isLastCompany: false,
            Contents(), "س", "س");

        Assert.Equal(CompanyBlockReason.StillEnabled, r);
    }

    [Fact]
    public void Delete_Blocked_WhenItIsTheActiveCompany()
        => Assert.Equal(CompanyBlockReason.IsActiveCompany,
            CompanyLifecycle.CanDelete(false, true, false, Contents(), "س", "س"));

    [Fact]
    public void Delete_Blocked_WhenItIsTheLastCompany()
        => Assert.Equal(CompanyBlockReason.LastCompany,
            CompanyLifecycle.CanDelete(false, false, true, Contents(), "س", "س"));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("شركة")]
    [InlineData("شركة التجربةX")]
    public void Delete_Blocked_WhenConfirmationDoesNotMatch(string? confirmation)
        => Assert.Equal(CompanyBlockReason.BadConfirmation,
            CompanyLifecycle.CanDelete(false, false, false, Contents(), "شركة التجربة", confirmation));

    [Fact]
    public void Delete_Confirmation_IgnoresSurroundingWhitespace()
    {
        // ⚠️ مسافةٌ لاصقة من اللصق كانت تُفشل مستخدماً كتب الاسم صحيحاً.
        Assert.Equal(CompanyBlockReason.None,
            CompanyLifecycle.CanDelete(false, false, false, Contents(), "شركة التجربة", "  شركة التجربة  "));
    }

    // ─────────────────────── ترتيب الفحص ───────────────────────

    [Fact]
    public void Delete_ChecksCheapReasonsBeforeContents()
    {
        // 🔑 **الترتيب معلومة**: شركةٌ مفعَّلة وفيها سجلّات ⇒ تُقال له «عطّلها أولاً»
        //    لا «فيها 3 سجلّات» — فيفهم الخطوة التالية من أوّل رسالة.
        var c = Contents(liveOut: 3);

        var r = CompanyLifecycle.CanDelete(
            isEnabled: true, isActiveCompany: true, isLastCompany: true, c, "س", "لا يطابق");

        Assert.Equal(CompanyBlockReason.StillEnabled, r);
    }

    [Fact]
    public void Delete_ChecksConfirmationLast()
    {
        // 🔴 طلبُ الكتابة قبل التأكّد من الجواز يجعل المستخدم يكتب ثم يُرفض،
        //    فيظنّ أن **الكتابة** هي المشكلة.
        var r = CompanyLifecycle.CanDelete(false, false, false, Contents(liveOut: 1), "س", "لا يطابق");

        Assert.Equal(CompanyBlockReason.HasLiveRecords, r);
    }

    // ─────────────────────── الرسائل ───────────────────────

    [Theory]
    [InlineData(CompanyBlockReason.SoleCompanyUsers)]
    [InlineData(CompanyBlockReason.StillEnabled)]
    [InlineData(CompanyBlockReason.IsActiveCompany)]
    [InlineData(CompanyBlockReason.LastCompany)]
    [InlineData(CompanyBlockReason.HasLiveRecords)]
    [InlineData(CompanyBlockReason.BadConfirmation)]
    public void Explain_NeverReturnsEmpty_ForARealBlock(CompanyBlockReason reason)
    {
        // 🔑 **رسالةٌ فارغة تعني رفضاً بلا سبب** — وهو ما يدفع المستخدم إلى مخرجٍ ثالث.
        var msg = CompanyLifecycle.Explain(reason, "شركة التجربة", Contents(liveOut: 2, sole: 1));
        Assert.False(string.IsNullOrWhiteSpace(msg));
    }

    [Fact]
    public void Explain_NamesTheCompany_AndTheNextStep()
    {
        var msg = CompanyLifecycle.Explain(
            CompanyBlockReason.StillEnabled, "شركة التجربة", Contents());

        Assert.Contains("شركة التجربة", msg);
        Assert.Contains("عطّل", msg);        // ⚠️ كلُّ رسالةٍ تنتهي بالخطوة التالية
    }

    [Fact]
    public void Explain_ListsWhatIsActuallyThere()
    {
        var msg = CompanyLifecycle.Explain(
            CompanyBlockReason.HasLiveRecords, "س",
            Contents(liveOut: 2, liveIn: 1, employees: 3));

        Assert.Contains("2 صادر", msg);
        Assert.Contains("1 وارد", msg);
        Assert.Contains("3 موظف", msg);
        Assert.DoesNotContain("أرشيف", msg);   // ما ليس فيها لا يُذكر
    }

    [Fact]
    public void Explain_ReturnsEmpty_WhenNothingBlocks()
        => Assert.Equal(string.Empty, CompanyLifecycle.Explain(CompanyBlockReason.None, "س", Contents()));
}
