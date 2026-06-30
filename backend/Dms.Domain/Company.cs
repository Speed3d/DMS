namespace Dms.Domain;

/// <summary>شركة ضمن النظام متعدد الشركات (لكل شركة قوالبها ورمز ترقيمها).</summary>
public class Company
{
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;

    /// <summary>رمز الترقيم، مثل DEN — يدخل في رقم الكتاب DEN-2026-00124.</summary>
    public string Prefix { get; set; } = string.Empty;

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }

    public ICollection<Template> Templates { get; set; } = new List<Template>();
}
