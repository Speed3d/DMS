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
        // عُيِّن 16 تموز ⇒ من اليوم 16 إلى اليوم 30 = 15 يوماً.
        // (لا 16: الشهر مدى مرقّم 1..30 لا عدّ أيامٍ تقويمية — انظر شباط أدناه.)
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 16), null);
        Assert.Equal(15, days);
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

    // ───────────── شباط: الحالة التي كشفها المالك ولم تكن مغطّاة (2026-08-05) ─────────────
    //
    // 🔴 الحارس الصحيح كان موجوداً في `hr-e2e.ps1` («المستقرّ يأخذ 30») لكنه **لم يمرّ على
    //    شباط قطّ**، لأن السكربت يختار أول شهرٍ غير مُسدَّد فوقع على 3 و4 و5 و7.
    //    واختبارات الوحدة كلها كانت على تموز. **حالةٌ حدّية بلا اختبار = حالةٌ بلا حارس.**

    [Theory]
    [InlineData(2026, 2)]   // شباط عادي — 28 يوماً
    [InlineData(2024, 2)]   // شباط كبيس — 29 يوماً
    public void ShortMonth_SettledEmployee_StillGetsFullWorkingDays(int year, int month)
    {
        // العيب المُبلَّغ عنه: كان يعود 28 فيُصرف 28/30 من الراتب لمن داوم الشهر كلّه.
        var days = PayrollCalculator.EligibleDays(year, month, 30, new DateTime(2020, 1, 1), null);
        Assert.Equal(30, days);
    }

    [Fact]
    public void ShortMonth_SettledEmployee_GetsFullNetSalary()
    {
        // الرقم الحرفيّ من بلاغ المالك: 2000$ كان يظهر 1,866.67.
        var r = PayrollCalculator.Compute(
            2026, 2, workingDays: 30, baseSalary: 2000m, currency: Currency.USD, exchangeRate: null,
            hireDate: new DateTime(2020, 1, 1), terminationDate: null,
            absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(30, r.EligibleDays);
        Assert.Equal(2000m, r.NetSalary);
    }

    [Fact]
    public void SameHireDay_YieldsSameDays_AcrossMonthsOfDifferentLength()
    {
        // جوهر عرف 30/360: الجهد نفسه ⇒ الاستحقاق نفسه. العدّ كان يعطي 13 في شباط و16 في تموز.
        var feb = PayrollCalculator.EligibleDays(2026, 2, 30, new DateTime(2026, 2, 16), null);
        var jul = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 16), null);

        Assert.Equal(15, feb);
        Assert.Equal(15, jul);
    }

    [Fact]
    public void ShortMonth_TerminatedOnLastCalendarDay_GetsFullMonth()
    {
        // أُنهيت خدمته 28 شباط — وهو آخر الشهر، فقد داومه كلّه ⇒ 30 لا 28.
        var days = PayrollCalculator.EligibleDays(2026, 2, 30, new DateTime(2020, 1, 1), new DateTime(2026, 2, 28));
        Assert.Equal(30, days);
    }

    [Fact]
    public void DayBeyondWorkingDays_IsClampedNotDropped()
    {
        // عُيِّن 31 تموز في شهرٍ من 30 يوم عمل ⇒ يومٌ واحد لا صفر.
        var days = PayrollCalculator.EligibleDays(2026, 7, 30, new DateTime(2026, 7, 31), null);
        Assert.Equal(1, days);
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
        // عُيِّن 16 تموز (15 يوماً من مدى 1..30) وغاب يومين من راتب 1,200,000:
        //   الاستحقاق = 1,200,000 × 15/30 = 600,000
        //   خصم الغياب = 1,200,000 × 2/30  =  80,000
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 1_200_000m, Currency.IQD, exchangeRate: null,
            hireDate: new DateTime(2026, 7, 16), terminationDate: null,
            absenceDays: 2, bonus: null, deduction: null, manualAbsenceDeduction: null);

        Assert.Equal(15, r.EligibleDays);
        Assert.Equal(80_000m, r.AbsenceDeduction);
        Assert.Equal(520_000m, r.NetSalary);
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

    // ─────────────────────── مكافأة نهاية الخدمة (الدفعة ٢) ───────────────────────

    [Theory]
    [InlineData(EndOfServiceRatio.MonthPerYear, null, 30)]
    [InlineData(EndOfServiceRatio.HalfMonthPerYear, null, 15)]
    [InlineData(EndOfServiceRatio.CustomDays, 21, 21)]
    [InlineData(EndOfServiceRatio.CustomDays, null, 0)]   // مخصّص بلا عدد ⇒ لا استحقاق
    public void DaysPerYear_FollowsTheChosenRatio(EndOfServiceRatio ratio, int? custom, int expected)
    {
        Assert.Equal(expected, PayrollCalculator.DaysPerYear(ratio, custom));
    }

    [Fact]
    public void EndOfService_MonthPerYear_ThreeYears_EqualsThreeMonths()
    {
        // 3 سنوات × راتب شهر ≈ 3 × 900,000.
        // ⚠️ الناتج **أعلى** قليلاً من 2,700,000 لا أدنى: المدّة 1096 يوماً (2020 كبيسة)
        //    و1096 ÷ 365.25 = 3.0007 سنة. نتحقّق من التقارب لا من رقمٍ مضبوط.
        var amount = PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 1, 1), new DateTime(2023, 1, 1),
            EndOfServiceRatio.MonthPerYear, null);

        const decimal expected = 3 * 900_000m;
        Assert.InRange(amount, expected * 0.995m, expected * 1.005m);
    }

    [Fact]
    public void EndOfService_HalfMonthPerYear_IsHalfOfMonthPerYear()
    {
        var full = PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 1, 1), new DateTime(2024, 1, 1),
            EndOfServiceRatio.MonthPerYear, null);
        var half = PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 1, 1), new DateTime(2024, 1, 1),
            EndOfServiceRatio.HalfMonthPerYear, null);

        Assert.InRange(half, full / 2 - 1m, full / 2 + 1m);
    }

    [Fact]
    public void EndOfService_PartialYear_IsProrated_NotRoundedDown()
    {
        // سنة ونصف يجب أن تُعطي أكثر من سنة — الكسر محفوظ لا مبتور.
        var oneYear = PayrollCalculator.SuggestEndOfService(
            600_000m, new DateTime(2020, 1, 1), new DateTime(2021, 1, 1),
            EndOfServiceRatio.MonthPerYear, null);
        var oneAndHalf = PayrollCalculator.SuggestEndOfService(
            600_000m, new DateTime(2020, 1, 1), new DateTime(2021, 7, 1),
            EndOfServiceRatio.MonthPerYear, null);

        Assert.True(oneAndHalf > oneYear * 1.4m, $"سنة ونصف={oneAndHalf} وسنة={oneYear}");
    }

    [Fact]
    public void EndOfService_DisabledOrZeroService_YieldsNothing()
    {
        // خدمةٌ بلا مدّة، ونسبةٌ بلا أيام — كلتاهما صفر لا استثناء.
        Assert.Equal(0m, PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2023, 5, 1), new DateTime(2023, 5, 1),
            EndOfServiceRatio.MonthPerYear, null));
        Assert.Equal(0m, PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 1, 1), new DateTime(2023, 1, 1),
            EndOfServiceRatio.CustomDays, null));
    }

    [Fact]
    public void EndOfService_UsesFixedThirtyDivisor_NotWorkingDays()
    {
        // ⚠️ العرف التعاقدي «راتب شهر» لا طول شهر الإنهاء — وإلا اختلفت مكافأة موظفَين
        //    متطابقَين لأن أحدهما ترك العمل في شباط والآخر في آذار.
        Assert.Equal(30, PayrollCalculator.EndOfServiceDivisor);

        var febLeaver = PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 3, 1), new DateTime(2023, 2, 28),
            EndOfServiceRatio.MonthPerYear, null);
        var marLeaver = PayrollCalculator.SuggestEndOfService(
            900_000m, new DateTime(2020, 3, 1), new DateTime(2023, 3, 1),
            EndOfServiceRatio.MonthPerYear, null);

        // الفارق يومان من الخدمة فقط، لا قفزةٌ سببها طول الشهر.
        Assert.InRange(marLeaver - febLeaver, 0m, 3_000m);
    }

    [Fact]
    public void NetSalary_AddsEndOfService_AsABonus()
    {
        var net = PayrollCalculator.NetSalary(
            900_000m, 30, 30, bonus: null, deduction: null, absenceDeduction: 0m,
            endOfService: 2_700_000m);

        Assert.Equal(3_600_000m, net);
    }

    [Fact]
    public void Compute_FlowsEndOfService_IntoNetAndIqd()
    {
        var r = PayrollCalculator.Compute(
            2026, 7, 30, baseSalary: 700m, Currency.USD, exchangeRate: 1310m,
            hireDate: new DateTime(2020, 1, 1), terminationDate: new DateTime(2026, 7, 31),
            absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null,
            endOfService: 300m);

        Assert.Equal(1000m, r.NetSalary);            // 700 + 300
        Assert.Equal(1_310_000m, r.NetSalaryIqd);    // × 1310
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
