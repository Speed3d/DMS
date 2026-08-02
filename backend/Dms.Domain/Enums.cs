namespace Dms.Domain;

/// <summary>
/// الأدوار الهرمية. القيمة الأصغر = صلاحية أعلى.
/// القاعدة: كل دور يدير المستويات الأدنى منه فقط (Level أكبر).
/// </summary>
public enum UserRole
{
    SuperAdmin = 1,
    President = 2,
    Manager = 3,
    Employee = 4,
    Reader = 5,
}

/// <summary>حالة الكتاب الصادر.</summary>
public enum BookStatus
{
    Draft = 0,
    Final = 1,
}

/// <summary>العملة.</summary>
public enum Currency
{
    IQD = 0,
    USD = 1,
}

/// <summary>نوع الجهة.</summary>
public enum EntityKind
{
    Outgoing = 0,   // صادرة
    Incoming = 1,   // مستلمة
    Both = 2,       // كلاهما
}

/// <summary>حالة الكتاب الوارد.</summary>
public enum IncomingStatus
{
    New        = 0,   // جديد — تم الاستلام لكن لم يُراجع بعد
    InReview   = 1,   // قيد المراجعة — قيد الدراسة من القسم المختص
    Replied    = 2,   // تم الرد — تم إصدار كتاب صادر كرد
    Closed     = 3,   // مغلق — لا يحتاج إجراء إضافي
    Archived   = 4,   // مؤرشف — أرشفة نهائية
}

/// <summary>طريقة استلام الكتاب الوارد.</summary>
public enum ReceiveMethod
{
    Manual = 0,   // يدوي — تسليم باليد
    Mail   = 1,   // بريد — بريد عادي
    Email  = 2,   // بريد إلكتروني
}

/// <summary>نوع مالك المرفق/الإصدار.</summary>
public enum OwnerType
{
    Outgoing = 0,
    Archive = 1,
    Incoming = 2,

    /// <summary>مستمسكات الموظف (هوية · عقد · شهادات). الوصول يُفحص عبر إسناد الموظف لا عبر مُنشئه.</summary>
    Employee = 3,
}

/// <summary>لغة إيصال استلام الراتب — الشركة توظّف عمالاً أجانب لا يقرؤون العربية.</summary>
public enum ReceiptLanguage
{
    Arabic = 0,
    English = 1,
}

/// <summary>سبب إنهاء خدمة الموظف.</summary>
public enum TerminationReason
{
    Resignation = 0,   // استقالة
    Termination = 1,   // فصل
    Retirement  = 2,   // تقاعد
    Death       = 3,   // وفاة
    Other       = 4,   // أخرى
}

/// <summary>كيف تُحسب أيام العمل في الشهر.</summary>
public enum WorkingDaysMode
{
    /// <summary>عدد ثابت (30 عرفاً) مهما كان طول الشهر — الافتراض بطلب المالك.</summary>
    Fixed = 0,

    /// <summary>عدد أيام الشهر التقويمي فعلياً (28–31).</summary>
    Calendar = 1,
}

/// <summary>حالة كشف رواتب الشهر.</summary>
public enum PayrollStatus
{
    Draft = 0,   // مسودة — قابلة للتعديل
    Paid  = 1,   // مُسدَّد — مجمَّد
}

/// <summary>حالة دفع راتب موظف في كشف شهر بعينه.</summary>
public enum PayrollPaymentStatus
{
    Unpaid             = 0,   // لم يُصرف
    PaidByThisCompany  = 1,   // صرفته هذه الشركة
    PaidByOtherCompany = 2,   // صُرف من شركة أخرى يعمل فيها (ADR-024)
}

/// <summary>
/// أقسام النظام لصلاحيات الوصول (مستوى «وصول/لا‑وصول»). تُخزَّن كـ bitmask على المستخدم.
/// طبقة تقييد فوق الأدوار: السوبر أدمن ورئيس الشركة معفيان دائماً (All).
/// </summary>
[Flags]
public enum AppModule
{
    None = 0,
    Outgoing = 1,
    Archive = 2,
    Reports = 4,
    Users = 8,
    Settings = 16,
    Backup = 32,
    Incoming = 64,

    /// <summary>الموظفون والرواتب (ADR-023). **خارج <see cref="All"/> عمداً** — انظر تعليقها.</summary>
    HR = 128,

    /// <summary>
    /// الأقسام الافتراضية لأي إسناد جديد — **بلا HR عمداً (127 لا 255)**.
    /// </summary>
    /// <remarks>
    /// ⚠️ لماذا لا تشمل HR؟ لأن هذه القيمة هي **الافتراض** في ثلاثة مواضع صامتة:
    /// <c>UserCompany.Modules</c> المُهيَّأة، و<c>UserService.ResolveModules</c> حين ينشئ مديرٌ
    /// مستخدماً بلا تحديد أقسام، والمهاجرة على الصفوف القائمة. لو ضُمّت HR إليها لحصل **كل
    /// مستخدم جديد** على رؤية رواتب الشركة كلها بلا أن يمنحه أحدٌ ذلك — والرواتب أحسّ بيانات
    /// في النظام. الوصول لـHR **يُمنح صراحةً أو لا يُمنح**.
    /// </remarks>
    All = Outgoing | Archive | Reports | Users | Settings | Backup | Incoming, // 127

    /// <summary>كل شيء بلا استثناء (255) — للأدوار المعفاة وحدها: السوبر أدمن ورئيس الشركة.</summary>
    AllWithHr = All | HR, // 255
}

/// <summary>تحويل bitmask الأقسام إلى/من قائمة أسماء (لعقود الـ API).</summary>
public static class AppModuleExtensions
{
    // ⚠️ **كل قسم جديد يجب أن يُضاف هنا** — هذه المصفوفة هي ما يُترجم الـbitmask إلى أسماء
    //    وبالعكس. قسمٌ غائب عنها يُسقَط **صامتاً** في `ToNames` و`FromNames`، فلا يظهر مربّعه
    //    في شاشة المستخدمين ولا تُحفظ صلاحيته أبداً — وهو نمط «ميزة بلا مدخل» الذي كلّف
    //    المشروع ثلاث فجوات (G7 · G8 · G10).
    private static readonly AppModule[] Individual =
    {
        AppModule.Outgoing, AppModule.Archive, AppModule.Reports, AppModule.Users,
        AppModule.Settings, AppModule.Backup, AppModule.Incoming, AppModule.HR,
    };

    public static List<string> ToNames(this AppModule m) =>
        Individual.Where(x => (m & x) == x).Select(x => x.ToString()).ToList();

    /// <summary>أسماء → bitmask. الأسماء غير المعروفة تُتجاهل.</summary>
    public static AppModule FromNames(IEnumerable<string> names)
    {
        var result = AppModule.None;
        foreach (var n in names)
            if (Enum.TryParse<AppModule>(n, ignoreCase: true, out var v) && Individual.Contains(v))
                result |= v;
        return result;
    }
}
