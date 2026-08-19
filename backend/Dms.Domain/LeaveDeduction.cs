namespace Dms.Domain;

/// <summary>
/// قاعدة نسبة أيام الإجازة إلى شهرٍ بعينه — **موضعٌ واحد لقرار التقسيم** (ADR-036).
/// </summary>
/// <remarks>
/// 🔴 **سبب وجود هذا الملف:** الإجازة مدًى بين تاريخين، وكشف الرواتب **شهر**. والمدى قد
/// يعبُر الشهرين (٢٨ آب ← ٣ أيلول)، فيلزم قرارٌ صريح: أين تُحسم؟
/// **قرار المالك (2026-08-19): تُقسَم بالأيام** — كل شهرٍ يحمل أيامه التي وقعت فيه فعلاً،
/// لأن أربعة أيامٍ وقعت في آب ليست من راتب أيلول.
///
/// ⚠️ **والقاعدة هنا لا في الخدمة**: الحسم يُقرأ في موضعين على الأقل (كشف التنبيه،
/// والتطبيق على السطر)، ونسخُها يجعلهما يفترقان بأول تعديل — والمبلغ **مال**.
/// نظير <see cref="PayrollPayable"/> و<see cref="LeaveDecision"/>.
///
/// ⚠️ **والتواريخ هنا تقويميّة لا لحظات**: تُقارَن بـ<c>.Date</c> دائماً، فإجازةُ الأول
/// من الشهر تبقى في الأول مهما كانت ساعة تسجيلها.
/// </remarks>
public static class LeaveDeduction
{
    /// <summary>
    /// عدد أيام الإجازة الواقعة **داخل** الشهر المطلوب — شاملاً الطرفين.
    /// </summary>
    /// <remarks>
    /// إجازةٌ لا تمسّ الشهر تُعيد صفراً، فتُصفَّى من قوائم التنبيه بلا حالةٍ خاصة.
    /// </remarks>
    public static int DaysInMonth(DateTime fromDate, DateTime toDate, int year, int month)
    {
        if (month is < 1 or > 12) return 0;

        var from = fromDate.Date;
        var to = toDate.Date;
        if (to < from) return 0;

        var firstOfMonth = new DateTime(year, month, 1);
        var lastOfMonth = firstOfMonth.AddMonths(1).AddDays(-1);

        var start = from > firstOfMonth ? from : firstOfMonth;
        var end = to < lastOfMonth ? to : lastOfMonth;

        return end < start ? 0 : (end - start).Days + 1;
    }

    /// <summary>
    /// هل يظهر تنبيه هذه الإجازة في كشف (<paramref name="sheetYear"/>/<paramref name="sheetMonth"/>)؟
    /// </summary>
    /// <param name="leaveMonthIsPaid">
    /// هل كشفُ الشهر الذي وقعت فيه هذه الأيام **مُسدَّدٌ بالفعل**؟
    /// </param>
    /// <remarks>
    /// 🔴 **قرار المالك الثالث (2026-08-19):** إجازةٌ يُوافَق عليها **بعد** تسديد شهرها لا
    /// تضيع — تظهر في الكشف التالي **منسوبةً لشهرها الأصلي** («إجازة من ٤/٢٠٢٦ لم تُحسم»).
    ///
    /// ⚠️ **والشرط <c>leaveMonthIsPaid</c> جوهريّ لا زينة:** بدونه تظهر إجازةُ آب في كشف
    /// أيلول **بينما كشف آب ما زال مسودّةً** يمكن حسمها فيه — فتُحسم مرّتين أو تُحسم من
    /// الشهر الخطأ. القاعدة: **تُعالَج في شهرها ما دام مفتوحاً، وتُرحَّل إن أُقفل.**
    /// </remarks>
    public static bool ShowsInSheet(
        int leaveYear, int leaveMonth, int sheetYear, int sheetMonth, bool leaveMonthIsPaid)
    {
        // شهرُها نفسه ⇒ تظهر دائماً.
        if (leaveYear == sheetYear && leaveMonth == sheetMonth) return true;

        // شهرٌ سابقٌ **أُقفل بالتسديد** ⇒ تُرحَّل إلى هذا الكشف.
        var leaveIndex = leaveYear * 12 + leaveMonth;
        var sheetIndex = sheetYear * 12 + sheetMonth;
        return leaveMonthIsPaid && leaveIndex < sheetIndex;
    }
}
