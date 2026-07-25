namespace Dms.Domain;

/// <summary>
/// كيان الكتاب الوارد.
/// Hint: يتم إنشاؤه بحالة New ويُمنح رقماً داخلياً فوراً بخلاف الصادر الذي يُرقم عند الاعتماد.
/// </summary>
public class IncomingBook
{
    public int IncomingId { get; set; }
    public int CompanyId { get; set; }

    // الترقيم الرسمي الداخلي
    public string? IncomingNumber { get; set; }     // DEN-IN-2026-00015
    public int? Year { get; set; }
    public int? SerialNo { get; set; }

    // تفاصيل الكتاب الخارجي (من الجهة المرسلة)
    public string? ExternalNumber { get; set; }
    public DateTime? ExternalDate { get; set; }

    // تفاصيل الاستلام
    public DateTime ReceivedDate { get; set; }
    public TimeSpan? ReceivedTime { get; set; }
    
    public int EntityId { get; set; } // الجهة المرسلة
    public string Subject { get; set; } = string.Empty;
    public int? DocumentTypeId { get; set; }
    
    public ReceiveMethod ReceiveMethod { get; set; }
    
    // الموظف الذي استلم الكتاب (Hint: القارئ/الموظف العادي يرى فقط الكتب التي استلمها هو)
    public int ReceivedByUserId { get; set; }
    
    public IncomingStatus Status { get; set; } = IncomingStatus.New;
    
    /// <summary>
    /// القسم المحال إليه الكتاب (اختياري).
    /// Hint: يحلّ محلّ FolderName النصّي — الإحالة صارت إسناداً حقيقياً لقسم يراه موظفوه.
    /// </summary>
    public int? DepartmentId { get; set; }
    public Department? Department { get; set; }

    /// <summary>[مهجور] اسم القسم كنصّ حر — أُبقي للتوافق الخلفي فقط، والمصدر الآن DepartmentId.</summary>
    public string? FolderName { get; set; }
    
    public string? LastAction { get; set; } // وصف نصي لآخر إجراء تم
    public string? Keywords { get; set; }
    public string? Notes { get; set; }

    // الحقول المالية
    public decimal? Amount { get; set; }
    public Currency? Currency { get; set; }
    public decimal? ExchangeRate { get; set; }
    public decimal? AmountInIqd { get; set; } // يُحسب تلقائياً

    /// <summary>إذا تم الرد على هذا الكتاب الوارد بكتاب صادر (Hint: الربط العكسي).</summary>
    public int? ReplyOutgoingId { get; set; }

    // بيانات تتبع الإنشاء والتعديل
    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    // حذف ناعم
    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    // العلاقات (Navigation Properties)
    public Entity? Entity { get; set; }
    public OutgoingBook? ReplyOutgoing { get; set; }
}
