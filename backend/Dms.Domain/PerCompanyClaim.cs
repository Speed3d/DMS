namespace Dms.Domain;

/// <summary>
/// ترميز قيمة تختلف **باختلاف الشركة** داخل نصّ واحد، بصيغة <c>شركة:قيمة,شركة:قيمة</c>
/// (مثال: <c>1:63,2:127</c>). تُستخدم لحمل صلاحيات المستخدم وقسمه لكل شركة في الـJWT (ADR-017).
/// </summary>
/// <remarks>
/// <para>
/// Hint: لماذا في التوكن لا في قاعدة البيانات؟ لأن <c>AppDbContext</c> يعتمد على
/// <c>ICurrentUser</c> (الفلتر العام للشركة يُبنى منه)، فلو احتاج <c>ICurrentUser</c> قاعدةَ
/// البيانات لحساب الصلاحيات لصار الاعتماد **دائرياً**. القراءة من الـclaims تحسم ذلك.
/// </para>
/// <para>
/// وموضعه في <c>Dms.Domain</c> منطقٌ نقي على نمط <see cref="RoleHierarchy"/> و
/// <see cref="IncomingWorkflow"/> — لأنه ما يفصل شركةً عن أخرى في كل طلب، فوجب أن يكون
/// قابلاً للاختبار وحده.
/// </para>
/// </remarks>
public static class PerCompanyClaim
{
    public static string Encode(IEnumerable<KeyValuePair<int, int>> byCompany) =>
        string.Join(",", byCompany.Select(p => $"{p.Key}:{p.Value}"));

    /// <summary>
    /// قيمة الشركة المطلوبة، أو <c>null</c> إن لم تكن في الخريطة أو كان النصّ مشوّهاً
    /// — **فشل مغلق** (لا صلاحية)، التزاماً بما نصّت عليه ADR-012.
    /// </summary>
    public static int? Read(string? claim, int? companyId)
    {
        if (companyId is null || string.IsNullOrWhiteSpace(claim)) return null;

        foreach (var part in claim.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var sep = part.IndexOf(':');
            if (sep <= 0) continue;
            if (!int.TryParse(part.AsSpan(0, sep), out var cid) || cid != companyId.Value) continue;
            return int.TryParse(part.AsSpan(sep + 1), out var value) ? value : null;
        }
        return null;
    }
}
