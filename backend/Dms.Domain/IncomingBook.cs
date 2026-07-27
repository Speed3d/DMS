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
    /// الأقسام المُحال إليها الكتاب — **قد تكون أكثر من واحد في آنٍ معاً** (ADR-018).
    /// </summary>
    /// <remarks>
    /// Hint: كان الكتاب يُحال لقسم **واحد** (<c>DepartmentId</c> مفرد يحلّ محلّ <c>FolderName</c>
    /// النصّي)، فتعذّر أن يعمل قسمان عليه بالتوازي — وكان لا بدّ من انتظار أحدهما ليُعيد إحالته.
    /// صار الإسناد علاقةً متعدّدة، ولكل إسناد **ملاحظته الخاصة** لأن توجيه المالية يختلف عن
    /// توجيه المتابعة. والإحالة **تراكمية**: تُضيف أقساماً ولا تُزيح الموجود (قرار المالك) —
    /// لأن الإزاحة الضمنية تُفقد قسماً كتابَه بلا أن يقصد أحد.
    /// </remarks>
    public ICollection<IncomingAssignment> Assignments { get; set; } = new List<IncomingAssignment>();

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
