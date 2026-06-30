using System.IO.Compression;
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
    Task<BackupRecord> RunAsync(BackupType type, CancellationToken ct = default);
    Task<List<BackupRecord>> ListAsync(CancellationToken ct = default);
    Task<BackupSchedule> GetScheduleAsync(CancellationToken ct = default);
    Task<BackupSchedule> UpdateScheduleAsync(UpdateScheduleInput input, CancellationToken ct = default);
    Task<(byte[] bytes, string fileName)> DownloadAsync(int id, CancellationToken ct = default);
}

/// <summary>
/// نسخ احتياطي: BACKUP DATABASE (.bak) + ملفات التخزين، مضغوطة في أرشيف ZIP واحد بمجلد النسخ.
/// يُدار من السوبر أدمن فقط (تُفرَض الصلاحية في الـ Controller).
/// </summary>
public sealed class BackupService(
    AppDbContext db, AppPaths paths, IConfiguration config, ICurrentUser current, IAuditService audit) : IBackupService
{
    public async Task<BackupRecord> RunAsync(BackupType type, CancellationToken ct = default)
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
            var connStr = config.GetConnectionString("Default")!;
            var dbName = new SqlConnectionStringBuilder(connStr).InitialCatalog;
            await using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct);
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"BACKUP DATABASE [{dbName}] TO DISK = @path WITH INIT, FORMAT, COMPRESSION";
            cmd.Parameters.Add(new SqlParameter("@path", bakPath));
            cmd.CommandTimeout = 180;
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (Exception ex)
        {
            // بعض إصدارات LocalDB لا تدعم COMPRESSION — أعد المحاولة بدونها.
            try
            {
                var connStr = config.GetConnectionString("Default")!;
                var dbName = new SqlConnectionStringBuilder(connStr).InitialCatalog;
                await using var conn = new SqlConnection(connStr);
                await conn.OpenAsync(ct);
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = $"BACKUP DATABASE [{dbName}] TO DISK = @path WITH INIT, FORMAT";
                cmd.Parameters.Add(new SqlParameter("@path", bakPath));
                cmd.CommandTimeout = 180;
                await cmd.ExecuteNonQueryAsync(ct);
            }
            catch (Exception ex2)
            {
                status = BackupStatus.Failed;
                note = "تعذّر نسخ قاعدة البيانات: " + ex2.Message;
            }
        }

        // 2) ضغط (نسخة DB إن وُجدت + ملفات التخزين) في أرشيف واحد.
        try
        {
            using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);
            if (File.Exists(bakPath))
                zip.CreateEntryFromFile(bakPath, "database.bak", CompressionLevel.Optimal);

            if (Directory.Exists(paths.StorageRoot))
            {
                foreach (var file in Directory.EnumerateFiles(paths.StorageRoot, "*", SearchOption.AllDirectories))
                {
                    var rel = "files/" + Path.GetRelativePath(paths.StorageRoot, file).Replace('\\', '/');
                    zip.CreateEntryFromFile(file, rel, CompressionLevel.Optimal);
                }
            }
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
        var record = new BackupRecord
        {
            CreatedAt = DateTime.UtcNow,
            CreatedByUserId = current.UserId,
            FileName = zipName,
            SizeBytes = size,
            Type = type,
            Status = status,
            Note = note,
        };
        db.BackupRecords.Add(record);
        audit.Add("Backup", nameof(BackupRecord), null, $"نسخة احتياطية {type} ({status})", null);
        await db.SaveChangesAsync(ct);
        return record;
    }

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
