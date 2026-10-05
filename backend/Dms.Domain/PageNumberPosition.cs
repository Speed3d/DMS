namespace Dms.Domain;

/// <summary>
/// موضع «صفحة X من Y» في القالب (بلاغ المالك 2026-10-05): كان في الوسط ثابتاً — وتذييلُ القالب قد يحمل رسماً في الوسط.
/// محاذاةٌ (يمين · وسط · يسار) **وإزاحةٌ بالمليمتر** أفقياً وعمودياً، فيوضع الرقم حيث يلائم القالب.
/// </summary>
/// <remarks>
/// 🔑 **في القالب لا في الكتاب** (قرار المالك): الموضع يتبع رسم التذييل، فيُضبط مرّةً لكل قالب ويأخذه كل كتابٍ به.
/// والقيم تُفحص هنا وحدها — الخدمة تفرضها والواجهة تعكسها.
/// </remarks>
public static class PageNumberPosition
{
    public const string Right = "right";
    public const string Center = "center";
    public const string Left = "left";

    /// <summary>أقصى إزاحةٍ أفقية (مم) يميناً أو يساراً — نصف عرض المتن تقريباً.</summary>
    public const int MaxOffsetXMm = 80;

    /// <summary>أقصى إزاحةٍ عمودية (مم) — موجبٌ للأعلى. الرقم يبقى في منطقة التذييل.</summary>
    public const int MaxOffsetYMm = 30;

    /// <summary>نقطة طباعة لكل مليمتر.</summary>
    public const float PointsPerMm = 72f / 25.4f;

    /// <summary>الفراغ ⟵ الوسط (السلوك السابق) · وقيمةٌ غير معروفة ⟵ رفضٌ بالعربية لا تجاهلٌ صامت.</summary>
    public static string Align(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        null or "" or Center => Center,
        Right => Right,
        Left => Left,
        _ => throw new ValidationException("موضع ترقيم الصفحة: يمين أو وسط أو يسار."),
    };

    public static int OffsetX(int mm) => Math.Clamp(mm, -MaxOffsetXMm, MaxOffsetXMm);

    public static int OffsetY(int mm) => Math.Clamp(mm, -MaxOffsetYMm, MaxOffsetYMm);
}
