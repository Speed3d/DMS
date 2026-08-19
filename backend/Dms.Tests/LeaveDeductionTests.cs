using Dms.Domain;
using Xunit;

/// <summary>
/// حرّاس قاعدة نسبة أيام الإجازة إلى الشهر (ADR-036).
///
/// ⚠️ **سبب وجودها:** الإجازة مدًى والكشف شهر، والمدى يعبُر الشهرين. والقرار
/// (**تُقسَم بالأيام**) **مالٌ يُنقص من راتب**، فخطأُ يومٍ واحد خطأُ مبلغ.
/// </summary>
public class LeaveDeductionTests
{
    // ─────────────── التقسيم بالأيام ───────────────

    /// <summary>🔴 **الحارس الأهمّ**: مثال المالك حرفياً — ٢٨ آب ← ٣ أيلول.</summary>
    /// <remarks>
    /// أربعة أيام في آب (٢٨·٢٩·٣٠·٣١) وثلاثة في أيلول (١·٢·٣) — ومجموعها **سبعة**،
    /// أي أن التقسيم لا يخلق يوماً ولا يبتلعه.
    /// </remarks>
    [Fact]
    public void إجازةٌ_تعبُر_شهرين_تُقسَم_بالأيام_بلا_زيادةٍ_ولا_نقص()
    {
        var from = new DateTime(2026, 8, 28);
        var to = new DateTime(2026, 9, 3);

        var august = LeaveDeduction.DaysInMonth(from, to, 2026, 8);
        var september = LeaveDeduction.DaysInMonth(from, to, 2026, 9);

        Assert.Equal(4, august);
        Assert.Equal(3, september);
        Assert.Equal(7, august + september);
    }

    [Fact]
    public void إجازةٌ_داخل_الشهر_كلُّها_له_شاملةً_الطرفين()
        => Assert.Equal(3, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 10), new DateTime(2026, 4, 12), 2026, 4));

    [Fact]
    public void إجازةُ_يومٍ_واحد_يومٌ_واحد()
        => Assert.Equal(1, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 10), new DateTime(2026, 4, 10), 2026, 4));

    [Fact]
    public void إجازةٌ_لا_تمسّ_الشهر_تُعيد_صفراً()
    {
        var from = new DateTime(2026, 4, 10);
        var to = new DateTime(2026, 4, 12);
        Assert.Equal(0, LeaveDeduction.DaysInMonth(from, to, 2026, 3));
        Assert.Equal(0, LeaveDeduction.DaysInMonth(from, to, 2026, 5));
        Assert.Equal(0, LeaveDeduction.DaysInMonth(from, to, 2025, 4));
    }

    /// <summary>شباط لا يُستثنى — الطول يأتي من التقويم لا من رقمٍ مكتوب.</summary>
    [Fact]
    public void شباط_يأخذ_طوله_الحقيقي()
    {
        // 2026 ليست كبيسة ⇒ شباط 28 يوماً.
        Assert.Equal(28, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 1, 20), new DateTime(2026, 3, 5), 2026, 2));
        // 2024 كبيسة ⇒ 29.
        Assert.Equal(29, LeaveDeduction.DaysInMonth(
            new DateTime(2024, 1, 20), new DateTime(2024, 3, 5), 2024, 2));
    }

    /// <summary>إجازةٌ تبتلع الشهر كلَّه ⇒ أيام الشهر كلها.</summary>
    [Fact]
    public void إجازةٌ_تغطّي_الشهر_كلَّه()
        => Assert.Equal(30, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 3, 15), new DateTime(2026, 5, 10), 2026, 4));

    /// <summary>⚠️ **الوقت لا يُغيّر اليوم**: تسجيلٌ في الحادية عشرة ليلاً يبقى يومه.</summary>
    [Fact]
    public void ساعةُ_التسجيل_لا_تُزحزح_اليوم()
        => Assert.Equal(2, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 10, 23, 30, 0), new DateTime(2026, 4, 11, 0, 15, 0), 2026, 4));

    [Fact]
    public void مدًى_معكوس_أو_شهرٌ_خارج_النطاق_يُعيد_صفراً()
    {
        Assert.Equal(0, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 12), new DateTime(2026, 4, 10), 2026, 4));
        Assert.Equal(0, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 10), new DateTime(2026, 4, 12), 2026, 13));
        Assert.Equal(0, LeaveDeduction.DaysInMonth(
            new DateTime(2026, 4, 10), new DateTime(2026, 4, 12), 2026, 0));
    }

    // ─────────────── قاعدة الظهور والترحيل ───────────────

    [Fact]
    public void إجازةُ_الشهر_نفسه_تظهر_دائماً()
    {
        Assert.True(LeaveDeduction.ShowsInSheet(2026, 4, 2026, 4, leaveMonthIsPaid: false));
        Assert.True(LeaveDeduction.ShowsInSheet(2026, 4, 2026, 4, leaveMonthIsPaid: true));
    }

    /// <summary>
    /// 🔴 **الحارس الذي يمنع الحسم من الشهر الخطأ**: ما دام كشف آب مسودّةً، لا تظهر
    /// إجازةُ آب في كشف أيلول — تُعالَج في شهرها.
    /// </summary>
    [Fact]
    public void إجازةُ_شهرٍ_مفتوح_لا_تُرحَّل()
        => Assert.False(LeaveDeduction.ShowsInSheet(2026, 8, 2026, 9, leaveMonthIsPaid: false));

    /// <summary>🔴 **قرار المالك الثالث**: إن أُقفل شهرُها بالتسديد تُرحَّل ولا تضيع.</summary>
    [Fact]
    public void إجازةُ_شهرٍ_مُسدَّد_تُرحَّل_إلى_الكشف_التالي()
        => Assert.True(LeaveDeduction.ShowsInSheet(2026, 4, 2026, 5, leaveMonthIsPaid: true));

    /// <summary>وتبقى ظاهرةً في الأشهر التالية حتى يُبتّ فيها — لا تسقط بمرور شهر.</summary>
    [Fact]
    public void المُرحَّلة_تبقى_ظاهرةً_حتى_يُبتّ_فيها()
        => Assert.True(LeaveDeduction.ShowsInSheet(2026, 4, 2026, 7, leaveMonthIsPaid: true));

    /// <summary>⚠️ **ولا تُرحَّل إلى الماضي**: إجازةُ أيلول لا تظهر في كشف آب.</summary>
    [Fact]
    public void لا_ترحيلَ_إلى_شهرٍ_سابق()
    {
        Assert.False(LeaveDeduction.ShowsInSheet(2026, 9, 2026, 8, leaveMonthIsPaid: true));
        Assert.False(LeaveDeduction.ShowsInSheet(2027, 1, 2026, 12, leaveMonthIsPaid: true));
    }

    /// <summary>والترحيل يعبُر السنة: كانون الأول المُسدَّد يظهر في كانون الثاني التالي.</summary>
    [Fact]
    public void الترحيل_يعبُر_حدّ_السنة()
        => Assert.True(LeaveDeduction.ShowsInSheet(2025, 12, 2026, 1, leaveMonthIsPaid: true));
}
