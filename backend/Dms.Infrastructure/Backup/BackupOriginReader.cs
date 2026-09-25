using System.IO.Compression;
using System.Reflection;
using System.Text.Json;
using Dms.Domain;
using Microsoft.Data.SqlClient;

namespace Dms.Infrastructure.Backup;

/// <summary>
/// «من أين جاءت هذه النسخة؟» — إصدار البرنامج وآخر مهاجرة وإصدار SQL Server (ADR-055).
/// </summary>
/// <remarks>
/// 🔑 **ملفٌّ ثانٍ في الأرشيف (`backup-info.json`) لا حقولٌ في `manifest.json`** — ذاك قائمةُ ملفاتٍ
/// تقرؤها النسخ القديمة بصيغتها، وتغييرُها يكسر قراءتها. والنسخة القديمة بلا هذا الملف تُقبل بتنبيه.
/// </remarks>
public static class BackupOriginReader
{
    public const string InfoFileName = "backup-info.json";

    /// <summary>ما يُكتب في كل نسخةٍ جديدة.</summary>
    public sealed record BackupInfo(string? AppVersion, string? LastMigration, int? SqlMajorVersion, DateTime CreatedAtUtc);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>إصدار البرنامج الذي يعمل — من ملف التجميع (أصلُه `VERSION` — ADR-054).</summary>
    public static AppVersion CurrentAppVersion { get; } =
        AppVersion.Parse(typeof(BackupOriginReader).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion)
        ?? new AppVersion(0, 0, 0);

    public static void Write(ZipArchive zip, BackupInfo info)
    {
        var entry = zip.CreateEntry(InfoFileName, CompressionLevel.Optimal);
        using var s = entry.Open();
        JsonSerializer.Serialize(s, info, Json);
    }

    public static void Write(string directory, BackupInfo info) =>
        File.WriteAllText(Path.Combine(directory, InfoFileName), JsonSerializer.Serialize(info, Json));

    /// <summary>يقرأ أصل النسخة من أرشيفها — وغيابُ الملف (نسخةٌ قديمة) أصلٌ فارغ لا خطأ.</summary>
    public static BackupOrigin FromZip(string zipPath)
    {
        using var zip = ZipFile.OpenRead(zipPath);
        var entry = zip.GetEntry(InfoFileName);
        if (entry is null) return new BackupOrigin(null, null, null);
        using var s = entry.Open();
        return ToOrigin(JsonSerializer.Deserialize<BackupInfo>(s, Json));
    }

    /// <summary>يقرأ أصل المرآة من مجلدها.</summary>
    public static BackupOrigin FromDirectory(string directory)
    {
        var file = Path.Combine(directory, InfoFileName);
        return File.Exists(file)
            ? ToOrigin(JsonSerializer.Deserialize<BackupInfo>(File.ReadAllText(file), Json))
            : new BackupOrigin(null, null, null);
    }

    private static BackupOrigin ToOrigin(BackupInfo? i) =>
        i is null ? new BackupOrigin(null, null, null)
                  : new BackupOrigin(AppVersion.Parse(i.AppVersion), i.LastMigration, i.SqlMajorVersion);

    /// <summary>الإصدار الرئيسيّ لـSQL Server على هذا الخادم (<c>16</c> = 2022).</summary>
    public static async Task<int> ServerSqlMajorAsync(string connectionString, CancellationToken ct)
    {
        await using var conn = new SqlConnection(Master(connectionString));
        await conn.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS int)";
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
    }

    /// <summary>
    /// الإصدار الرئيسيّ لـSQL Server الذي أخذ ملف <c>.bak</c> — من ترويسته (<c>RESTORE HEADERONLY</c>).
    /// </summary>
    /// <remarks>
    /// 🔑 **الحَكَم الصادق** — لا يعتمد على ما كتبناه نحن في `backup-info.json`، فيصلح للنسخ القديمة أيضاً.
    /// ⚠️ **المسار يقرؤه محرّك SQL بحسابه** — فالملف يوضع في مجلد النسخ الذي يكتب فيه أصلاً.
    /// </remarks>
    public static async Task<int?> BakSqlMajorAsync(string connectionString, string bakPath, CancellationToken ct)
    {
        await using var conn = new SqlConnection(Master(connectionString));
        await conn.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "RESTORE HEADERONLY FROM DISK = @bak";
        cmd.Parameters.Add(new SqlParameter("@bak", bakPath));
        cmd.CommandTimeout = 300;
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return null;
        var ord = r.GetOrdinal("SoftwareVersionMajor");
        return r.IsDBNull(ord) ? null : Convert.ToInt32(r.GetValue(ord));
    }

    private static string Master(string cs) =>
        new SqlConnectionStringBuilder(cs) { InitialCatalog = "master" }.ConnectionString;
}
