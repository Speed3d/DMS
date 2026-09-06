namespace Dms.Domain;

/// <summary>
/// حساب موعد النسخة التالية من مهمة متكررة — **دالّة نقيّة**: لا قاعدةَ بيانات ولا وقتَ نظام.
/// </summary>
/// <remarks>
/// لماذا نقيّة؟ لأن العيب الوحيد المكلف هنا **حسابيّ** (تكاثرٌ أو انزلاق تسلسل)، والحسابُ
/// النقيّ يُختبَر بالوحدة بلا خادم — على نمط <c>PayrollCalculator</c> و<c>LeaveDeduction</c>.
/// </remarks>
public static class TaskRecurrence
{
    /// <summary>الموعد التالي، أو <c>null</c> إن تجاوز نهاية التكرار.</summary>
    /// <remarks>
    /// ⚠️ **<c>AddMonths</c> يقصّ نهاية الشهر:** 31 كانون الثاني + شهر = **28/29 شباط**، ثم
    /// +شهر = 28/31 آذار — فينزلق التسلسل نزولاً ولا يعود إلى 31. **القرار: مقبولٌ ومقصود**
    /// (سلوك .NET القياسي، وأبسطُ ما يُشرَح للمستخدم)، وله حارسٌ صريح في الاختبارات.
    /// 🔴 **الحالة الحدّية بلا حارسٍ هي التي تنفجر** — درس شباط.
    ///
    /// ⚠️ **والمقارنة بالتاريخ لا باللحظة**: نهايةُ التكرار يومٌ، فنسخةٌ موعدها **نفسُ** يوم
    /// النهاية مقبولة، وما بعده لا.
    /// </remarks>
    public static DateTime? NextDueDate(
        DateTime currentDue,
        DmsRecurrencePattern pattern,
        int interval,
        DateTime? endDate)
    {
        // فاصلٌ غير صالح يُعامَل كواحد بدل أن يرمي: القيمة تأتي من نموذج، والخدمة الخلفية
        // لا ينبغي أن تتعطّل بسبب صفٍّ واحدٍ مشوّه.
        if (interval < 1) interval = 1;

        var next = pattern switch
        {
            DmsRecurrencePattern.Daily => currentDue.AddDays(interval),
            DmsRecurrencePattern.Weekly => currentDue.AddDays(7 * interval),
            DmsRecurrencePattern.Monthly => currentDue.AddMonths(interval),
            _ => currentDue.AddDays(interval),
        };

        return endDate is { } end && next.Date > end.Date ? null : next;
    }

    /// <summary>الاسم العربي لنمط التكرار.</summary>
    public static string ArabicName(DmsRecurrencePattern pattern) => pattern switch
    {
        DmsRecurrencePattern.Daily => "يومي",
        DmsRecurrencePattern.Weekly => "أسبوعي",
        DmsRecurrencePattern.Monthly => "شهري",
        _ => pattern.ToString(),
    };
}
