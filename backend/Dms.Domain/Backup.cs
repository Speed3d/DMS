namespace Dms.Domain;

public enum BackupFrequency { Off = 0, Daily = 1, Weekly = 2 }
/// <remarks><c>Uploaded</c>: مرفوعةٌ من جهاز المستخدم (ADR-055) — لا يأخذها هذا الخادم بل يستوردها.</remarks>
public enum BackupType { Manual = 0, Scheduled = 1, Uploaded = 2 }
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
    /// يحدّد تصنيف النسخة المجدولة حسب التاريخ (نمط الجد/الأب/الابن).
    /// **والنطاق دائماً «قاعدة فقط»** — انظر المبرّر.
    /// </summary>
    /// <remarks>
    /// ⚠️ **كانت المجدولة تُرقّى إلى «كاملة» يوم الجمعة وأول الشهر** — تصميم صحيح حين كان
    /// التخزين ميغابايتات. لكن أرشيف الشركة الورقي **~80 غيغابايت**، وسياسة الاحتفاظ تُبقي
    /// ٣٦ نسخة كاملة (٤ أسبوعية + ١٢ شهرية + ٢٠ سنوية):
    ///
    ///     ٣٦ × 80 غيغا = **2.9 تيرابايت** — لا قرص في خطة النشر يحتمله، وكل نسخة تستغرق
    ///     ساعات لتُعيد نسخ أرشيفٍ **لا يتغيّر أبداً**.
    ///
    /// **القرار (المالك، 2026-07-28):** المجدولة **قاعدة فقط دائماً** — سريعة وصغيرة تُرفع
    /// إلى OneDrive، وتحمي من تلف القاعدة والحذف الخاطئ والمهاجرة الفاشلة. أما الملفات
    /// فتُحمى بنسخة كاملة **يدوية** إلى قرص خارجي (مرآة تُضيف ولا تُكرّر).
    ///
    /// 🔴 **الثمن المقصود:** المجدولة وحدها **لا تحمي المرفقات**. ولذلك يتتبّع النظام عمر
    /// آخر نسخة كاملة ويُنذر تصعيدياً قبل تجاوز ٣٠ يوماً — «يدوي بتذكير» لا «يدوي منسيّ».
    ///
    /// Hint: التصنيف يبقى متدرّجاً (شهري > أسبوعي > يومي) فتُحفظ دورة الاحتفاظ ومعها تاريخٌ
    ///       أعمق — نسخة من أول كل شهر لا سبع نسخ يومية فقط.
    /// </remarks>
    public static (BackupScope scope, RetentionCategory category) ClassifyScheduled(BackupFrequency freq, DateTime now)
    {
        if (freq == BackupFrequency.Weekly)
            return (BackupScope.DbOnly, RetentionCategory.Weekly);

        // يومي: التصنيف يتدرّج والنطاق ثابت.
        if (now.Day == 1)
            return (BackupScope.DbOnly, RetentionCategory.Monthly);
        if (now.DayOfWeek == DayOfWeek.Friday)
            return (BackupScope.DbOnly, RetentionCategory.Weekly);
        return (BackupScope.DbOnly, RetentionCategory.Daily);
    }

    /// <summary>الحدّ الأقصى المقبول لعمر آخر نسخة كاملة (بالأيام) قبل الإنذار الأحمر.</summary>
    public const int FullBackupMaxAgeDays = 30;

    /// <summary>خطورة تذكير النسخة الكاملة — تتصاعد مع اقتراب المهلة.</summary>
    public enum FullBackupUrgency { Ok, Soon, Urgent, Overdue }

    /// <summary>
    /// يقيس عمر آخر نسخة كاملة ويُصنّف إلحاحه.
    /// </summary>
    /// <remarks>
    /// 🔴 **أضعف حلقة في المنظومة هي ذاكرة المالك.** النسخة الكاملة يدوية بقراره، والمجدولة
    /// لا تحمي المرفقات — فلو نُسيت شهرين ثم تعطّل القرص ضاعت مرفقات شهرين، **بينما النسخ
    /// اليومية تعمل بانتظام وتُعطي شعوراً زائفاً بالأمان**. هذا التصنيف هو ما يمنع ذلك.
    ///
    /// التصعيد مقصود: تنبيه هادئ قبل ثلاثة أيام، ثم يشتدّ يوماً بيوم، ثم أحمر عند التجاوز.
    /// و<c>null</c> (لا نسخة كاملة قط) = **متأخّرة** لا «سليمة» — فشل مغلق.
    /// </remarks>
    public static FullBackupUrgency ClassifyFullBackupAge(DateTime? lastFullUtc, DateTime nowUtc)
    {
        if (lastFullUtc is null) return FullBackupUrgency.Overdue;

        var days = (nowUtc - lastFullUtc.Value).TotalDays;
        if (days >= FullBackupMaxAgeDays) return FullBackupUrgency.Overdue;
        if (days >= FullBackupMaxAgeDays - 2) return FullBackupUrgency.Urgent;   // ٢٨ و٢٩
        if (days >= FullBackupMaxAgeDays - 3) return FullBackupUrgency.Soon;     // ٢٧
        return FullBackupUrgency.Ok;
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

/// <summary>
/// صحّة النسخ الاحتياطي ككلّ (ADR-062) — فوق تغطية النسخة الكاملة.
/// </summary>
/// <remarks>
/// 🔴 **كان التنبيه يسأل سؤالاً واحداً: كم مضى على آخر نسخة كاملة؟** فبقي صامتاً في حالاتٍ
/// ثلاث وُجدت فعلاً على جهاز التطوير (2026-10-15): **الجدولة متوقّفة** (والتثبيت الجديد يبدأ
/// متوقّفاً) · **لا نسخةَ منذ عشرة أيام** · **وسجلّان ملفّاهما مفقودان من القرص** — وكان
/// السجلُّ المفقود ملفُّه يُحسب «نسخةً كاملة» فيُطمئن التنبيه على ما لا يُستعاد.
///
/// ⚠️ **المفقود ملفُّه لا يُحسب نسخةً في أيّ موضع** — لا في التغطية ولا في «آخر نسخة»
/// ولا في حارس «لا تحذف النسخة الوحيدة». **النسخة التي لا ملفَّ لها ليست نسخة.**
/// </remarks>
public static class BackupHealth
{
    /// <summary>بعد كم يوماً بلا أيّ نسخة يصير الأمر تنبيهاً (طلب المالك: «أكثر من يومين»).</summary>
    public const int StaleAfterDays = 2;

    public enum Warning { ScheduleOff, Stale, MissingFiles }

    public sealed record Assessment(
        BackupRetention.FullBackupUrgency Urgency,
        BackupRetention.FullBackupUrgency FullUrgency,
        IReadOnlyList<Warning> Warnings,
        int? DaysSinceAnyBackup);

    /// <param name="lastFullUtc">آخر نسخة كاملة ناجحة **ملفُّها موجود** (غير مرفوعة).</param>
    /// <param name="lastAnyUtc">آخر نسخة ناجحة أيّاً كان نطاقها **ملفُّها موجود** (غير مرفوعة).</param>
    /// <param name="scheduleOn">الجدولة مفعّلةٌ بتكرارٍ غير «متوقّف».</param>
    /// <param name="missingFiles">عدد السجلّات الناجحة التي اختفى ملفّها من القرص.</param>
    public static Assessment Assess(DateTime? lastFullUtc, DateTime? lastAnyUtc, bool scheduleOn,
        int missingFiles, DateTime nowUtc)
    {
        var full = BackupRetention.ClassifyFullBackupAge(lastFullUtc, nowUtc);
        var warnings = new List<Warning>();
        var urgency = full;

        if (!scheduleOn)
        {
            warnings.Add(Warning.ScheduleOff);
            urgency = Max(urgency, BackupRetention.FullBackupUrgency.Soon);
        }

        // ⚠️ «لا نسخة قطّ» تنبيهٌ أيضاً — فشلٌ مغلق كالتغطية.
        int? daysAny = lastAnyUtc is null ? null : (int)(nowUtc - lastAnyUtc.Value).TotalDays;
        if (lastAnyUtc is null || (nowUtc - lastAnyUtc.Value).TotalDays > StaleAfterDays)
        {
            warnings.Add(Warning.Stale);
            urgency = Max(urgency, BackupRetention.FullBackupUrgency.Urgent);
        }

        if (missingFiles > 0)
        {
            warnings.Add(Warning.MissingFiles);
            urgency = Max(urgency, BackupRetention.FullBackupUrgency.Soon);
        }

        return new Assessment(urgency, full, warnings, daysAny);
    }

    private static BackupRetention.FullBackupUrgency Max(BackupRetention.FullBackupUrgency a, BackupRetention.FullBackupUrgency b)
        => (int)a >= (int)b ? a : b;
}
