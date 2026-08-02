using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حساب الرواتب — أكثر منطق في النظام أثراً على شخص حقيقي، فيُختبر وحده بلا خادم ولا قاعدة.
/// </summary>
public class PayrollCalculatorTests
{
    // ─────────────────────────── أيام العمل ───────────────────────────

    [Fact]
    public void FixedMode_IgnoresCalendarLength()
    {
        // شباط 28 يوماً وآذار 31 — والوضع الثابت يعطي 30 في كليهما.
        Assert.Equal(30, PayrollCalculator.ResolveWorkingDays(WorkingDaysMode.Fixed, 30, 2026, 2));
        Assert.Equal(30, PayrollCalculator.ResolveWorkingDays(WorkingDaysMode.Fixed, 30, 2026, 3));
    }

    [Theory]
    [InlineData(2026, 2, 28)]   // شباط عادي
    [InlineData(2024, 2, 29)]   // شباط كبيس
    [InlineData(2026, 4, 30)]
    [InlineData(2026, 12, 31)]
    public void CalendarMode_FollowsRealMonthLength(int year, int month, int expected)
    {
        Assert.Equal(expected, PayrollCalculator.ResolveWorkingDays(WorkingDaysMode.Calendar, 30, year, month));
    }

    // ─────────────────────────── الأيام المستحقّة ───────────────────────────

