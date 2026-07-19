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

/// <summary>نوع مالك المرفق/الإصدار.</summary>
public enum OwnerType
{
    Outgoing = 0,
    Archive = 1,
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
    All = Outgoing | Archive | Reports | Users | Settings | Backup, // 63
}

/// <summary>تحويل bitmask الأقسام إلى/من قائمة أسماء (لعقود الـ API).</summary>
public static class AppModuleExtensions
{
    private static readonly AppModule[] Individual =
        { AppModule.Outgoing, AppModule.Archive, AppModule.Reports, AppModule.Users, AppModule.Settings, AppModule.Backup };

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
