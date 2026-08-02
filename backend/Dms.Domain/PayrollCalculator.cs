namespace Dms.Domain;

/// <summary>نتيجة حساب سطر راتب — كل ما يُخزَّن محسوباً في مكان واحد.</summary>
public readonly record struct PayrollAmounts(
    int EligibleDays, decimal AbsenceDeduction, decimal NetSalary, decimal NetSalaryIqd);

/// <summary>
/// حساب الرواتب — **منطق مجال نقيّ** بلا اعتماد على بنية تحتية، على نمط
/// <see cref="IncomingWorkflow"/> و<see cref="RoleHierarchy"/> و<see cref="FinancialCalculator"/>.
/// </summary>
/// <remarks>
/// Hint: موضعه هنا لا في الخدمة **لأنه ما يقرّر كم يقبض الموظف** — فوجب أن يكون قابلاً
/// للاختبار وحده بلا قاعدة بيانات ولا خادم. والخدمة تستدعيه في كل حفظ، فلا يوجد مسارٌ
/// يُخزَّن فيه صافٍ لم يمرّ من هنا.
/// </remarks>
public static class PayrollCalculator
{
    /// <summary>العرف المحاسبي: الشهر ثلاثون يوماً مهما كان طوله التقويمي (قرار المالك).</summary>
    public const int DefaultWorkingDays = 30;

    /// <summary>أيام العمل المعتمدة لشهر بعينه بحسب الوضع.</summary>
    public static int ResolveWorkingDays(WorkingDaysMode mode, int fixedDays, int year, int month) =>
        mode == WorkingDaysMode.Calendar ? DateTime.DaysInMonth(year, month) : fixedDays;

    /// <summary>
    /// الأيام المستحقّة للموظف في الشهر: كامل <paramref name="workingDays"/> للموظف المستقرّ،
    /// وجزءٌ منها لمن عُيِّن أو أُنهيت خدمته داخل الشهر، وصفرٌ لمن لم يكن على رأس عمله فيه.
    /// </summary>
    /// <remarks>
    /// السقف عند <paramref name="workingDays"/> مقصود: في وضع «30 ثابت» يُنتج شهرٌ من 31 يوماً
    /// حضوراً كاملاً قدره 31، وصرفُ 31/30 من الراتب زيادةٌ لا يريدها أحد.
    /// </remarks>
    public static int EligibleDays(
        int year, int month, int workingDays, DateTime hireDate, DateTime? terminationDate)
    {
        if (workingDays <= 0) return 0;

        var firstOfMonth = new DateTime(year, month, 1);
        var lastOfMonth = new DateTime(year, month, DateTime.DaysInMonth(year, month));

        var start = hireDate.Date > firstOfMonth ? hireDate.Date : firstOfMonth;
        var end = terminationDate?.Date is { } t && t < lastOfMonth ? t : lastOfMonth;

        // عُيِّن بعد الشهر، أو انتهت خدمته قبله ⇒ لا استحقاق أصلاً.
        if (start > end) return 0;

        return Math.Min((end - start).Days + 1, workingDays);
    }

    /// <summary>
    /// خصم الغياب المقترح = (أيام الغياب ÷ أيام العمل) × الراتب الأساسي.
    /// **اقتراحٌ لا حكم** — المستخدم يعدّله، ويُصان تعديله بعلَم <c>AbsenceDeductionIsManual</c>.
    /// </summary>
    public static decimal SuggestAbsenceDeduction(decimal baseSalary, int absenceDays, int workingDays)
    {
        if (absenceDays <= 0 || workingDays <= 0) return 0m;
        var capped = Math.Min(absenceDays, workingDays);
        return decimal.Round(baseSalary * capped / workingDays, 2);
    }

    /// <summary>
    /// صافي الراتب بعملة الموظف.
    /// </summary>
    /// <remarks>
    /// ⚠️ **قد يعود سالباً** حين تتجاوز الخصومات الاستحقاق — وهذا مقصود: الحسابُ يقول الحقيقة،
    /// وحصرُ السالب في الصفر يُخفي خطأ إدخالٍ بدل أن يكشفه. المسودّة تحتمله ليُصحَّح،
    /// و<b>التسديد</b> هو ما يرفضه (انظر <see cref="EnsurePayable"/>).
    /// </remarks>
    public static decimal NetSalary(
        decimal baseSalary, int eligibleDays, int workingDays,
        decimal? bonus, decimal? deduction, decimal absenceDeduction)
    {
        if (workingDays <= 0)
            throw new ValidationException("أيام العمل في الشهر يجب أن تكون أكبر من صفر.");

        var earned = decimal.Round(baseSalary * eligibleDays / workingDays, 2);
        return decimal.Round(earned + (bonus ?? 0m) - (deduction ?? 0m) - absenceDeduction, 2);
    }

