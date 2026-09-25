using System.Collections.Concurrent;
using System.Text.Json;
using Dms.Domain;
using Dms.Infrastructure.Services;

namespace Dms.Infrastructure.Backup;

/// <summary>رفعٌ بدأ — معرّفه وحجم القطعة الذي ينتظره الخادم.</summary>
public sealed record UploadSession(string UploadId, int ChunkSize, long TotalBytes, long ReceivedBytes, int NextIndex);

public interface IBackupUploadService
{
    /// <summary>يبدأ رفع نسخةٍ من جهاز المستخدم — بعد فحص الاسم والحجم ومساحة القرص.</summary>
    UploadSession Start(string fileName, long totalBytes);

    /// <summary>يُلحق قطعةً بالترتيب. **إعادةُ قطعةٍ وصلت تُتجاهل** (طلبٌ ضاع ردُّه فأُعيد).</summary>
    Task<UploadSession> AppendAsync(string uploadId, int index, Stream body, CancellationToken ct = default);

    /// <summary>يتحقّق أن الرفع اكتمل ويعيد مسار الملف واسمه الأصليّ — قبل بدء الفحص الخلفيّ.</summary>
    (string PartPath, string OriginalName) EnsureComplete(string uploadId);

    /// <summary>يُلغي رفعاً ويحذف ما وصل منه.</summary>
    void Abort(string uploadId);
}

/// <summary>
/// **استعادة نسخةٍ من جهازٍ آخر** — الرفع بقطع (ADR-055).
/// </summary>
/// <remarks>
/// 🐛 **بلاغ المالك (2026-09-24)**: أخذ نسخةً على جهاز التطوير وأخرى على الدومين، ولم يستطع استعادة
/// أيٍّ منهما على الآخر — **لا طريق لإدخال نسخةٍ من خارج الخادم**. وهذا نفسه ما يلزم يوم يتعطّل الـMini PC.
/// <para>
/// 🔴 **القطعة ≤ 32 ميغابايت** — Cloudflare يرفض ما فوق 100 (قاعدة ADR-049). والملف يُكتب **على القرص
/// لا في الذاكرة**، فنسخةٌ بعدّة غيغابايتات لا تُثقل الخادم.
/// </para>
/// <para>
/// 🔑 **الرفع لا يستعيد** — الملف المكتمل يُفحص ثم **يصير نسخةً في القائمة**، والاستعادة بالطريق القائم
/// (نسخة أمان · تأكيد بالكتابة · متابعة). فلا مسارَ ثانٍ للاستعادة يتباعد عن الأوّل.
/// </para>
/// </remarks>
public sealed class BackupUploadService(AppPaths paths, ICurrentUser current) : IBackupUploadService
{
    /// <summary>حجم القطعة — أقلّ من حدّ Cloudflare (100) بهامشٍ واسع، وأقلّ من حدّ الطلب على النقطة.</summary>
    public const int ChunkSize = 32 * 1024 * 1024;

    /// <summary>أكبر جسمٍ تقبله نقطة القطعة (القطعة + هامش).</summary>
    public const long MaxChunkRequestBytes = 40L * 1024 * 1024;

    /// <summary>رفعٌ تُرك أكثر من هذا يُحذف عند بدء رفعٍ جديد.</summary>
    private static readonly TimeSpan StaleAfter = TimeSpan.FromHours(24);

    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Locks = new();
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private sealed record Meta(string FileName, long Total, long Received, int NextIndex, int? UserId, DateTime StartedUtc);

    private string Dir => Path.Combine(paths.BackupDir, "uploads");
    private string PartPath(string id) => Path.Combine(Dir, id + ".part");
    private string MetaPath(string id) => Path.Combine(Dir, id + ".json");

    public UploadSession Start(string fileName, long totalBytes)
    {
        var name = Path.GetFileName(fileName ?? "").Trim();
        if (!name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            throw new ValidationException("اختر ملف نسخةٍ احتياطية مضغوطاً (.zip) كما يُنزَّل من شاشة النسخ.");
        if (totalBytes <= 0)
            throw new ValidationException("الملف فارغ.");

        Directory.CreateDirectory(Dir);
        RemoveStale();

        // ⚠️ **ضِعفُ الحجم على الأقلّ** — الملف يُفكّ مؤقتاً عند الفحص وعند الاستعادة.
        var free = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(paths.BackupDir))!).AvailableFreeSpace;
        if (free < totalBytes * 2)
            throw new ValidationException(
                $"لا تكفي مساحة القرص على الخادم: الملف {Size(totalBytes)} ويلزم ضِعفُه ({Size(totalBytes * 2)}) " +
                $"والمتاح {Size(free)}.");

