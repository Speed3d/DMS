namespace Dms.Domain;

/// <summary>حكمُ التوافق على نسخةٍ احتياطية قبل استعادتها (ADR-055).</summary>
public enum BackupVerdict
{
    /// <summary>من هذا الإصدار أو أقدم — تُستعاد وتُرقّى مهاجراتُها عند الإقلاع.</summary>
    Ok = 0,

    /// <summary>نسخةٌ قديمة بلا بيان إصدار (قبل ADR-055) — تُستعاد مع تنبيه.</summary>
    OkUnknownVersion = 1,

    /// <summary>أُخذت على SQL Server أحدث من هذا الخادم — لا تُستعاد عليه إطلاقاً (قيدٌ في SQL Server نفسه).</summary>
    NewerSqlServer = 2,

    /// <summary>قاعدتُها فيها مهاجرةٌ لا يعرفها هذا الكود — مخطّطٌ أحدث من البرنامج.</summary>
    UnknownMigration = 3,

    /// <summary>من إصدار برنامجٍ أحدث من الخادم.</summary>
    NewerApp = 4,
}

/// <summary>ما تحمله النسخة عن نفسها (`backup-info.json`) — وقد يغيب كلُّه في نسخةٍ قديمة.</summary>
public sealed record BackupOrigin(AppVersion? AppVersion, string? LastMigration, int? SqlMajorVersion);

/// <summary>
/// هل تُستعاد هذه النسخة على هذا الخادم؟ — **قاعدةٌ واحدة** تُطبَّق عند رفع نسخةٍ من جهازٍ آخر
/// وعند كل استعادة (ADR-055).
/// </summary>
/// <remarks>
/// 🔴 **لماذا؟** نسخةٌ من إصدارٍ أحدث تُستعاد فوق برنامجٍ أقدم **فتصير القاعدة متقدّمةً على الكود**:
/// أعمدةٌ لا يعرفها ⇒ `Invalid column name` في كل شاشة، والاستعادة لا رجعة فيها إلا بنسخة الأمان.
/// والرفضُ قبل أن يُلمس شيء أرخص من الإصلاح بعده.
/// <para>
/// ⚠️ **الترتيب مقصود**: SQL Server أوّلاً (لا حلّ له إلا خادمٌ أحدث) · ثم المهاجرة (الدليل الأدقّ على
/// المخطّط) · ثم رقم الإصدار (يرفض الأحدث ولو بلا مهاجرة — احتياطٌ لا يكلّف شيئاً).
/// </para>
/// </remarks>
public static class BackupCompatibility
{
    public static (BackupVerdict Verdict, string Message) Check(
        BackupOrigin origin, AppVersion server, IReadOnlyCollection<string> serverMigrations, int serverSqlMajor)
    {
        if (origin.SqlMajorVersion is { } sql && sql > serverSqlMajor)
            return (BackupVerdict.NewerSqlServer,
                $"هذه النسخة أُخذت على SQL Server أحدث ({SqlName(sql)}) من المثبَّت على هذا الخادم ({SqlName(serverSqlMajor)}) — " +
                "لا يمكن استعادتها عليه إطلاقاً (قيدٌ في SQL Server نفسه). حدِّث SQL Server على هذا الجهاز أولاً.");

        if (origin.LastMigration is { Length: > 0 } m && !serverMigrations.Contains(m))
            return (BackupVerdict.UnknownMigration,
                "قاعدة بيانات هذه النسخة من إصدارٍ أحدث من البرنامج على هذا الخادم" +
                (origin.AppVersion is { } v ? $" ({v.Display} مقابل {server.Display})" : "") +
                " — حدِّث البرنامج أولاً ثم استعِدها.");

        if (origin.AppVersion is { } app && app.IsNewerThan(server))
            return (BackupVerdict.NewerApp,
                $"هذه النسخة من الإصدار {app.Display} وهو أحدث من الإصدار على هذا الخادم ({server.Display}) — " +
                "حدِّث البرنامج أولاً ثم استعِدها.");

        if (origin.AppVersion is null)
            return (BackupVerdict.OkUnknownVersion,
                "نسخةٌ قديمة لا تحمل رقم إصدار — تُستعاد، وتُرقّى قاعدتُها إلى هذا الإصدار تلقائياً.");

        return (BackupVerdict.Ok, $"من الإصدار {origin.AppVersion.Display} — متوافقة مع هذا الخادم ({server.Display}).");
    }

    /// <summary>هل الحكم يسمح بالاستعادة؟</summary>
    public static bool Allows(BackupVerdict v) => v is BackupVerdict.Ok or BackupVerdict.OkUnknownVersion;

    /// <summary>اسمُ الإصدار الرئيسيّ لـSQL Server للعرض — <c>16</c> ⟵ «2022».</summary>
    public static string SqlName(int major) => major switch
    {
        17 => "2025",
        16 => "2022",
        15 => "2019",
        14 => "2017",
        13 => "2016",
        12 => "2014",
        11 => "2012",
        _ => $"الإصدار {major}",
    };
}
