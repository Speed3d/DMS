namespace Dms.Domain;

/// <summary>
/// الجهة (المُراسِل): جهة صادرة/مستلمة تُدخَل مرة وتُختار من قائمة منسدلة.
/// (سُمّيت Entity مطابقةً لمصطلح الخطة "الجهات/Entities".)
/// </summary>
public class Entity
{
    public int EntityId { get; set; }
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;
    public EntityKind Kind { get; set; } = EntityKind.Both;
    public string? Notes { get; set; }
}

/// <summary>نوع الكتاب/المستند — قائمة مُدارة.</summary>
public class DocumentType
{
    public int DocumentTypeId { get; set; }
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;
}
