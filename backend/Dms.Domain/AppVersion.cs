namespace Dms.Domain;

/// <summary>
/// رقم إصدار البرنامج <c>الرئيسي.الفرعي.الإصلاح</c> مع رمز الـcommit (ADR-054).
/// </summary>
/// <remarks>
/// <list type="bullet">
/// <item><b>الإصلاح</b>: إصلاحُ عطلٍ بلا ميزةٍ جديدة.</item>
/// <item><b>الفرعي</b>: ميزةٌ جديدة، أو مهاجرةُ قاعدة بيانات.</item>
/// <item><b>الرئيسي</b>: تغييرٌ لا يتوافق مع ما قبله.</item>
/// </list>
/// 🔑 **المقارنة بالأرقام الثلاثة وحدها** — الـcommit للتتبّع لا للترتيب. وبها تعرف استعادةُ
/// نسخةٍ (الدفعة ج) أنها «من إصدارٍ أحدث من الخادم» فترفضها قبل أن تُفسد شيئاً.
/// </remarks>
public sealed record AppVersion(int Major, int Minor, int Patch, string? Commit = null) : IComparable<AppVersion>
{
    /// <summary>يقرأ <c>0.9.0</c> أو <c>0.9.0+abcdef…</c> (صيغة <c>InformationalVersion</c>) — و<c>null</c> لغيرهما.</summary>
    public static AppVersion? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = text.Trim().Split('+', 2);
        var nums = parts[0].Split('.');
        if (nums.Length != 3) return null;
        if (!int.TryParse(nums[0], out var major) || !int.TryParse(nums[1], out var minor)
            || !int.TryParse(nums[2], out var patch)) return null;
        if (major < 0 || minor < 0 || patch < 0) return null;
        var commit = parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[1]) ? parts[1].Trim() : null;
        return new AppVersion(major, minor, patch, commit);
    }

    /// <summary>الرقم للعرض — <c>0.9.0</c>.</summary>
    public string Display => $"{Major}.{Minor}.{Patch}";

    /// <summary>أوّل سبعة أحرف من الـcommit (كما يعرضها git) — أو <c>null</c>.</summary>
    public string? ShortCommit => Commit is { Length: > 7 } c ? c[..7] : Commit;

    public int CompareTo(AppVersion? other)
    {
        if (other is null) return 1;
        var c = Major.CompareTo(other.Major);
        if (c != 0) return c;
        c = Minor.CompareTo(other.Minor);
        return c != 0 ? c : Patch.CompareTo(other.Patch);
    }

    /// <summary>هل هذا أحدث من <paramref name="other"/>؟ — بالأرقام وحدها.</summary>
    public bool IsNewerThan(AppVersion other) => CompareTo(other) > 0;

    /// <summary>الإصدار نفسه بالأرقام (ولو اختلف الـcommit).</summary>
    public bool SameReleaseAs(AppVersion other) => CompareTo(other) == 0;

    public override string ToString() => Display;
}