    /// <summary>
    /// حساب سطر كامل. <paramref name="manualAbsenceDeduction"/> غير فارغ ⇒ يُحترم تعديل المستخدم
    /// ولا يُعاد الاقتراح فوقه.
    /// </summary>
    public static PayrollAmounts Compute(
        int year, int month, int workingDays,
        decimal baseSalary, Currency currency, decimal? exchangeRate,
        DateTime hireDate, DateTime? terminationDate,
        int absenceDays, decimal? bonus, decimal? deduction,
        decimal? manualAbsenceDeduction)
    {
        var eligible = EligibleDays(year, month, workingDays, hireDate, terminationDate);
        var absence = manualAbsenceDeduction
                      ?? SuggestAbsenceDeduction(baseSalary, absenceDays, workingDays);

        var net = NetSalary(baseSalary, eligible, workingDays, bonus, deduction, absence);
        return new PayrollAmounts(eligible, absence, net, ToIqd(net, currency, exchangeRate));
    }

    /// <summary>هل يمكن تحويل هذه العملة بالسعر المتاح؟ (الدينار لا يحتاج سعراً).</summary>
    public static bool HasUsableRate(Currency currency, decimal? rate) =>
        currency != Currency.USD || rate is > 0;

    /// <summary>
    /// المعادل بالدينار — **صفرٌ مؤقّت** حين ينقص سعر الصرف بدل رمي استثناء.
    /// </summary>
    /// <remarks>
    /// ⚠️ لماذا لا نرمي كما يفعل <see cref="FinancialCalculator.ComputeIqd"/>؟ لأن الكشف
    /// **يُولَّد قبل أن يُدخل المستخدم سعر الصرف**، فالرمي هنا كان يُنتج قفلاً مغلقاً: لا
    /// يستطيع إنشاء الشهر ليضع فيه السعر، ولا يستطيع وضع السعر قبل إنشاء الشهر.
    /// (انكشف في أول تشغيل حيّ: <c>POST /payroll/periods/2026/7</c> ردّ 400 على موظف بالدولار.)
    ///
    /// والصفر **ليس تسامحاً**: <see cref="EnsureRateSet"/> يرفض التسديد بدون سعر، فلا يُجمَّد
    /// كشفٌ فيه صفرٌ كاذب. المسودّة تحتمل النقص، والتسديد لا يحتمله.
    /// </remarks>
    public static decimal ToIqd(decimal net, Currency currency, decimal? rate) =>
        HasUsableRate(currency, rate)
            ? FinancialCalculator.ComputeIqd(net, currency, rate) ?? 0m
            : 0m;

    /// <summary>حارس التسديد: كشفٌ فيه رواتب بالدولار لا يُسدَّد بلا سعر صرف للشهر.</summary>
    public static void EnsureRateSet(bool hasForeignCurrency, decimal? rate)
    {
        if (hasForeignCurrency && rate is null or <= 0)
            throw new ValidationException(
                "الكشف يحتوي رواتب بالدولار — حدّد سعر صرف الشهر قبل التسديد.");
    }

    /// <summary>
    /// حارس التسديد: يمنع تجميد كشفٍ فيه رقم لا معنى له.
    /// </summary>
    /// <remarks>التسديد لا رجعة فيه، فما يُتساهَل معه في المسودّة يُرفَض هنا.</remarks>
    public static void EnsurePayable(string employeeName, decimal netSalary)
    {
        if (netSalary < 0)
            throw new ValidationException(
                $"صافي راتب «{employeeName}» سالب — راجع الخصومات قبل التسديد.");
    }

    /// <summary>الاسم العربي للشهر (يظهر في الإيصال والكشف وشبكة الأشهر).</summary>
    public static string ArabicMonth(int month) => month switch
    {
        1 => "كانون الثاني", 2 => "شباط", 3 => "آذار", 4 => "نيسان",
        5 => "أيار", 6 => "حزيران", 7 => "تموز", 8 => "آب",
        9 => "أيلول", 10 => "تشرين الأول", 11 => "تشرين الثاني", 12 => "كانون الأول",
        _ => month.ToString(),
    };

    /// <summary>الاسم الإنجليزي للشهر (للإيصال الإنجليزي).</summary>
    public static string EnglishMonth(int month) => month switch
    {
        1 => "January", 2 => "February", 3 => "March", 4 => "April",
        5 => "May", 6 => "June", 7 => "July", 8 => "August",
        9 => "September", 10 => "October", 11 => "November", 12 => "December",
        _ => month.ToString(),
    };
}
