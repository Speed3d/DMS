namespace Dms.Domain;

/// <summary>
/// قواعد ربط الردّ بين الوارد والصادر — منطق مجال نقيّ بلا اعتماد على بنية تحتية (ADR-045).
/// </summary>
/// <remarks>
/// Hint: هذا مصدر الحقيقة الوحيد لِـ«متى يُقبل الربط؟» و«ماذا تصير الحالة بعد الفكّ؟»؛
/// الخدمة تفرضه والواجهة تعكسه.
/// </remarks>
public static class BookReplyRules
{
    /// <summary>هل تسمح حالةُ الوارد بربط ردٍّ به؟</summary>
    /// <remarks>
    /// 🔴 **قاعدةٌ ثانية باسمها الخاص — ولا تُوسَّع <see cref="IncomingWorkflow.IsOperable"/>.**
    /// تلك تحرس **موضعين**: الإحالة إلى قسم والربط. وهي <c>New | InReview</c> فقط. فلمّا صار
    /// الوارد يُجاب **بردَّين** (أوّليّ ثم نهائيّ) احتاج الربطُ قبولَ <see cref="IncomingStatus.Replied"/>
    /// — وتوسيعُ <c>IsOperable</c> كان **يفتح الإحالة على كتابٍ مُجابٍ عنه**، وهي قاعدةٌ لم
    /// يطلب المالك تغييرها. **حارسان مختلفان لسؤالين مختلفين.**
    ///
    /// ⚠️ **و<c>Closed</c> و<c>Archived</c> مستثنيان**: الأول قرارُ إغلاقٍ مستقلّ، والثاني
    /// سجلٌّ رسميّ مغلق — والربط بعدهما يُغيّر حالةَ ما استقرّ.
    /// </remarks>
    public static bool CanLink(IncomingStatus status) =>
        status is IncomingStatus.New or IncomingStatus.InReview or IncomingStatus.Replied;

    /// <summary>
    /// حالةُ الوارد بعد فكّ ربطِ ردٍّ عنه.
    /// </summary>
    /// <param name="current">حالته الآن.</param>
    /// <param name="remainingReplies">عدد الردود الباقية **بعد** الفكّ.</param>
    /// <param name="hasAssignments">هل أُحيل إلى قسمٍ يوماً؟</param>
    /// <param name="becameRepliedByLink">
    /// هل صار «تم الرد» **بسبب ربطٍ** لا بتعليمٍ يدويّ؟ (يُشتقّ من آخر سطرٍ في سجلّ الحركة.)
    /// </param>
    /// <remarks>
    /// ثلاث قواعد، كلٌّ منها وُلدت من حالةٍ حدّية:
    ///
    /// 🔴 **① ردٌّ باقٍ يُبقي «تم الرد».** واردٌ له ردّان فُكّ أحدهما ما زال مردوداً عليه —
    /// وتنزيلُه إلى «قيد المراجعة» يكذب على القارئ ويُبطل حارسَ الملاحظة الإلزامية.
    ///
    /// 🔴 **② «تم الرد» اليدويّ لا يُمحى بفكّ ربط.** مَن وضع الحالة يدوياً بملاحظةٍ إلزامية
    /// («ردٌّ ورقيّ خارج النظام») وثّق واقعةً خارج النظام؛ فلو ربطنا ردّاً ثم فككناه لهبطت
    /// الحالة **وضاع التوثيق**. فالرجوع مقصورٌ على ما رفعه الربطُ نفسه.
    ///
    /// 🔴 **③ ما لم يُحَل قطّ يعود «جديداً» لا «قيد المراجعة».** العودةُ الثابتة إلى
    /// <c>InReview</c> كانت تُرقّي كتاباً لم يمرّ على قسمٍ قطّ — **حالةٌ لم يبلغها بأيّ طريق**.
    ///
    /// ⚠️ و<c>Closed</c>/<c>Archived</c> **لا تُمسّان**: الإغلاق قرارٌ مستقلّ عن الربط.
    /// </remarks>
    public static IncomingStatus StatusAfterUnlink(
        IncomingStatus current,
        int remainingReplies,
        bool hasAssignments,
        bool becameRepliedByLink)
    {
        if (current != IncomingStatus.Replied) return current;   // ⚠️ مغلق/مؤرشف لا يُمسّان
        if (remainingReplies > 0) return current;                // ① ردٌّ باقٍ
        if (!becameRepliedByLink) return current;                // ② تعليمٌ يدويّ بملاحظة

        return hasAssignments ? IncomingStatus.InReview : IncomingStatus.New;   // ③
    }
}
