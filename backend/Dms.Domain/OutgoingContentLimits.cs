namespace Dms.Domain;

/// <summary>
/// حدود حجم محتوى الكتاب الصادر — **قاعدةٌ واحدة** يفرضها الخادم عند الإنشاء والتعديل والمعاينة.
///
/// 🔴 **ما وُجد:** لم يكن للمتن حدٌّ إطلاقاً — <c>BodyHtml</c> و<c>BodyJson</c> بلا سقفٍ سوى حدّ
///    طلب Kestrel (~55 ميغا)، والمتن يُرسَم PDF داخل الطلب نفسه. فمتنٌ ضخمٌ (خطأً أو عمداً) يحبس
///    الخادم في توليد PDF ويملأ القاعدة بنصٍّ لا يُقرأ.
///
/// ⚖️ **والحدود واسعةٌ عمداً:** فاتورةٌ من 600 صفٍّ بتنسيقٍ كامل أقلُّ من ميغا واحد بكثير، فالحدّ
///    لا يمسّ استعمالاً حقيقياً — هو حارسٌ ضدّ الشاذّ لا قيدٌ على العمل. (ويتّسع للجداول القادمة.)
/// </summary>
public static class OutgoingContentLimits
{
    /// <summary>أقصى طول لـ <c>BodyHtml</c> (مصدر الطباعة) بالأحرف.</summary>
    public const int MaxBodyHtmlChars = 4_000_000;

    /// <summary>أقصى طول لـ <c>BodyJson</c> (مصدر التحرير) بالأحرف — أكبر لأن Delta أطول من HTML نفسه.</summary>
    public const int MaxBodyJsonChars = 6_000_000;

    /// <summary>أقصى طول لسبب التعديل بعد الاعتماد — يُكتب في سجلّ الحركة (المحدود بـ500 حرف).</summary>
    public const int MaxChangeNoteChars = 300;

    /// <summary>يعيد رسالة الخطأ بالعربية، أو <c>null</c> إن كان المحتوى ضمن الحدود.</summary>
    public static string? Violation(string? bodyHtml, string? bodyJson, string? changeNote = null)
    {
        if (bodyHtml is { Length: > MaxBodyHtmlChars } || bodyJson is { Length: > MaxBodyJsonChars })
            return "نص الكتاب أكبر من الحدّ المسموح. قسّمه على أكثر من كتاب أو خفّف ما فيه.";
        if (changeNote is not null && changeNote.Trim().Length > MaxChangeNoteChars)
            return $"سبب التعديل أطول من {MaxChangeNoteChars} حرف.";
        return null;
    }
}