        var id = Guid.NewGuid().ToString("N");
        File.WriteAllBytes(PartPath(id), []);
        WriteMeta(id, new Meta(name, totalBytes, 0, 0, current.UserId, DateTime.UtcNow));
        return new UploadSession(id, ChunkSize, totalBytes, 0, 0);
    }

    public async Task<UploadSession> AppendAsync(string uploadId, int index, Stream body, CancellationToken ct = default)
    {
        var id = ValidId(uploadId);
        var gate = Locks.GetOrAdd(id, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            var meta = ReadMeta(id);
            // 🔑 **إعادةُ قطعةٍ وصلت لا تُلحَق ثانيةً** — طلبٌ وصل وضاع ردُّه فأعاده المتصفّح.
            if (index < meta.NextIndex) return Session(id, meta);
            if (index > meta.NextIndex)
                throw new ConflictException($"وصلت القطعة {index + 1} قبل القطعة {meta.NextIndex + 1} — أعد الرفع.");

            long written;
            await using (var file = new FileStream(PartPath(id), FileMode.Append, FileAccess.Write, FileShare.None))
            {
                var before = file.Length;
                await body.CopyToAsync(file, ct);
                written = file.Length - before;
            }

            if (written <= 0) throw new ValidationException("قطعةٌ فارغة.");
            var received = meta.Received + written;
            if (received > meta.Total)
            {
                Delete(id);
                throw new ValidationException("وصل أكثر من حجم الملف المُعلَن — أُلغي الرفع. أعد المحاولة.");
            }

            var next = meta with { Received = received, NextIndex = meta.NextIndex + 1 };
            WriteMeta(id, next);
            return Session(id, next);
        }
        finally { gate.Release(); }
    }

    public (string PartPath, string OriginalName) EnsureComplete(string uploadId)
    {
        var id = ValidId(uploadId);
        var meta = ReadMeta(id);
        if (meta.Received != meta.Total)
            throw new ValidationException($"الرفع لم يكتمل: وصل {Size(meta.Received)} من {Size(meta.Total)}.");
        return (PartPath(id), meta.FileName);
    }

    public void Abort(string uploadId) => Delete(ValidId(uploadId));

    // ─────────────────────────── مساعدات ───────────────────────────

    /// <summary>🔐 المعرّف يدخل في مسار ملف — فلا يُقبل إلا 32 حرفاً سداسياً (لا `..` ولا فواصل).</summary>
    private static string ValidId(string id) =>
        id is { Length: 32 } && id.All(Uri.IsHexDigit) ? id : throw new NotFoundException("الرفع غير موجود.");

    private Meta ReadMeta(string id)
    {
        var path = MetaPath(id);
        if (!File.Exists(path)) throw new NotFoundException("الرفع غير موجود أو انتهت صلاحيته — ابدأ من جديد.");
        return JsonSerializer.Deserialize<Meta>(File.ReadAllText(path), Json)
               ?? throw new NotFoundException("الرفع غير موجود.");
    }

    private void WriteMeta(string id, Meta meta) => File.WriteAllText(MetaPath(id), JsonSerializer.Serialize(meta, Json));

    private void Delete(string id)
    {
        try { File.Delete(PartPath(id)); } catch { /* أفضل جهد */ }
        try { File.Delete(MetaPath(id)); } catch { /* أفضل جهد */ }
        Locks.TryRemove(id, out _);
    }

    /// <summary>رفعٌ متروك (أُغلق المتصفّح في منتصفه) يُحذف بعد يوم — لا يتراكم على القرص.</summary>
    private void RemoveStale()
    {
        foreach (var meta in Directory.EnumerateFiles(Dir, "*.json"))
        {
            if (DateTime.UtcNow - File.GetLastWriteTimeUtc(meta) < StaleAfter) continue;
            Delete(Path.GetFileNameWithoutExtension(meta));
        }
    }

    private static UploadSession Session(string id, Meta m) => new(id, ChunkSize, m.Total, m.Received, m.NextIndex);

    internal static string Size(long b) =>
        b >= 1L << 30 ? $"{b / (double)(1L << 30):0.0} GB"
        : b >= 1L << 20 ? $"{b / (double)(1L << 20):0.0} MB"
        : $"{b / 1024.0:0} KB";
}
