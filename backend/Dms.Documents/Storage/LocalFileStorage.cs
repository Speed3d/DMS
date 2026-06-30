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

    public async Task<string> SaveAsync(string suggestedName, byte[] content, CancellationToken ct = default)
    {
        // مفتاح فريد يشبه نمط Blob: yyyy/MM/guid_name
        var safeName = Path.GetFileName(suggestedName);
        var key = $"{DateTime.UtcNow:yyyy/MM}/{Guid.NewGuid():N}_{safeName}";
        var fullPath = Path.Combine(_root, key);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        await File.WriteAllBytesAsync(fullPath, content, ct);
        return key;
    }

    public async Task<byte[]> ReadAsync(string key, CancellationToken ct = default)
    {
        var fullPath = Path.Combine(_root, key);
        return await File.ReadAllBytesAsync(fullPath, ct);
    }

    public Task<bool> ExistsAsync(string key, CancellationToken ct = default)
        => Task.FromResult(File.Exists(Path.Combine(_root, key)));

    public Task DeleteAsync(string key, CancellationToken ct = default)
    {
        var fullPath = Path.Combine(_root, key);
        if (File.Exists(fullPath)) File.Delete(fullPath);
        return Task.CompletedTask;
    }
}

