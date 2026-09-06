namespace Dms.Domain;

/// <summary>
/// متى يلزم **سببٌ مكتوب** لتغييرٍ على مهمة؟ (ADR-037، بقرار المالك 2026-09-06)
/// </summary>
/// <remarks>
/// **المبدأ:** المهمة سجلٌّ يقرؤه غيرُك — رئيسُك وزملاؤك ومَن يتسلّمها بعدك. وتغييرٌ يمسّهم
/// بلا تعليل يجعل السجلّ يعرض **«ماذا» بلا «لماذا»**.
///
/// وهي سابقةٌ مستقرّة في المستودع: فكّ الأرشفة يشترط سبباً (ADR-021)، وتعديلُ الشهر
/// المُسدَّد كذلك (ADR-026) — وكلاهما «نقضُ أمرٍ استقرّ».
///
/// 🔴 **ولا يُطلب السبب لكل حرف** (قرار المالك): تصحيحُ إملاءٍ في الوصف يمرّ بلا سؤال.
/// والسبب: اشتراطُ تعليلٍ لكل تعديلٍ يدفع الناس إلى كتابة «تعديل» أو نقطة — **فيصير الحقل
/// شكليّاً، وحقلٌ شكليّ أسوأ من غيابه** لأنه يوهم القارئ أن ثمّة تعليلاً.
/// </remarks>
public static class TaskChangeReason
{
    /// <summary>أدنى طول لسببٍ مقبول — نظير سبب فكّ الأرشفة وتعديل الشهر المُسدَّد.</summary>
    public const int MinLength = 5;

    /// <summary>
    /// هل يمسّ هذا التعديل غيرَ صاحبه؟ — أي هل يلزمه سبب؟
    /// </summary>
    /// <remarks>
    /// **يمسّ غيرك:** العنوان (يُقرأ في القوائم والتقارير) · الموعد (يحكم التأخّر والتصعيد) ·
    /// الأولوية (تحكم الترتيب) · القسم (**يحكم مَن يرى**).
    /// **ولا يمسّه:** الوصف والملاحظات وتاريخ البدء — تفصيلٌ لصاحب العمل.
    /// </remarks>
    public static bool EditNeedsReason(
        string oldTitle, string newTitle,
        DateTime oldDue, DateTime newDue,
        DmsTaskPriority oldPriority, DmsTaskPriority newPriority,
        int? oldDepartmentId, int? newDepartmentId)
        => !string.Equals(oldTitle?.Trim(), newTitle?.Trim(), StringComparison.Ordinal)
           || oldDue.Date != newDue.Date
           || oldPriority != newPriority
           || oldDepartmentId != newDepartmentId;

    /// <summary>
    /// هل **تراجعت** نسبة الإنجاز؟ — أي هل يلزمها سبب؟
    /// </summary>
    /// <remarks>
    /// 🔴 **التقدّم لا يحتاج تعليلاً والتراجع يحتاجه.** من رفع النسبة إلى 75% أعلن إنجازاً،
    /// ومن أعادها إلى 25% **نقض إعلاناً سابقاً** — ومن يقرأ الرقم بعد أسبوع لا يعرف أكان
    /// خطأَ إدخالٍ أم انكشف عملٌ ناقص. والسبب يفرّق بينهما.
    ///
    /// ⚠️ **والمساواة ليست تراجعاً**: إعادةُ ضبط النسبة على قيمتها نفسها لا تُنقص شيئاً.
    /// </remarks>
    public static bool ProgressNeedsReason(int oldPercent, int newPercent)
        => newPercent < oldPercent;

    /// <summary>يتحقّق من السبب ويرمي استثناءً عربياً واضحاً عند نقصه.</summary>
    public static void EnsureReason(string? reason, string action)
    {
        if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length < MinLength)
            throw new ValidationException(
                $"{action} يحتاج سبباً مكتوباً ({MinLength} أحرف فأكثر) — ليُقرأ في سجلّ المهمة.");
    }
}
