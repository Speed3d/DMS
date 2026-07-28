using System.Data;
using System.IO.Compression;
using System.Text.Json;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace Dms.Infrastructure.Backup;

public sealed record UpdateScheduleInput(BackupFrequency Frequency, bool Enabled, int Hour);

public interface IBackupService
{
    /// <summary>ينشئ نسخة احتياطية بالنطاق والتصنيف المحدّدين، ثم يقلّم النسخ الزائدة عن السقف.</summary>
    Task<BackupRecord> RunAsync(BackupType type, BackupScope scope, RetentionCategory category, CancellationToken ct = default);

    Task<List<BackupRecord>> ListAsync(CancellationToken ct = default);
    Task<BackupSchedule> GetScheduleAsync(CancellationToken ct = default);
    Task<BackupSchedule> UpdateScheduleAsync(UpdateScheduleInput input, CancellationToken ct = default);
    Task<(byte[] bytes, string fileName)> DownloadAsync(int id, CancellationToken ct = default);

    /// <summary>يحذف نسخة احتياطية (السجلّ + الملف). Hint: يُمنع حذف آخر نسخة ناجحة.</summary>
    Task DeleteAsync(int id, CancellationToken ct = default);

    /// <summary>
    /// يستعيد قاعدة البيانات والملفات من نسخة احتياطية. عملية تدميرية — تتطلب تأكيداً صريحاً.
    /// Hint: تأخذ نسخة أمان أولاً، ثم تدخل وضع الصيانة، فتستبدل القاعدة والملفات بالكامل.
    /// </summary>
    Task RestoreAsync(int backupRecordId, string confirmation, CancellationToken ct = default);
}