    [Fact]
    public void SettledEmployee_GetsFullWorkingDays()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2020, 1, 1), null);
        Assert.Equal(30, days);
    }

    [Fact]
    public void ThirtyOneDayMonth_IsCappedAtThirty()
    {
        // تموز 31 يوماً — بلا سقف لصار الاستحقاق 31/30 من الراتب، أي زيادة لا يريدها أحد.
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2020, 1, 1), null);
        Assert.Equal(30, days);
    }

    [Fact]
    public void HiredMidMonth_GetsRemainingDaysOnly()
    {
        // عُيِّن 16 تموز ⇒ من 16 إلى 31 = 16 يوماً.
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 16), null);
        Assert.Equal(16, days);
    }

    [Fact]
    public void HiredOnFirstOfMonth_GetsFullMonth()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 1), null);
        Assert.Equal(30, days);
    }

    [Fact]
    public void TerminatedMidMonth_GetsElapsedDaysOnly()
    {
        // أُنهيت خدمته 10 تموز ⇒ من 1 إلى 10 = 10 أيام.
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2020, 1, 1), new DateTime(2026, 7, 10));
        Assert.Equal(10, days);
    }

    [Fact]
    public void HiredAndTerminatedInSameMonth_GetsTheSpanBetween()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 5), new DateTime(2026, 7, 14));
        Assert.Equal(10, days);
    }

    [Fact]
    public void HiredAfterMonth_GetsNothing()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 9, 1), null);
        Assert.Equal(0, days);
    }

    [Fact]
    public void TerminatedBeforeMonth_GetsNothing()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2020, 1, 1), new DateTime(2026, 5, 20));
        Assert.Equal(0, days);
    }

    [Fact]
    public void TerminatedOnLastDay_GetsFullMonth()
    {
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2020, 1, 1), new DateTime(2026, 7, 31));
        Assert.Equal(30, days);
    }

    [Fact]
    public void CalendarMode_PartialMonth_IsNotCappedBelowRealDays()
    {
        // شباط 2026 = 28 يوماً، عُيِّن يوم 15 ⇒ 14 يوماً من 28.
        var days = PayrollCalculator.EligibleDays(2026, 2, 28, new DateTime(2026, 2, 15), null);
        Assert.Equal(14, days);
    }

    // ─────────────────────────── خصم الغياب ───────────────────────────

    [Fact]
    public void AbsenceDeduction_IsProportionalToWorkingDays()
    {
        // 3 أيام غياب من 30 على راتب 900,000 ⇒ 90,000
        var d = PayrollCalculator.SuggestAbsenceDeduction(900_000m, 3, 30);
        Assert.Equal(90_000m, d);
    }

    [Fact]
    public void NoAbsence_NoDeduction()
    {
        Assert.Equal(0m, PayrollCalculator.SuggestAbsenceDeduction(900_000m, 0, 30));
    }

    [Fact]
    public void AbsenceBeyondWorkingDays_IsCapped()
    {
        // 40 يوم غياب في شهر من 30 ⇒ يُخصم الشهر كله لا أكثر.
        var d = PayrollCalculator.SuggestAbsenceDeduction(900_000m, 40, 30);
        Assert.Equal(900_000m, d);
    }

    [Fact]
    public void AbsenceDeduction_RoundsToTwoDecimals()
    {
        var d = PayrollCalculator.SuggestAbsenceDeduction(1000m, 1, 30);
        Assert.Equal(33.33m, d);
    }

    // ─────────────────────────── الصافي ───────────────────────────

    [Fact]
    public void FullMonth_NoAdjustments_EqualsBaseSalary()
    {
        var net = PayrollCalculator.NetSalary(1_000_000m, 30, 30, null, null, 0m);
        Assert.Equal(1_000_000m, net);
    }

    [Fact]
    public void BonusAdds_DeductionSubtracts()
    {
        var net = PayrollCalculator.NetSalary(1_000_000m, 30, 30, 200_000m, 50_000m, 0m);
        Assert.Equal(1_150_000m, net);
    }

    [Fact]
    public void PartialMonth_IsProratedByEligibleDays()
    {
        // نصف الشهر ⇒ نصف الراتب.
        var net = PayrollCalculator.NetSalary(1_000_000m, 15, 30, null, null, 0m);
        Assert.Equal(500_000m, net);
    }

    [Fact]
    public void ZeroEligibleDays_YieldsOnlyManualAmounts()
    {
        // لم يكن على رأس عمله ⇒ لا استحقاق أساسي، والمكافأة اليدوية وحدها تبقى.
        var net = PayrollCalculator.NetSalary(1_000_000m, 0, 30, 75_000m, null, 0m);
        Assert.Equal(75_000m, net);
    }

    [Fact]
    public void ZeroWorkingDays_Throws()
    {
        Assert.Throws<ValidationException>(() =>
            PayrollCalculator.NetSalary(1_000_000m, 30, 0, null, null, 0m));
    }

    [Fact]
    public void DeductionsBeyondSalary_ProduceNegative_NotZero()
    {
        // الحساب يقول الحقيقة؛ حصرُ السالب في الصفر كان سيُخفي خطأ الإدخال.
        var net = PayrollCalculator.NetSalary(500_000m, 30, 30, null, 800_000m, 0m);
        Assert.Equal(-300_000m, net);
    }

    // ─────────────────────────── الحساب الكامل ───────────────────────────

    [Fact]
    public void Compute_IqdEmployee_NetEqualsNetIqd()
    {
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 900_000m, Currency.IQD, exchangeRate: null,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(30, r.EligibleDays);
        Assert.Equal(0m, r.AbsenceDeduction);
        Assert.Equal(900_000m, r.NetSalary);
        Assert.Equal(900_000m, r.NetSalaryIqd);
    }

    [Fact]
    public void Compute_UsdEmployee_ConvertsByPeriodRate()
    {
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 700m, Currency.USD, exchangeRate: 1310m,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(700m, r.NetSalary);
        Assert.Equal(917_000m, r.NetSalaryIqd);
    }

    [Fact]
    public void Compute_UsdEmployee_WithoutRate_YieldsZeroIqd_ButKeepsUsdNet()
    {
        // ⚠️ لا يرمي: الكشف يُولَّد **قبل** إدخال سعر الصرف، فالرمي هنا كان قفلاً مغلقاً
        //    (لا إنشاء للشهر بلا سعر، ولا وضع للسعر بلا شهر). انكشف في أول تشغيل حيّ.
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 700m, Currency.USD, exchangeRate: null,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(700m, r.NetSalary);   // الصافي بعملته صحيح
        Assert.Equal(0m, r.NetSalaryIqd);  // والمعادل ينتظر السعر
    }

    [Fact]
    public void EnsureRateSet_BlocksPaying_WhenUsdSalariesLackARate()
    {
        Assert.Throws<ValidationException>(() => PayrollCalculator.EnsureRateSet(true, null));
        Assert.Throws<ValidationException>(() => PayrollCalculator.EnsureRateSet(true, 0m));
    }

    [Fact]
    public void EnsureRateSet_AllowsPaying_WhenAllIqd_OrRatePresent()
    {
        PayrollCalculator.EnsureRateSet(false, null);   // لا رواتب بالدولار ⇒ لا حاجة لسعر
        PayrollCalculator.EnsureRateSet(true, 1310m);
    }

    [Theory]
    [InlineData(Currency.IQD, null, true)]
    [InlineData(Currency.USD, null, false)]
    [InlineData(Currency.USD, 0.0, false)]
    [InlineData(Currency.USD, 1310.0, true)]
    public void HasUsableRate_IsTrueOnlyWhenConversionIsPossible(
        Currency currency, double? rate, bool expected)
    {
        Assert.Equal(expected, PayrollCalculator.HasUsableRate(currency, (decimal?)rate));
    }

    [Fact]
    public void Compute_ManualAbsenceDeduction_OverridesSuggestion()
    {
        // الاقتراح لثلاثة أيام = 90,000 — والمستخدم قرّر 50,000 فيجب أن يبقى قراره.
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 900_000m, Currency.IQD, exchangeRate: null,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 3, bonus: null, deduction: null, manualAbsenceDeduction: 50_000m);

        Assert.Equal(50_000m, r.AbsenceDeduction);
        Assert.Equal(850_000m, r.NetSalary);
    }

    [Fact]
    public void Compute_AutomaticAbsenceDeduction_UsesSuggestion()
    {
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 900_000m, Currency.IQD, exchangeRate: null,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 3, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(90_000m, r.AbsenceDeduction);
        Assert.Equal(810_000m, r.NetSalary);
    }

    [Fact]
    public void Compute_NewHireWithAbsence_ProratesThenDeducts()
    {
        // عُيِّن 16 تموز (16 يوماً) وغاب يومين من راتب 1,200,000:
        //   الاستحقاق = 1,200,000 × 16/30 = 640,000
        //   خصم الغياب = 1,200,000 × 2/30  =  80,000
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 1_200_000m, Currency.IQD, exchangeRate: null,
            hireDate: new DateTime(2026, 7, 16), terminationDate: null,
            absenceDays: 2, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(16, r.EligibleDays);
        Assert.Equal(80_000m, r.AbsenceDeduction);
        Assert.Equal(560_000m, r.NetSalary);
    }

    // ─────────────────────────── حارس التسديد ───────────────────────────

    [Fact]
    public void EnsurePayable_RejectsNegativeNet()
    {
        var ex = Assert.Throws<ValidationException>(() => PayrollCalculator.EnsurePayable("سنان", -1m));
        Assert.Contains("سنان", ex.Message);
    }

    [Fact]
    public void EnsurePayable_AllowsZeroAndPositive()
    {
        PayrollCalculator.EnsurePayable("سنان", 0m);
        PayrollCalculator.EnsurePayable("سنان", 900_000m);
    }

    // ─────────────────────────── أسماء الأشهر ───────────────────────────

    [Fact]
    public void MonthNames_CoverAllTwelve_InBothLanguages()
    {
        for (var m = 1; m <= 12; m++)
        {
            Assert.NotEqual(m.ToString(), PayrollCalculator.ArabicMonth(m));
            Assert.NotEqual(m.ToString(), PayrollCalculator.EnglishMonth(m));
        }
    }
}
