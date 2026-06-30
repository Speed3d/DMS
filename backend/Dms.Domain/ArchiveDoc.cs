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

    // مالي (نفس منطق الصادر)
    public decimal? Amount { get; set; }
    public Currency? Currency { get; set; }
    public decimal? ExchangeRate { get; set; }
    public decimal? AmountInIqd { get; set; }

    public string? Keywords { get; set; }
    public string? Notes { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }
}
