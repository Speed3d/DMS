namespace Dms.Domain;

/// <summary>
/// قالب كتاب لشركة: صور هيدر/فوتر/علامة مائية (مفاتيح Blob) + إعدادات الصفحة.
/// المتن يبقى نصاً حقيقياً؛ الصور للترويسة فقط.
/// </summary>
public class Template
{
    public int TemplateId { get; set; }
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;

    public string? HeaderImageKey { get; set; }
    public string? FooterImageKey { get; set; }
    public string? WatermarkImageKey { get; set; }

    /// <summary>شفافية العلامة المائية 0–100.</summary>
    public int WatermarkOpacity { get; set; } = 10;

    // هوامش المتن (نقاط)
    public int MarginTop { get; set; } = 24;
    public int MarginRight { get; set; } = 40;
    public int MarginBottom { get; set; } = 24;
    public int MarginLeft { get; set; } = 40;

    public string PageSize { get; set; } = "A4";
    public string FontFamily { get; set; } = "Amiri";

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public Company? Company { get; set; }
}
