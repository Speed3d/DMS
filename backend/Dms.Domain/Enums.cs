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