/// <summary>
/// نسخ احتياطي واستعادة.
/// النسخة = BACKUP DATABASE (.bak) [+ ملفات التخزين عند النطاق الكامل] مضغوطة في أرشيف ZIP واحد.
/// يُدار من السوبر أدمن فقط (تُفرَض الصلاحية في الـ Controller).
/// Hint: نطاق «قاعدة فقط» يجعل الرفع اليومي خفيفاً؛ سياسة الاحتفاظ تمنع تراكم النسخ للأبد.
/// </summary>
public sealed class BackupService(
    AppDbContext db, AppPaths paths, IConfiguration config, ICurrentUser current,
    IAuditService audit, IMaintenanceState maintenance) : IBackupService
{
    /// <summary>كلمة التأكيد المطلوبة للاستعادة (Hint: حاجز ثانٍ فوق صلاحية السوبر أدمن).</summary>
    public const string RestoreConfirmation = "استعادة";

    public async Task<BackupRecord> RunAsync(
        BackupType type, BackupScope scope, RetentionCategory category, CancellationToken ct = default)
    {
        var (zipName, size, status, note) = await CreateArchiveAsync(scope, ct);

        var record = new BackupRecord
        {
            CreatedAt = DateTime.UtcNow,
            CreatedByUserId = current.UserId,
            FileName = zipName,
            SizeBytes = size,
            Type = type,
            Scope = scope,
            Category = category,
            Status = status,
            Note = note,
        };
        db.BackupRecords.Add(record);
        audit.Add("Backup", nameof(BackupRecord), null, $"نسخة {category}/{scope} ({status})", null);
        await db.SaveChangesAsync(ct);

        // Hint: نقلّم بعد النجاح فقط — لا نحذف نسخاً قديمة سليمة لإفساح المجال لنسخة فشلت.
        if (status == BackupStatus.Success)
            await PruneAsync(category, ct);

        return record;
    }

    // ─────────────────────────── إنشاء الأرشيف (بلا كتابة في القاعدة) ───────────────────────────

    /// <summary>
    /// ينشئ أرشيف ZIP على القرص ويعيد بياناته. لا يكتب في قاعدة البيانات.
    /// Hint: مفصول عن RunAsync ليستخدمه مسار الاستعادة أيضاً (نسخة الأمان قبل الاستبدال) —
    /// حيث لا يصحّ الاعتماد على سجلّ قاعدة سيُستبدَل بعد لحظات.
    /// </summary>
    private async Task<(string zipName, long size, BackupStatus status, string? note)> CreateArchiveAsync(
        BackupScope scope, CancellationToken ct)
    {
        Directory.CreateDirectory(paths.BackupDir);
        var ts = DateTime.Now.ToString("yyyyMMdd-HHmmss");
        var zipName = $"backup-{ts}.zip";
        var zipPath = Path.Combine(paths.BackupDir, zipName);
        var bakPath = Path.Combine(paths.BackupDir, $"db-{ts}.bak");

        var status = BackupStatus.Success;
        string? note = null;

        // 1) نسخ قاعدة البيانات (على اتصال مستقل لتفادي استراتيجية إعادة المحاولة/المعاملات).
        try
        {
            await BackupDatabaseAsync(bakPath, compression: true, ct);
        }
        catch (Exception)
        {
            // بعض إصدارات SQL Server (Express/LocalDB) لا تدعم COMPRESSION — أعد المحاولة بدونها.
            try
            {
                await BackupDatabaseAsync(bakPath, compression: false, ct);
            }
            catch (Exception ex2)
            {
                status = BackupStatus.Failed;
                note = "تعذّر نسخ قاعدة البيانات: " + ex2.Message;
            }
        }

        // 2) ضغط (نسخة القاعدة إن وُجدت + ملفات التخزين عند النطاق الكامل فقط) في أرشيف واحد.
        try
        {
            using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);
            if (File.Exists(bakPath))
                zip.CreateEntryFromFile(bakPath, "database.bak", CompressionLevel.Optimal);

            // Hint: النطاق «قاعدة فقط» يتخطّى الملفات — الوثائق لا تتغيّر بعد إنشائها، فنسخها يومياً هدر.
            if (scope == BackupScope.Full && Directory.Exists(paths.StorageRoot))
            {
                foreach (var file in Directory.EnumerateFiles(paths.StorageRoot, "*", SearchOption.AllDirectories))
                {
                    var rel = "files/" + Path.GetRelativePath(paths.StorageRoot, file).Replace('\\', '/');
                    zip.CreateEntryFromFile(file, rel, CompressionLevel.Optimal);
                }
            }

            // ⚠️ **بيان الملفات — يُكتب في كل نسخة مهما كان نطاقها.**
            //
            // نسخةُ «قاعدة فقط» لا تحوي المرفقات، فاستعادتها تُنتج نظاماً سليم البيانات
            // **وكل زرّ مرفق فيه يقول «الملف غير موجود»** — عطلٌ صامت يُكتشف بعد أسابيع
            // ملفاً ملفاً. البيان يجعل النظام قادراً على قول: «استُعيدت القاعدة، و٦٤٣٢ ملفاً
            // مفقود — استعدها من نسختك الكاملة». **كشفُ حساب لا حماية**، وهذا دوره بالضبط.
            //
            // Hint: المسار والحجم يكفيان لكشف الفقد، ولا نحسب بصمة تجزئة — على 80 غيغا
            //       تستغرق دقائق طويلة في كل نسخة يومية مقابل فائدة لا نحتاجها هنا.
            WriteManifest(zip, paths.StorageRoot);
        }
        catch (Exception ex)
        {
            status = BackupStatus.Failed;
            note = (note is null ? "" : note + " | ") + "تعذّر ضغط الملفات: " + ex.Message;
        }
        finally
        {
            if (File.Exists(bakPath)) File.Delete(bakPath);
        }

        var size = File.Exists(zipPath) ? new FileInfo(zipPath).Length : 0;
        return (zipName, size, status, note);
    }

    private async Task BackupDatabaseAsync(string bakPath, bool compression, CancellationToken ct)
    {
        var connStr = config.GetConnectionString("Default")!;
        var dbName = new SqlConnectionStringBuilder(connStr).InitialCatalog;
        await using var conn = new SqlConnection(connStr);
        await conn.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        var options = compression ? "WITH INIT, FORMAT, COMPRESSION" : "WITH INIT, FORMAT";
        cmd.CommandText = $"BACKUP DATABASE [{dbName}] TO DISK = @path {options}";
        cmd.Parameters.Add(new SqlParameter("@path", bakPath));
        cmd.CommandTimeout = 300;
        await cmd.ExecuteNonQueryAsync(ct);
    }

    // ─────────────────────────── سياسة الاحتفاظ (التقليم) ───────────────────────────

    /// <summary>
    /// يحذف النسخ الناجحة الزائدة عن سقف التصنيف (الأقدم أولاً) — سجلّاً وملفّاً.
    /// Hint: يقتصر على تصنيف واحد حتى لا تؤثر النسخ اليومية على الشهرية. يحذف ملفات backup-*.zip فقط.
    /// </summary>
    private async Task PruneAsync(RetentionCategory category, CancellationToken ct)
    {
        var keep = BackupRetention.KeepFor(category);

        // النسخ الناجحة لهذا التصنيف، الأحدث أولاً. لا نحذف الفاشلة (لا ملفات لها غالباً) ولا نعدّها.
        var records = await db.BackupRecords
            .Where(r => r.Category == category && r.Status == BackupStatus.Success)
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync(ct);

        var toDelete = records.Skip(keep).ToList();
        if (toDelete.Count == 0) return;

        foreach (var rec in toDelete)
        {
            try
            {
                var path = Path.Combine(paths.BackupDir, rec.FileName);
                // حارس أمان: لا نحذف إلا ملفات النسخ الاحتياطية بنمطها المعروف داخل مجلد النسخ.
                if (File.Exists(path) && Path.GetFileName(rec.FileName).StartsWith("backup-", StringComparison.Ordinal))
                    File.Delete(path);
            }
            catch
            {
                // Hint: فشل حذف ملف لا يجب أن يُفشِل عملية النسخ — نُبقي السجلّ لإعادة المحاولة لاحقاً.
                continue;
            }
            db.BackupRecords.Remove(rec);
        }
        await db.SaveChangesAsync(ct);
    }

    // ─────────────────────────── الاستعادة ───────────────────────────

    public async Task RestoreAsync(int backupRecordId, string confirmation, CancellationToken ct = default)
    {
        if (!string.Equals(confirmation?.Trim(), RestoreConfirmation, StringComparison.Ordinal))
            throw new ValidationException($"للتأكيد، أرسل كلمة «{RestoreConfirmation}» في حقل التأكيد.");

        var rec = await db.BackupRecords.FirstOrDefaultAsync(r => r.BackupRecordId == backupRecordId, ct)
                  ?? throw new NotFoundException("سجلّ النسخة غير موجود.");
        if (rec.Status != BackupStatus.Success)
            throw new ValidationException("لا يمكن الاستعادة من نسخة فاشلة.");

        var zipPath = Path.Combine(paths.BackupDir, rec.FileName);
        if (!File.Exists(zipPath))
            throw new NotFoundException("ملف النسخة غير موجود على الخادم.");

        // عدد الملفات التي تتوقّعها القاعدة المُستعادة ولا وجود لها على القرص (نسخة بلا ملفات).
        var missingFiles = 0;

        // تحقّق مبكر من سلامة الأرشيف قبل لمس أي شيء.
        bool hasDb, hasFiles;
        try
        {
            using var probe = ZipFile.OpenRead(zipPath);
            hasDb = probe.GetEntry("database.bak") is not null;
            hasFiles = probe.Entries.Any(e => e.FullName.StartsWith("files/", StringComparison.Ordinal));
        }
        catch (Exception ex)
        {
            throw new ValidationException("أرشيف النسخة تالف أو غير قابل للقراءة: " + ex.Message);
        }
        if (!hasDb)
            throw new ValidationException("الأرشيف لا يحتوي نسخة قاعدة بيانات (database.bak).");

        var userId = current.UserId;
        var restoreUserId = userId; // نحتفظ به لتسجيله بعد عودة القاعدة (الجلسة تنقطع أثناء الاستعادة).

        // Hint: نسخة أمان كاملة قبل أي استبدال — تجعل الاستعادة نفسها قابلة للتراجع. تُنشأ قبل وضع الصيانة
        //       لأنها تحتاج القاعدة متصلة، وسجلّها في القاعدة سيُستبدَل فنعيد تسجيله بعد الاستعادة.
        var (safetyZip, safetySize, safetyStatus, safetyNote) = await CreateArchiveAsync(BackupScope.Full, ct);

        var tempDir = Path.Combine(paths.BackupDir, $"restore-{DateTime.Now:yyyyMMdd-HHmmss}");
        maintenance.Enter("جارٍ استعادة نسخة احتياطية — النظام متوقّف مؤقتاً.");
        try
        {
            Directory.CreateDirectory(tempDir);
            ZipFile.ExtractToDirectory(zipPath, tempDir);
            var bakPath = Path.Combine(tempDir, "database.bak");

            await RestoreDatabaseAsync(bakPath, ct);

            // استبدال ملفات التخزين — فقط إن كانت النسخة كاملة (تحوي مجلد files/).
            // Hint: نسخة «قاعدة فقط» لا تلمس الملفات إطلاقاً، فتبقى الملفات الحالية كما هي.
            if (hasFiles)
                RestoreStorageFiles(Path.Combine(tempDir, "files"));
            else
                // نسخة بلا ملفات: نقيس الفجوة بين ما تتوقّعه القاعدة المُستعادة وما هو موجود.
                missingFiles = CountMissingFromManifest(Path.Combine(tempDir, ManifestName));
        }
        finally
        {
            maintenance.Exit();
            try { if (Directory.Exists(tempDir)) Directory.Delete(tempDir, recursive: true); } catch { /* تنظيف أفضل جهد */ }
        }

        // Hint: أمر SINGLE_USER WITH ROLLBACK IMMEDIATE قتل كل اتصالات القاعدة بما فيها المجمّعة (pool).
        //       نُفرّغ التجمّع حتى لا يعيد EF استخدام اتصال ميت في الكتابة التالية (وإلا رمى خطأ اتصال).
        SqlConnection.ClearAllPools();

        // Hint: النسخة قد تكون أقدم من إصدار التطبيق الحالي (مخطّط قديم بلا أعمدة أُضيفت لاحقاً).
        //       نرقّي المخطّط لأحدث migration بعد الاستعادة — عملية عديمة الأثر إن كانت النسخة محدّثة أصلاً،
        //       وتنقذ البيانات من نسخة قديمة إن كانت أقدم. بدونها تفشل أي كتابة تعتمد على عمود جديد.
        await db.Database.MigrateAsync(ct);

        // Hint: بعد استبدال القاعدة بالكامل صار متتبّع التغييرات قديماً — يتعقّب كياناً (سجلّ النسخة المُحمَّل
        //       في البداية) لم يعُد يطابق الحالة الجديدة. نُفرّغه حتى لا يتعارض مع الكتابة التالية.
        db.ChangeTracker.Clear();

        // بعد عودة القاعدة إلى الحالة المُستعادة: أعِد تسجيل نسخة الأمان (سجلّها القديم اختفى بالاستبدال)
        // ودوّن حدث الاستعادة في سجلّ التدقيق — كلاهما يُكتب في القاعدة المُستعادة.
        db.BackupRecords.Add(new BackupRecord
        {
            CreatedAt = DateTime.UtcNow,
            CreatedByUserId = restoreUserId,
            FileName = safetyZip,
            SizeBytes = safetySize,
            Type = BackupType.Manual,
            Scope = BackupScope.Full,
            Category = RetentionCategory.Manual,
            Status = safetyStatus,
            Note = "نسخة أمان تلقائية قبل الاستعادة" + (safetyNote is null ? "" : " | " + safetyNote),
        });
        // ⚠️ الفجوة تُدوَّن في التدقيق **صراحةً**: استعادةٌ تُبلّغ «نجحت» بينما آلاف المرفقات
        //    مفقودة هي أخطر من فشلٍ صريح — لأنها تُطمئن المالك زوراً.
        var missingNote = missingFiles > 0
            ? $" | ⚠️ {missingFiles} ملف مرفق مفقود — استعِدها من النسخة الكاملة"
            : "";
        audit.Add("Restore", nameof(BackupRecord), backupRecordId.ToString(),
            $"تمت الاستعادة من {rec.FileName} (نسخة أمان: {safetyZip}){missingNote}", null);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// يستعيد قاعدة البيانات من ملف .bak عبر اتصال master، مع MOVE للمسارات الحالية.
    /// Hint: نأخذ القاعدة إلى SINGLE_USER (ROLLBACK IMMEDIATE يُنهي أي جلسات عالقة)، ثم RESTORE WITH REPLACE،
    ///       ثم نعيدها MULTI_USER دائماً في finally حتى لا تبقى مقفلة عند أي خطأ.
    ///       MOVE يجعل الاستعادة تعمل حتى على جهاز جديد (مسارات ملفات مختلفة) — لاختبار «الاستعادة على جهاز نظيف».
    /// </summary>
    private async Task RestoreDatabaseAsync(string bakPath, CancellationToken ct)
    {
        var connStr = config.GetConnectionString("Default")!;
        var builder = new SqlConnectionStringBuilder(connStr);
        var dbName = builder.InitialCatalog;
        builder.InitialCatalog = "master"; // لا نتصل بالقاعدة التي سنستبدلها.

        await using var conn = new SqlConnection(builder.ConnectionString);
        await conn.OpenAsync(ct);

        // 1) اقرأ الأسماء المنطقية للملفات داخل النسخة (بيانات + سجلّ).
        string? logicalData = null, logicalLog = null;
        await using (var list = conn.CreateCommand())
        {
            list.CommandText = "RESTORE FILELISTONLY FROM DISK = @bak";
            list.Parameters.Add(new SqlParameter("@bak", bakPath));
            list.CommandTimeout = 120;
            await using var r = await list.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var name = r.GetString(r.GetOrdinal("LogicalName"));
                var typ = r.GetString(r.GetOrdinal("Type")); // 'D' بيانات، 'L' سجلّ
                if (typ.Equals("D", StringComparison.OrdinalIgnoreCase)) logicalData ??= name;
                else if (typ.Equals("L", StringComparison.OrdinalIgnoreCase)) logicalLog ??= name;
            }
        }
        if (logicalData is null || logicalLog is null)
            throw new ValidationException("تعذّر قراءة بنية ملفات النسخة.");

        // 2) مسارات الملفات الحالية للقاعدة الهدف (يجب أن تكون موجودة — يُنشئها النشر عبر ef database update).
        string? targetData = null, targetLog = null;
        await using (var files = conn.CreateCommand())
        {
            files.CommandText =
                "SELECT type_desc, physical_name FROM sys.master_files WHERE database_id = DB_ID(@db)";
            files.Parameters.Add(new SqlParameter("@db", dbName));
            files.CommandTimeout = 60;
            await using var r = await files.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var typeDesc = r.GetString(0);
                var physical = r.GetString(1);
                if (typeDesc == "ROWS") targetData ??= physical;
                else if (typeDesc == "LOG") targetLog ??= physical;
            }
        }
        if (targetData is null || targetLog is null)
            throw new ValidationException(
                $"القاعدة [{dbName}] غير موجودة على الخادم. أنشئها أولاً (dotnet ef database update) ثم استعِد.");

        // 3) إغلاق حصري ثم استعادة ثم إعادة الفتح.
        await ExecAsync(conn, $"ALTER DATABASE [{dbName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE", 120, ct);
        try
        {
            await using var restore = conn.CreateCommand();
            restore.CommandText =
                $"RESTORE DATABASE [{dbName}] FROM DISK = @bak WITH REPLACE, " +
                "MOVE @ld TO @pd, MOVE @ll TO @pl, RECOVERY";
            restore.Parameters.Add(new SqlParameter("@bak", bakPath));
            restore.Parameters.Add(new SqlParameter("@ld", logicalData));
            restore.Parameters.Add(new SqlParameter("@pd", targetData));
            restore.Parameters.Add(new SqlParameter("@ll", logicalLog));
            restore.Parameters.Add(new SqlParameter("@pl", targetLog));
            restore.CommandTimeout = 600; // الاستعادة قد تستغرق وقتاً.
            await restore.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            // Hint: إعادة الفتح إلزامية حتى عند فشل الاستعادة، وإلا بقيت القاعدة مقفلة على مستخدم واحد.
            //       نتجنّب تمرير ct هنا كي لا يُلغى أمر الفكّ الحيوي.
            await ExecAsync(conn, $"ALTER DATABASE [{dbName}] SET MULTI_USER", 120, CancellationToken.None);
        }
    }

    private static async Task ExecAsync(SqlConnection conn, string sql, int timeoutSec, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.CommandTimeout = timeoutSec;
        await cmd.ExecuteNonQueryAsync(ct);
    }

    // ─────────────────────────── بيان الملفات ───────────────────────────

    /// <summary>صفٌّ في بيان الملفات: المسار النسبي وحجمه.</summary>
    private sealed record ManifestEntry(string Path, long Size);

    private const string ManifestName = "manifest.json";

    /// <summary>يكتب بيان ملفات التخزين داخل أرشيف النسخة.</summary>
    private static void WriteManifest(ZipArchive zip, string storageRoot)
    {
        var entries = Directory.Exists(storageRoot)
            ? Directory.EnumerateFiles(storageRoot, "*", SearchOption.AllDirectories)
                .Select(f => new ManifestEntry(
                    System.IO.Path.GetRelativePath(storageRoot, f).Replace('\\', '/'),
                    new FileInfo(f).Length))
                .ToList()
            : [];

        var entry = zip.CreateEntry(ManifestName, CompressionLevel.Optimal);
        using var s = entry.Open();
        JsonSerializer.Serialize(s, entries);
    }

    /// <summary>
    /// يقارن بيان النسخة بملفات التخزين الفعلية ويردّ عدد المفقود.
    /// </summary>
    /// <remarks>
    /// يُستدعى بعد استعادة نسخة **لا تحوي ملفات**: القاعدة عادت وهي تشير إلى مرفقات قد لا
    /// تكون موجودة. الرقم يُبلَّغ للمالك فوراً بدل أن يكتشفه بعد أسابيع ملفاً ملفاً.
    /// </remarks>
    private int CountMissingFromManifest(string manifestPath)
    {
        try
        {
            if (!File.Exists(manifestPath)) return 0;
            using var s = File.OpenRead(manifestPath);
            var entries = JsonSerializer.Deserialize<List<ManifestEntry>>(s) ?? [];

            return entries.Count(e =>
            {
                var full = System.IO.Path.Combine(paths.StorageRoot, e.Path.Replace('/', System.IO.Path.DirectorySeparatorChar));
                return !File.Exists(full);
            });
        }
        catch
        {
            // بيانٌ تالف لا يجوز أن يُفشل استعادة ناجحة — نتجاهله ونُبلّغ بصفر.
            return 0;
        }
    }

    /// <summary>
    /// يستبدل ملفات التخزين بالكامل بمحتوى مجلد files/ من النسخة.
    /// Hint: نفرّغ مجلد التخزين أولاً حتى لا تبقى ملفات لا تعرفها القاعدة المُستعادة (تناسق تام مع النسخة).
    /// </summary>
    private void RestoreStorageFiles(string filesDir)
    {
        Directory.CreateDirectory(paths.StorageRoot);

        // تفريغ المحتوى الحالي (نُبقي المجلد الجذر نفسه).
        foreach (var f in Directory.EnumerateFiles(paths.StorageRoot, "*", SearchOption.AllDirectories))
        {
            try { File.Delete(f); } catch { /* أفضل جهد */ }
        }
        foreach (var d in Directory.EnumerateDirectories(paths.StorageRoot))
        {
            try { Directory.Delete(d, recursive: true); } catch { /* أفضل جهد */ }
        }

        if (!Directory.Exists(filesDir)) return;
        foreach (var src in Directory.EnumerateFiles(filesDir, "*", SearchOption.AllDirectories))
        {
            var rel = Path.GetRelativePath(filesDir, src);
            var dest = Path.Combine(paths.StorageRoot, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            File.Copy(src, dest, overwrite: true);
        }
    }

    // ─────────────────────────── القراءة والجدولة ───────────────────────────

    public async Task<List<BackupRecord>> ListAsync(CancellationToken ct = default)
        => await db.BackupRecords.OrderByDescending(r => r.CreatedAt).Take(100).ToListAsync(ct);

    public async Task<BackupSchedule> GetScheduleAsync(CancellationToken ct = default)
    {
        var s = await db.BackupSchedules.FirstOrDefaultAsync(ct);
        if (s is null)
        {
            s = new BackupSchedule { Frequency = BackupFrequency.Off, Enabled = false, Hour = 2 };
            db.BackupSchedules.Add(s);
            await db.SaveChangesAsync(ct);
        }
        return s;
    }

    public async Task<BackupSchedule> UpdateScheduleAsync(UpdateScheduleInput input, CancellationToken ct = default)
    {
        if (input.Hour is < 0 or > 23) throw new ValidationException("الساعة يجب أن تكون بين 0 و 23.");
        var s = await GetScheduleAsync(ct);
        s.Frequency = input.Frequency;
        s.Enabled = input.Enabled && input.Frequency != BackupFrequency.Off;
        s.Hour = input.Hour;
        s.NextRunAt = s.Enabled ? ComputeNext(s, DateTime.Now) : null;
        audit.Add("BackupSchedule", nameof(BackupSchedule), null, $"{s.Frequency} @ {s.Hour} (enabled={s.Enabled})", null);
        await db.SaveChangesAsync(ct);
        return s;
    }

    public async Task<(byte[] bytes, string fileName)> DownloadAsync(int id, CancellationToken ct = default)
    {
        var rec = await db.BackupRecords.FirstOrDefaultAsync(r => r.BackupRecordId == id, ct)
                  ?? throw new NotFoundException("سجلّ النسخة غير موجود.");
        var path = Path.Combine(paths.BackupDir, rec.FileName);
        if (!File.Exists(path)) throw new NotFoundException("ملف النسخة غير موجود على الخادم.");
        return (await File.ReadAllBytesAsync(path, ct), rec.FileName);
    }

    public async Task DeleteAsync(int id, CancellationToken ct = default)
    {
        var rec = await db.BackupRecords.FirstOrDefaultAsync(r => r.BackupRecordId == id, ct)
                  ?? throw new NotFoundException("سجلّ النسخة غير موجود.");

        // Hint: حارس أساسي — لا نترك النظام بلا أي نسخة صالحة للاستعادة.
        //       (النسخ الفاشلة لا تُحسب لأنها غير قابلة للاستعادة أصلاً.)
        if (rec.Status == BackupStatus.Success)
        {
            var successCount = await db.BackupRecords.CountAsync(r => r.Status == BackupStatus.Success, ct);
            if (successCount <= 1)
                throw new ConflictException("لا يمكن حذف النسخة الناجحة الوحيدة — خذ نسخة جديدة أولاً.");
        }

        try
        {
            var path = Path.Combine(paths.BackupDir, rec.FileName);
            // حارس أمان: لا نحذف إلا ملفات النسخ بنمطها المعروف داخل مجلد النسخ.
            if (File.Exists(path) && Path.GetFileName(rec.FileName).StartsWith("backup-", StringComparison.Ordinal))
                File.Delete(path);
        }
        catch (Exception ex)
        {
            throw new ConflictException("تعذّر حذف ملف النسخة: " + ex.Message);
        }

        db.BackupRecords.Remove(rec);
        audit.Add("DeleteBackup", nameof(BackupRecord), id.ToString(), rec.FileName, null);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>يحسب موعد التشغيل التالي حسب التكرار وساعة التشغيل.</summary>
    public static DateTime ComputeNext(BackupSchedule s, DateTime now)
    {
        var today = new DateTime(now.Year, now.Month, now.Day, s.Hour, 0, 0);
        return s.Frequency switch
        {
            BackupFrequency.Daily => now < today ? today : today.AddDays(1),
            BackupFrequency.Weekly => now < today ? today : today.AddDays(7),
            _ => today.AddYears(100),
        };
    }
}
