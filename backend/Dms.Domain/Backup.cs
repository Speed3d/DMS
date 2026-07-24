namespace Dms.Domain;

public enum BackupFrequency { Off = 0, Daily = 1, Weekly = 2 }
public enum BackupType { Manual = 0, Scheduled = 1 }
public enum BackupStatus { Success = 0, Failed = 1 }

/// <summary>
/// نطاق النسخة: ماذا تتضمّن.
/// Hint: الوثائق لا تتغيّر بعد إنشائها، فلا معنى لنسخ الملفات يومياً. اليومية = قاعدة فقط (خفيفة)،
/// والأسبوعية/الشهرية = كاملة (قاعدة + ملفات). يقلّل حجم الرفع اليومي للسحابة بشكل كبير.
/// </summary>
public enum BackupScope { DbOnly = 0, Full = 1 }

/// <summary>
/// تصنيف النسخة لأغراض سياسة الاحتفاظ (نمط الجد/الأب/الابن).
/// Hint: كل تصنيف له سقف عدد مستقل — انظر BackupRetention. يدوية = لا تُحذف تلقائياً إلا عند تجاوز سقف كبير.
/// </summary>
public enum RetentionCategory { Manual = 0, Daily = 1, Weekly = 2, Monthly = 3 }

/// <summary>
/// سياسة الاحتفاظ بالنسخ (نمط الجد/الأب/الابن — Grandfather/Father/Son).
/// Hint: بدونها تتراكم النسخ بلا حدّ (~365 ج.ب سنوياً بنسخة يومية). بها ~23 نسخة فقط (~58 ج.ب).
/// القيم قابلة للتعديل هنا في مكان واحد؛ تغييرها يسري على عمليات التقليم اللاحقة فقط.
/// </summary>
public static class BackupRetention
{
    public const int KeepDaily = 7;      // آخر أسبوع
    public const int KeepWeekly = 4;     // آخر شهر
    public const int KeepMonthly = 12;   // آخر سنة
    public const int KeepManual = 20;    // سقف أمان لليدوية (المالك يديرها، لكن لا نتركها بلا حدّ)

    /// <summary>عدد النسخ المحتفظ بها لكل تصنيف.</summary>
    public static int KeepFor(RetentionCategory category) => category switch
    {
        RetentionCategory.Daily => KeepDaily,
        RetentionCategory.Weekly => KeepWeekly,
        RetentionCategory.Monthly => KeepMonthly,
        RetentionCategory.Manual => KeepManual,
        _ => KeepManual,
    };

    /// <summary>
    /// يحدّد نطاق وتصنيف النسخة المجدولة حسب التاريخ (نمط الجد/الأب/الابن).
    /// Hint: بإعداد «يومي» واحد تحصل تلقائياً على دورة كاملة — يومية خفيفة (قاعدة فقط)،
    ///       وترقية لكاملة أسبوعياً (الجمعة) وشهرياً (أول الشهر). الأولوية: شهري > أسبوعي > يومي.
    ///       منطق نقي في المجال ليبقى قابلاً للاختبار بلا بنية تحتية.
    /// </summary>
    public static (BackupScope scope, RetentionCategory category) ClassifyScheduled(BackupFrequency freq, DateTime now)
    {
        if (freq == BackupFrequency.Weekly)
            return (BackupScope.Full, RetentionCategory.Weekly);

        // يومي:
        if (now.Day == 1)
            return (BackupScope.Full, RetentionCategory.Monthly);
        if (now.DayOfWeek == DayOfWeek.Friday)
            return (BackupScope.Full, RetentionCategory.Weekly);
        return (BackupScope.DbOnly, RetentionCategory.Daily);
    }
}

/// <summary>سجلّ عملية نسخ احتياطي (قاعدة البيانات وحدها أو مع ملفات التخزين، في أرشيف ZIP واحد).</summary>
public class BackupRecord
{
    public int BackupRecordId { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? CreatedByUserId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public long SizeBytes { get; set; }
    public BackupType Type { get; set; }
    public BackupStatus Status { get; set; }
    public string? Note { get; set; }

    /// <summary>ماذا تتضمّن النسخة (قاعدة فقط أم كاملة). Hint: افتراضياً Full للنسخ القديمة قبل هذا الحقل.</summary>
    public BackupScope Scope { get; set; } = BackupScope.Full;

    /// <summary>تصنيف الاحتفاظ (يدوية/يومية/أسبوعية/شهرية). Hint: يحدّد أيّ سقف عدد يُطبَّق عند التقليم.</summary>
    public RetentionCategory Category { get; set; } = RetentionCategory.Manual;
}

/// <summary>إعداد جدولة النسخ الاحتياطي (صفّ مفرد، يتحكم به السوبر أدمن فقط).</summary>
public class BackupSchedule
{
    public int BackupScheduleId { get; set; }
    public BackupFrequency Frequency { get; set; } = BackupFrequency.Off;
    public bool Enabled { get; set; }

    /// <summary>ساعة التشغيل (0–23، توقيت الخادم المحلي).</summary>
    public int Hour { get; set; } = 2;

    public DateTime? LastRunAt { get; set; }
    public DateTime? NextRunAt { get; set; }
}
