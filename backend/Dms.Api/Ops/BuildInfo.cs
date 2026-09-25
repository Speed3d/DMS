using System.Globalization;
using System.Reflection;
using Dms.Domain;

namespace Dms.Api.Ops;

/// <summary>
/// إصدار الخادم الذي يعمل الآن — من ملف التجميع نفسه لا من إعداد (ADR-054).
/// </summary>
/// <remarks>
/// 🔑 **يُقرأ من `Dms.Api.dll` المبنيّ** — فما يُعرض هو ما يعمل فعلاً، لا ما كُتب في ملفٍّ
/// قد لا يطابق الملفات المنسوخة. والرقم أصله `VERSION` عبر `Directory.Build.props`.
/// </remarks>
public static class BuildInfo
{
    private static readonly Assembly Asm = typeof(BuildInfo).Assembly;

    /// <summary>الإصدار مع الـcommit (<c>0.9.0+sha</c>) — أو <c>0.0.0</c> إن تعذّرت قراءته.</summary>
    public static AppVersion Current { get; } =
        AppVersion.Parse(Asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion)
        ?? new AppVersion(0, 0, 0);

    /// <summary>لحظة البناء (UTC) — من <c>AssemblyMetadata("DmsBuiltAtUtc")</c>.</summary>
    public static DateTime? BuiltAtUtc { get; } = ReadBuiltAt();

    private static DateTime? ReadBuiltAt()
    {
        var raw = Asm.GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == "DmsBuiltAtUtc")?.Value;
        return DateTime.TryParse(raw, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var t)
            ? DateTime.SpecifyKind(t, DateTimeKind.Utc)
            : null;
    }
}
