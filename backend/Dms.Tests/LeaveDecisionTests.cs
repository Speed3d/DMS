using Dms.Domain;
using Xunit;

/// <summary>
/// حرّاس قواعد الإجازة الذاتيّة والبتّ فيها (ADR-033).
///
/// ⚠️ **سبب وجودها:** الطلب الذاتيّ يصل بـ<c>DeductFromSalary = false</c> **كغيابِ قرار
/// لا كقرار**، والفرق لا يظهر في نوع البيانات. فلو مرّ الافتراض صامتاً عند الموافقة
/// لاحتُسبت إجازةُ شهرٍ بلا راتب **مدفوعةً** — وهو عطل ADR-028 نفسه بثوبٍ آخر.
/// </summary>
public class LeaveDecisionTests
{
    // ─────────────── قرار الحسم ───────────────

    /// <summary>🔴 **الحارس الأهمّ**: `null` تُبقي المسجَّل ولا تكتب `false`.</summary>
    /// <remarks>
    /// لو كتبت `false` لانقلب قرارُ كاتب الشؤون «تُحسم» إلى «بلا حسم» صامتاً كلَّما
    /// وافق مراجعٌ من عميلٍ قديم لا يرسل الحقل — أي **مالٌ يُدفع بلا استحقاق**.
    /// </remarks>
    [Theory]
    [InlineData(true, true)]
    [InlineData(false, false)]
    public void غيابُ_قرار_المراجع_يُبقي_المسجَّل_كما_هو(bool current, bool expected)
    {
        Assert.Equal(expected, LeaveDecision.ResolveDeduction(
            approve: true, reviewerDecision: null, current: current));
    }

    [Theory]
    [InlineData(true, false, true)]    // قرارٌ صريح «تُحسم» فوق مسجَّلٍ «بلا حسم»
    [InlineData(false, true, false)]   // وقرارٌ صريح «بلا حسم» فوق مسجَّلٍ «تُحسم»
    public void قرارُ_المراجع_الصريح_يُكتب(bool decision, bool current, bool expected)
    {
        Assert.Equal(expected, LeaveDecision.ResolveDeduction(
            approve: true, reviewerDecision: decision, current: current));
    }

    /// <summary>الرفض لا يمسّ الحسم — إجازةٌ مرفوضة لم تقع، فلا قرارَ في شأنها.</summary>
    [Theory]
    [InlineData(null, true, true)]
    [InlineData(null, false, false)]
    [InlineData(true, false, false)]   // ولو أرسل المراجع قراراً مع الرفض، يُهمَل
    [InlineData(false, true, true)]
    public void الرفضُ_لا_يمسّ_الحسم(bool? decision, bool current, bool expected)
    {
        Assert.Equal(expected, LeaveDecision.ResolveDeduction(
            approve: false, reviewerDecision: decision, current: current));
    }

    // ─────────────── سحب الطلب ───────────────

    /// <summary>الذاتيّ المعلّق وحده يُسحب — والشرطان معاً لا أحدهما.</summary>
    [Theory]
    [InlineData(true, LeaveStatus.Pending, true)]
    [InlineData(true, LeaveStatus.Approved, false)]   // بُني عليها كشفُ الشهر
    [InlineData(true, LeaveStatus.Rejected, false)]   // محوُها إعادةُ فتحٍ بالباب الخلفي
    [InlineData(false, LeaveStatus.Pending, false)]   // 🔴 سجّلها كاتب الشؤون — واقعةٌ لا طلب
    [InlineData(false, LeaveStatus.Approved, false)]
    [InlineData(false, LeaveStatus.Rejected, false)]
    public void السحبُ_للذاتيّ_المعلّق_وحده(
        bool isSelf, LeaveStatus status, bool expected)
    {
        Assert.Equal(expected, LeaveDecision.CanSelfCancel(isSelf, status));
    }

    /// <summary>
    /// 🔴 **سؤال «تُحسم؟» يطابق شرطَ السحب حرفياً** — وهذا الحارس يمنع تباعدهما.
    /// </summary>
    /// <remarks>
    /// لو انفصل الشرطان لظهرت حالةٌ يُسأل فيها المراجع عن سطرٍ جاء بقراره (فيُغيّره بلا
    /// قصد)، أو لا يُسأل عن سطرٍ جاء بلا قرار (فيمرّ الافتراض صامتاً).
    /// </remarks>
    [Theory]
    [InlineData(true, LeaveStatus.Pending)]
    [InlineData(true, LeaveStatus.Approved)]
    [InlineData(false, LeaveStatus.Pending)]
    [InlineData(false, LeaveStatus.Rejected)]
    public void سؤالُ_الحسم_يطابق_شرطَ_السحب(bool isSelf, LeaveStatus status)
    {
        Assert.Equal(
            LeaveDecision.CanSelfCancel(isSelf, status),
            LeaveDecision.NeedsDeductionDecision(isSelf, status));
    }

    /// <summary>الطلب الذاتيّ معلّقٌ دائماً — لا يمنح صاحبه نفسه إجازةً مقبولة.</summary>
    [Fact]
    public void الطلبُ_الذاتيّ_يبدأ_معلّقاً_دائماً()
    {
        Assert.Equal(LeaveStatus.Pending, LeaveDecision.SelfRequestStatus);
    }
}
