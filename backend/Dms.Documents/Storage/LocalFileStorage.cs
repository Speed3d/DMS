namespace Dms.Documents.Storage;

/// <summary>
/// تخزين محلي على القرص — للاختبار والتطوير فقط.
/// يُحاكي سلوك Blob: يحفظ بمفتاح فريد ويعيده.
/// </summary>
public sealed class LocalFileStorage : IFileStorage
{
    private readonly string _root;

    public LocalFileStorage(string root)
    {
        _root = root;
        Directory.CreateDirectory(_root);
    }

    private string GetSafePath(string key)
    {
        var fullPath = Path.GetFullPath(Path.Combine(_root, key));
        var rootPath = Path.GetFullPath(_root);
        if (!fullPath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase))
            throw new UnauthorizedAccessException("محاولة وصول غير مشروعة لملف خارج المجلد المسموح.");
        return fullPath;
    }

    public async Task<string> SaveAsync(string suggestedName, byte[] content, CancellationToken ct = default)
    {
        // مفتاح فريد يشبه نمط Blob: yyyy/MM/guid_name
        var safeName = Path.GetFileName(suggestedName);
        var key = $"{DateTime.UtcNow:yyyy/MM}/{Guid.NewGuid():N}_{safeName}";
        var fullPath = GetSafePath(key);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        await File.WriteAllBytesAsync(fullPath, content, ct);
        return key;
    }

    public async Task<byte[]> ReadAsync(string key, CancellationToken ct = default)
    {
        var fullPath = GetSafePath(key);
        return await File.ReadAllBytesAsync(fullPath, ct);
    }

    public Task<bool> ExistsAsync(string key, CancellationToken ct = default)
        => Task.FromResult(File.Exists(GetSafePath(key)));

    public Task DeleteAsync(string key, CancellationToken ct = default)
    {
        var fullPath = GetSafePath(key);
        if (File.Exists(fullPath)) File.Delete(fullPath);
        return Task.CompletedTask;
    }
}

