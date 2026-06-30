namespace Dms.Domain;

/// <summary>
/// تفويض صلاحية الاعتماد لموظف (دائم أو مؤقت بمدّة) لتغطية غياب المدير.
/// يُسجَّل في التدقيق، وينتهي تلقائياً عند تجاوز EndDate.
/// </summary>
public class ApprovalDelegation
{
    public int DelegationId { get; set; }
    public int CompanyId { get; set; }
    public int FromUserId { get; set; }
    public int ToUserId { get; set; }
    public DateTime StartDate { get; set; }

    /// <summary>null = تفويض دائم (نائب).</summary>
    public DateTime? EndDate { get; set; }

    public bool IsActive { get; set; } = true;
    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
}
