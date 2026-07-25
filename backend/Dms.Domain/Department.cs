namespace Dms.Domain;

/// <summary>
/// قسم داخل الشركة (الإدارة · المتابعة · المالية · الخارجية …).
///
/// Hint: يخدم غرضين مترابطين:
///  1) مكان عمل الموظف (<see cref="User.DepartmentId"/>).
///  2) وجهة إحالة الكتاب الوارد (<see cref="IncomingBook.DepartmentId"/>).
/// وباجتماعهما تصبح الإحالة **إسناداً حقيقياً**: الكتاب المحال لقسم يظهر تلقائياً
/// لموظفي ذلك القسم — بدل أن تكون مجرد نصّ لا يراه أحد.
/// </summary>
public class Department
{
    public int DepartmentId { get; set; }

    /// <summary>الشركة المالكة (عزل صفّي — لكل شركة أقسامها).</summary>
    public int CompanyId { get; set; }

    public string Name { get; set; } = string.Empty;

    /// <summary>قسم معطّل لا يظهر في قوائم الاختيار، لكن سجلاته السابقة تبقى سليمة.</summary>
    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; }
}
