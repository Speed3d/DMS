namespace Dms.Domain;

/// <summary>مرفق ملف (يخص كتاباً صادراً أو مستند أرشيف). يُخزَّن في Blob ويُحفظ مفتاحه فقط.</summary>
public class Attachment
{
    public int AttachmentId { get; set; }
    public OwnerType OwnerType { get; set; }
    public int OwnerId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string BlobKey { get; set; } = string.Empty;
    public string FileType { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public int UploadedByUserId { get; set; }
    public DateTime UploadedAt { get; set; }
}

/// <summary>سناب-شوت لنسخة سابقة من مستند بعد تعديله (سجل الإصدارات).</summary>
public class DocumentVersion
{
    public int VersionId { get; set; }
    public OwnerType DocType { get; set; }
    public int DocId { get; set; }
    public int VersionNo { get; set; }

    /// <summary>محتوى النسخة السابقة كـ JSON.</summary>
    public string SnapshotJson { get; set; } = string.Empty;

    public int ChangedByUserId { get; set; }
    public DateTime ChangedAt { get; set; }
    public string? ChangeNote { get; set; }
}

/// <summary>
/// عدّاد ترقيم منفصل لكل (شركة + سنة + نوع). يُستخدم داخل Transaction لمنع التكرار،
/// ويُصفَّر سنوياً ببدء سنة جديدة (سجل جديد).
/// </summary>
public class Counter
{
    public int CompanyId { get; set; }
    public int Year { get; set; }
    public string Type { get; set; } = string.Empty; // Outgoing / Archive
    public int LastNumber { get; set; }
}

/// <summary>سجل تدقيق: تسجيل تلقائي لكل عملية مع المستخدم والوقت.</summary>
public class AuditLog
{
    public long LogId { get; set; }
    public int? UserId { get; set; }
    public int? CompanyId { get; set; }
    public string Action { get; set; } = string.Empty;       // Create/Update/Delete/Approve/Login...
    public string EntityType { get; set; } = string.Empty;   // OutgoingBook/User/Company...
    public string? EntityId { get; set; }
    public string? Details { get; set; }
    public DateTime Timestamp { get; set; }
}
