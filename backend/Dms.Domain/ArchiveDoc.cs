namespace Dms.Domain;

/// <summary>مستند أرشيف (Phase 2): حقول + مالي + كلمات مفتاحية + مرفقات + بحث.</summary>
public class ArchiveDoc
{
    public int ArchiveId { get; set; }
    public int CompanyId { get; set; }
    public string ArchiveNumber { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;

    public string? BookNumber { get; set; }
    public DateTime? BookDate { get; set; }
    public int? FromEntityId { get; set; }
    public int? ToEntityId { get; set; }
    public int? DocumentTypeId { get; set; }

    /// <summary>القسم الذي تخصّه الأضبارة — **اختياري عمداً**.</summary>
    /// <remarks>
    /// ⚠️ لم يُجعل إلزامياً رغم أنه يُحسّن الفلترة: مُدخِلٌ لا يعرف قسم أضبارة ورقية قديمة
    /// سيُخمّن، فتُصنَّف خطأً وتُعرض على قسم لا علاقة له بها. **بيانات خاطئة أسوأ من ناقصة.**
    /// وأضبارة بلا قسم يراها منشئها والمدير فأعلى — فلا تضيع ولا تتسرّب.
    /// </remarks>
    public int? DepartmentId { get; set; }
    public Department? Department { get; set; }

    // مالي — **مخفيّ من الواجهة بقرار المالك (2026-07-28)، والأعمدة باقية عمداً.**
    // ⚠️ لا تُحذف: `ReportService` يقرأ `AmountInIqd` كمصدرٍ في التقرير المالي (صادر + أرشيف)،
    //    فحذفها يُلغي مصدر تقرير لا حقلاً معطّلاً — ويضرب معيار قبول قائماً.
    public decimal? Amount { get; set; }
    public Currency? Currency { get; set; }
    public decimal? ExchangeRate { get; set; }
    public decimal? AmountInIqd { get; set; }

    public string? Keywords { get; set; }
    public string? Notes { get; set; }
    public string? BodyHtml { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }
}
