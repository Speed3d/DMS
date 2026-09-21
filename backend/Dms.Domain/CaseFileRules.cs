namespace Dms.Domain;

/// <summary>
/// قواعد المعاملة — منطق مجال نقيّ بلا اعتماد على بنية تحتية (ADR-045).
/// </summary>
/// <remarks>
/// ⚠️ **موضعُها هنا لا في الخدمة**: مشروع الاختبارات يشير إلى <c>Dms.Domain</c> و
/// <c>Dms.Documents</c> **فقط** — فقاعدةٌ تُكتب داخل <c>CaseFileService</c> **لا تُختبر أبداً**.
/// </remarks>
public static class CaseFileRules
{
    /// <summary>أدنى طول لعنوانٍ مقبول.</summary>
    public const int MinTitleLength = 3;

    /// <summary>أقصى طول — مرآةُ عمود القاعدة.</summary>
    public const int MaxTitleLength = 200;

    /// <summary>يتحقّق من العنوان ويرمي استثناءً عربياً واضحاً.</summary>
    public static string EnsureTitle(string? title)
    {
        var t = title?.Trim();
        if (string.IsNullOrWhiteSpace(t) || t.Length < MinTitleLength)
            throw new ValidationException(
                $"عنوان المعاملة مطلوب ({MinTitleLength} أحرف فأكثر) — وهو ما يميّزها في القوائم.");

        if (t.Length > MaxTitleLength)
            throw new ValidationException($"عنوان المعاملة أطول من {MaxTitleLength} حرفاً.");

        return t;
    }

    /// <summary>هل تسمح حالةُ الكتاب الوارد بضمّه إلى معاملة؟</summary>
    /// <remarks>
    /// ✅ **كلُّ الحالات بما فيها «مؤرشف»** (قرار المالك): الضمّ **إشارةٌ لا إجراء** — لا يمسّ
    /// محتوى الكتاب ولا رقمه ولا حالته. ومنعُه على المؤرشف كان يعني أن **كلَّ مراسلاتك
    /// القديمة لا تدخل المعاملات أبداً**، وهو نصفُ قيمة الميزة.
    ///
    /// ⚠️ **ولا يُقاس عليه فكُّ ربط الردّ**: ذاك **يغيّر حالة السجلّ الرسميّ** فيبقى ممنوعاً
    /// على المؤرشف. **إشارةٌ شيءٌ وإجراءٌ شيءٌ آخر.**
    ///
    /// ⚠️ **ودالّةٌ تُعيد `true` دائماً ليست عبثاً**: هي **موضعُ القرار** — فمن أراد تقييده
    /// غداً يجده هنا مع تعليله، لا يخترع شرطاً في خدمةٍ لا تُختبر.
    /// </remarks>
    public static bool CanJoin(IncomingStatus status) => true;

    /// <summary>هل يُسمح بدمج معاملةٍ في أخرى؟ — ويرمي عربيةً عند المنع.</summary>
    /// <param name="sourceId">المعاملة التي تُفرَّغ.</param>
    /// <param name="targetId">المعاملة التي تستقبل.</param>
    /// <param name="sourceVisible">عدد كتب المصدر التي **يراها** الطالب.</param>
    /// <param name="sourceTotal">عدد كتب المصدر كلها في الشركة.</param>
    /// <param name="targetVisible">عدد كتب الهدف التي يراها الطالب.</param>
    /// <param name="targetTotal">عدد كتب الهدف كلها.</param>
    /// <remarks>
    /// 🔴 **دمجُ معاملةٍ بنفسها أخطرُ ما في العملية**: «انقل الكتب ثم احذف المصدر» على السجلّ
    /// نفسه يُفرغه **بعد** أن نقل كتبه إليه ⇒ تخرج كلُّها بـ<c>CaseFileId = null</c>
    /// **والخيطُ يختفي بلا أثر**.
    ///
    /// 🔐 **ولا تنقل ما لا تراه**: من يرى ٣ كتبٍ من ٥ لا يملك أن يقرّر مصير الخمسة. والحارس
    /// **بالعدد لا بالهويّة** — فلا يُسمّى له كتابٌ محجوب ولا يُكشف وجودُ بعينه.
    /// </remarks>
    public static void EnsureCanMerge(
        int sourceId, int targetId,
        int sourceVisible, int sourceTotal,
        int targetVisible, int targetTotal)
    {
        if (sourceId == targetId)
            throw new ValidationException("لا يمكن دمج المعاملة بنفسها.");

        if (sourceVisible < sourceTotal || targetVisible < targetTotal)
            throw new ForbiddenException(
                "لا يمكنك الدمج لأن إحدى المعاملتين تحوي كتباً خارج صلاحيتك — " +
                "والدمج ينقل كلَّ الكتب فلا يُبتّ فيما لا تراه.");
    }

    /// <summary>هل صارت المعاملة فارغة فتُطوى؟</summary>
    /// <remarks>
    /// ⚠️ **الفراغ يُقاس على كتب الشركة كلها لا على ما يراه الطالب** — وإلا طوى موظفُ قسمٍ
    /// معاملةً فيها كتبٌ لزملائه لمجرّد أنه لا يراها.
    /// </remarks>
    public static bool ShouldRetire(int totalMembersAfter) => totalMembersAfter == 0;
}
