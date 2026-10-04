namespace Dms.Domain;

/// <summary>
/// نوع الكتاب الصادر (ADR-057) — كتاب رسمي · فاتورة · عرض سعر · وما يضيفه المالك. **لكل شركةٍ قائمتها.**
/// </summary>
/// <remarks>
/// 🔑 **منفصلٌ عن <see cref="DocumentType"/>** (قرار المالك 2026-10-04): ذاك لتصنيف الوارد والأرشيف، وهذا لما
/// تُصدره الشركة — والخلط يجعل «شكوى» و«مخطّط» خياراتٍ في إنشاء فاتورة.
/// <para>
/// ⚖️ **تصنيفٌ اليوم لا قالب**: للفلترة والعرض. طباعةُ اسمه في الـPDF وإعداداته الافتراضية تُقرَّر على
/// النموذج الحيّ (قرار المالك) — فلا تُبنى قبل أن يراها.
/// </para>
/// </remarks>
public class OutgoingBookType
{
    public int OutgoingBookTypeId { get; set; }
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;
}

/// <summary>أنواع الصادر الافتراضية لكل شركةٍ جديدة — نقطة انطلاقٍ يعدّلها المالك من الإعدادات.</summary>
public static class DefaultOutgoingBookTypes
{
    /// <summary>الأوّل هو الافتراضيّ للكتاب الجديد (قرار المالك: «كتاب رسمي»).</summary>
    public static readonly string[] Names = ["كتاب رسمي", "فاتورة", "عرض سعر"];

    public static string Default => Names[0];

    /// <summary>كيانات الأنواع الافتراضية لشركةٍ بعينها (بلا حفظ — المُستدعي يحفظ).</summary>
    public static IEnumerable<OutgoingBookType> For(int companyId) =>
        Names.Select(n => new OutgoingBookType { CompanyId = companyId, Name = n });
}
