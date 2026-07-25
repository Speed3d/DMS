using System.Collections.Concurrent;

namespace Dms.Infrastructure.Documents;

/// <summary>
/// تخزين مؤقت لصور القوالب المُجهَّزة (ترويسة · تذييل · علامة مائية بعد تطبيق الشفافية).
/// </summary>
/// <remarks>
/// <para>
/// كانت هذه الصور تُقرأ من التخزين — وتُعالَج شفافية العلامة المائية — **في كل توليد PDF**،
/// رغم أنها ثابتة لكل قالب. وقياسٌ فعلي أظهر أن توليد معاينة واحدة يستغرق ~2.1 ثانية، وهو ما
/// يجعل المعاينة ثقيلة على السيرفر الداخلي (ADR-016) مع عدّة مستخدمين.
/// </para>
/// <para>
/// <b>لماذا هذا آمن بلا إبطال يدوي:</b> مفتاح التخزين يحمل <c>Guid</c> فريداً لكل رفع
/// (<c>yyyy/MM/{guid}_name</c>)، فرفعُ صورة جديدة يُنتج مفتاحاً جديداً ⇒ المدخل القديم لا
/// يُستعلَم عنه ثانيةً. لا خطر عرض صورة قديمة بعد التحديث.
/// </para>
/// <para>
/// مُسجَّل <b>singleton</b> عمداً — <c>BookRenderer</c> نفسه scoped، فلو كان التخزين بداخله
/// لضاع مع كل طلب ولم يُفِد شيئاً.
/// </para>
/// </remarks>
public sealed class TemplateAssetCache
{
    /// <summary>سقف احترازي: الصور قليلة بطبيعتها (٣ لكل قالب) والتجاوز يعني تسرّباً.</summary>
    private const int MaxEntries = 128;

    private readonly ConcurrentDictionary<string, byte[]> _items = new();

    /// <summary>
    /// يُعيد الصورة المخزَّنة، أو يبنيها بـ<paramref name="factory"/> ويخزّنها.
    /// </summary>
    /// <remarks>
    /// Hint: تسابقُ خيطين على نفس المفتاح قد يُنفّذ <paramref name="factory"/> مرتين — مقبول
    /// لأنها عملية عديمة الأثر (قراءة ملف)، والبديل قفلٌ يُبطئ الحالة الشائعة.
    /// </remarks>
    public async Task<byte[]> GetOrAddAsync(string cacheKey, Func<Task<byte[]>> factory)
    {
        if (_items.TryGetValue(cacheKey, out var cached)) return cached;

        var value = await factory();

        if (_items.Count >= MaxEntries) _items.Clear();
        _items[cacheKey] = value;
        return value;
    }
}
