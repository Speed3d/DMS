namespace Dms.Domain;

/// <summary>
/// سعر صرف يُدار مركزياً (لتعبئة القيمة الافتراضية عند الإدخال).
/// المعادل بالدينار يُجمَّد على الكتاب لحظة الإنشاء فلا يتأثر بتغيّر السعر لاحقاً.
/// </summary>
public class ExchangeRate
{
    public int ExchangeRateId { get; set; }
    public Currency Currency { get; set; }
    public decimal Rate { get; set; }
    public DateTime EffectiveDate { get; set; }
    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
}
