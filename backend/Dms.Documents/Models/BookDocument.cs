namespace Dms.Documents.Models;

/// <summary>
/// نموذج كتاب صادر — يمثّل الحقول التي تُطبع في الـ PDF/Word وتُوقَّع في الـ QR.
/// (نسخة مبسّطة لاختبار Phase 0 — تتوسّع لاحقاً مع كيانات قاعدة البيانات.)
/// </summary>
public sealed record BookDocument
{
    public required string CompanyName { get; init; }
    public required string Number { get; init; }      // مثال: DEN-2026-00124
    public required DateOnly Date { get; init; }
    public required string Entity { get; init; }       // الجهة المستلمة
    public required string Subject { get; init; }      // الموضوع
    public required string Body { get; init; }         // نص الكتاب (عربي RTL)

    // الحقول المالية (اختيارية)
    public decimal? Amount { get; init; }
    public string? Currency { get; init; }             // IQD / USD
    public decimal? ExchangeRate { get; init; }

    /// <summary>المعادل بالدينار العراقي (يُحسب ويُجمَّد لحظة الإنشاء/الاعتماد).</summary>
    public decimal? AmountInIqd =>
        Amount is null ? null
        : string.Equals(Currency, "USD", StringComparison.OrdinalIgnoreCase)
            ? Amount * (ExchangeRate ?? 0m)
            : Amount;

    public bool HasFinancials => Amount is not null;
}
