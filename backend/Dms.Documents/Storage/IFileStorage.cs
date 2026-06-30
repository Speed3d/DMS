namespace Dms.Documents.Storage;

/// <summary>
/// تجريد تخزين الملفات. التطبيق الحالي محلي (للـ Spike)؛
/// في الإنتاج يُستبدَل بتطبيق Azure Blob Storage دون تغيير بقية الكود.
/// قاعدة البيانات تحفظ المفتاح (BlobKey) فقط، والوصول يكون عبر الـ API.
/// </summary>
public interface IFileStorage
{
    /// <summary>يحفظ المحتوى ويعيد المفتاح (مسار/Key) الذي يُخزَّن في قاعدة البيانات.</summary>
    Task<string> SaveAsync(string suggestedName, byte[] content, CancellationToken ct = default);

    /// <summary>يجلب المحتوى عبر المفتاح.</summary>
    Task<byte[]> ReadAsync(string key, CancellationToken ct = default);

    Task<bool> ExistsAsync(string key, CancellationToken ct = default);

    Task DeleteAsync(string key, CancellationToken ct = default);
}
