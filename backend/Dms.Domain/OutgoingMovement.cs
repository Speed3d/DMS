namespace Dms.Domain;

/// <summary>
/// حركةٌ في سجلّ الكتاب الصادر — مَن أنشأه وعدّله واعتمده وربطه ومتى (ADR-056).
/// </summary>
/// <remarks>
/// 🔑 **نظيرُ `MovementLog` في الوارد** (طلب المالك 2026-09-25). كان الصادر يُسجَّل في سجلّ التدقيق وحده
/// (للسوبر أدمن)، **وسطرُ إنشائه بلا رقم الكتاب** فلا يُربط به — فلم يكن له سجلّ حركة يراه المستخدمون.
/// <para>
/// 🔐 **الوصف محايدٌ دائماً** («رُبط بكتابٍ وارد») — ورقم الوارد المرتبط في <see cref="RelatedIncomingId"/>
/// يُعرض **لمن يرى ذلك الوارد وحده** (قاعدة G20 — ADR-053: لا يُكتب رقمُ وحدةٍ أخرى في نصٍّ حرّ).
/// </para>
/// </remarks>
public class OutgoingMovement
{
    public int MovementId { get; set; }
    public int CompanyId { get; set; }
    public int OutgoingId { get; set; }
    public OutgoingBook? OutgoingBook { get; set; }

    /// <summary>رمز الإجراء — `Created` · `Edited` · `Approved` · `EditedApproved` · `LinkedIncoming` · `UnlinkedIncoming` · `Deleted`.</summary>
    public string Action { get; set; } = string.Empty;

    /// <summary>الوصف للعرض — محايدٌ لا يحمل رقم كتابٍ من وحدةٍ أخرى.</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>الوارد المرتبط (للربط وفكّه) — يُعرض رقمه لمن يراه وحده.</summary>
    public int? RelatedIncomingId { get; set; }

    public int PerformedByUserId { get; set; }
    public DateTime PerformedAt { get; set; }
}

/// <summary>رموز إجراءات سجلّ الصادر — مصدرٌ واحد للخادم والاختبارات.</summary>
public static class OutgoingActions
{
    public const string Created = "Created";
    public const string Edited = "Edited";
    public const string Approved = "Approved";
    public const string EditedApproved = "EditedApproved";
    public const string LinkedIncoming = "LinkedIncoming";
    public const string UnlinkedIncoming = "UnlinkedIncoming";
    public const string Deleted = "Deleted";
}

/// <summary>ما يُقارَن بين نسختين من الصادر لمعرفة ما تغيّر.</summary>
public sealed record OutgoingFields(
    int EntityId, int? TemplateId, DateTime Date, string? HeaderPhrase,
    string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate)
{
    public static OutgoingFields Of(OutgoingBook b) => new(
        b.EntityId, b.TemplateId, b.Date, b.HeaderPhrase, b.SignatoryName, b.SignatoryTitle,
        b.Subject, b.BodyHtml, b.Amount, b.Currency, b.ExchangeRate);
}

/// <summary>
/// «ماذا تغيّر؟» — أسماءُ الحقول بالعربية بترتيبٍ ثابت (ADR-056). **دالّةٌ نقيّة** تُختبر.
/// </summary>
/// <remarks>
/// 🔑 **أسماءٌ لا قيم** — القيمة القديمة قد تكون مبلغاً أو نصّاً طويلاً، والسجلّ يقرؤه كلُّ مَن يرى الكتاب؛
/// والنسخ الكاملة محفوظةٌ في إصدارات الكتاب المعتمد (`DocumentVersion`) لمن يحتاجها.
/// </remarks>
public static class OutgoingChanges
{
    public static IReadOnlyList<string> Describe(OutgoingFields before, OutgoingFields after)
    {
        var changed = new List<string>();
        if (before.Subject.Trim() != after.Subject.Trim()) changed.Add("الموضوع");
        if (before.BodyHtml != after.BodyHtml) changed.Add("المتن");
        if (before.EntityId != after.EntityId) changed.Add("الجهة");
        if (before.Date.Date != after.Date.Date) changed.Add("التاريخ");
        if (before.Amount != after.Amount || before.Currency != after.Currency || before.ExchangeRate != after.ExchangeRate)
            changed.Add("المبلغ");
        if (Norm(before.HeaderPhrase) != Norm(after.HeaderPhrase)) changed.Add("عبارة الافتتاح");
        if (Norm(before.SignatoryName) != Norm(after.SignatoryName) || Norm(before.SignatoryTitle) != Norm(after.SignatoryTitle))
            changed.Add("الموقّع");
        if (before.TemplateId != after.TemplateId) changed.Add("القالب");
        return changed;
    }

    /// <summary>نصُّ الحركة: «تعديل: الموضوع · المبلغ» — أو «حفظ بلا تغيير».</summary>
    public static string Summary(string prefix, IReadOnlyList<string> changed) =>
        changed.Count == 0 ? $"{prefix} بلا تغييرٍ في المحتوى" : $"{prefix}: {string.Join(" · ", changed)}";

    private static string Norm(string? s) => (s ?? "").Trim();
}
