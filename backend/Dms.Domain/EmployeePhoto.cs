namespace Dms.Domain;

/// <summary>
/// قواعد صورة الموظف — **قاعدةٌ واحدة تحكم مسارَي الرفع** (ADR-035).
/// </summary>
/// <remarks>
/// 🔴 **لماذا في المجال لا في الخدمة؟** بعد فتح الرفع للموظف نفسه صار للصورة **مساران**:
/// شؤون الموظفين من بطاقته، وصاحبُها من بروفايله. ونسخُ الحدّ والصيغ في الموضعين يجعلهما
/// يفترقان بأول تعديل — فيُقبل في أحدهما ما يُرفض في الآخر، **والصورة واحدة**.
/// نظير <see cref="PayrollPayable"/> و<see cref="LeaveDecision"/>: القاعدة في موضعٍ واحد.
///
/// ⚠️ **والامتداد يُعاد ليُبنى منه مفتاح التخزين** — فلا يُشتقّ مرّتين باحتمال اختلاف.
/// </remarks>
public static class EmployeePhotoRules
{
    /// <summary>أقصى حجم مقبول — خمسة ميغابايت.</summary>
    public const long MaxBytes = 5 * 1024 * 1024;

    /// <summary>الصيغ المسموحة — صورٌ فقط، بلا صيغٍ قابلة للتنفيذ.</summary>
    public static readonly string[] AllowedExtensions = [".jpg", ".jpeg", ".png"];

    /// <summary>مفتاح تخزين صورة الموظف — **ثابتٌ للشخص** فتبقى صورةً واحدة له.</summary>
    public static string BlobKey(int employeeId, string extension) => $"emp-{employeeId}{extension}";

    /// <summary>
    /// يتحقّق من الحجم والصيغة، ويُعيد **الامتداد المُطبَّع** لبناء مفتاح التخزين.
    /// </summary>
    /// <exception cref="ValidationException">برسالةٍ عربية تُعرض للمستخدم كما هي.</exception>
    public static string Validate(string fileName, long length)
    {
        if (length == 0) throw new ValidationException("الملف فارغ.");
        if (length > MaxBytes) throw new ValidationException("حجم الصورة يتجاوز 5 ميغابايت.");

        var ext = Path.GetExtension(fileName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(ext))
            throw new ValidationException("صيغة الصورة غير مسموحة (JPG/PNG).");

        return ext;
    }
}
