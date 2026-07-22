namespace Dms.Domain;

/// <summary>
/// سجل حركة الكتاب الوارد (Timeline).
/// Hint: مخصص لتتبع دورة حياة الكتاب الوارد بتفاصيل تشغيلية مرئية في واجهة التفاصيل.
/// </summary>
public class MovementLog
{
    public int MovementId { get; set; }
    public int IncomingId { get; set; }
    public int CompanyId { get; set; }

    /// <summary>نوع الإجراء (مثال: Registered, Forwarded, Reviewed, Replied, Closed).</summary>
    public string Action { get; set; } = string.Empty;

    /// <summary>وصف الإجراء بالعربية (مثال: "استلم الموظف أحمد الكتاب").</summary>
    public string Description { get; set; } = string.Empty;

    public string? FromDepartment { get; set; }
    public string? ToDepartment { get; set; }

    public int PerformedByUserId { get; set; }
    public DateTime PerformedAt { get; set; }

    // العلاقات
    public IncomingBook? IncomingBook { get; set; }
}
