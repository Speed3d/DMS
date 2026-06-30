namespace Dms.Domain;

/// <summary>
/// كتاب صادر. يبدأ مسودّة بلا رقم؛ عند الاعتماد يأخذ رقماً رسمياً + PDF + QR موقّع ويُقفل.
/// التعديل بعد الاعتماد للمدير فأعلى مع حفظ إصدار وإعادة توليد PDF/QR.
/// </summary>
public class OutgoingBook
{
    public int OutgoingId { get; set; }
    public int CompanyId { get; set; }

    // الترقيم الرسمي (يُملأ عند الاعتماد فقط)
    public string? Number { get; set; }     // DEN-2026-00124
    public int? Year { get; set; }          // سنة الاعتماد
    public int? SerialNo { get; set; }      // التسلسل ضمن (الشركة + السنة)

    public DateTime Date { get; set; }      // تاريخ الكتاب
    public int EntityId { get; set; }       // الجهة المستلمة
    public string Subject { get; set; } = string.Empty;
    public string BodyHtml { get; set; } = string.Empty;
    public int TemplateId { get; set; }
    public BookStatus Status { get; set; } = BookStatus.Draft;

    // الحقول المالية
    public decimal? Amount { get; set; }
    public Currency? Currency { get; set; }
    public decimal? ExchangeRate { get; set; }
    public decimal? AmountInIqd { get; set; }   // مُجمَّد لحظة الإنشاء/الاعتماد

    // QR موقّع + الـ PDF المولّد
    public string? QrContent { get; set; }      // المحتوى الموقّع الكامل المطبوع في الـ QR
    public string? QrSignature { get; set; }    // التوقيع وحده (للأرشفة/المراجعة)
    public string? GeneratedPdfBlobKey { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? ApprovedByUserId { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    // حذف ناعم
    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    /// <summary>للتزامن المتفائل عند التعديل بعد الاعتماد.</summary>
    public byte[]? RowVersion { get; set; }

    public Entity? Entity { get; set; }
    public Template? Template { get; set; }
}
