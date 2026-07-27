namespace Dms.Domain;

/// <summary>
/// إسناد كتاب وارد إلى قسم — كتاب واحد قد يُحال إلى **عدّة أقسام معاً** (ADR-018).
/// </summary>
/// <remarks>
/// <para>
/// لكل إسناد <see cref="Note"/> خاصة به: توجيه المالية يختلف عن توجيه المتابعة، وجمعهما في
/// ملاحظة واحدة يُفقد المعنى. أما الملاحظة المشتركة فتُدمَج في وصف سجل الحركة لكل قسم.
/// </para>
/// <para>
/// **فريد على (IncomingId, DepartmentId):** إعادة الإحالة لقسم موجود تُحدّث ملاحظته ولا
/// تُنشئ إسناداً ثانياً — وإلا تراكمت أسطر مكرّرة بلا معنى.
/// </para>
/// </remarks>
public class IncomingAssignment
{
    public int IncomingAssignmentId { get; set; }

    public int IncomingId { get; set; }
    public IncomingBook? Incoming { get; set; }

    public int DepartmentId { get; set; }
    public Department? Department { get; set; }

    /// <summary>ملاحظة/توجيه خاص بهذا القسم (اختياري).</summary>
    public string? Note { get; set; }

    public int AssignedByUserId { get; set; }
    public DateTime AssignedAt { get; set; }
}
