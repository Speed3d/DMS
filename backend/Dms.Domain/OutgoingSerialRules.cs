namespace Dms.Domain;

/// <summary>
/// قواعد تسلسل الصادر اليدوي وتراجع العداد (ADR-064) — هنا لا في الخدمة لتُختبر وحدها.
/// </summary>
public static class OutgoingSerialRules
{
    public const string AlreadyUsed = "AlreadyUsed";
    public const string AvailableNext = "AvailableNext";
    public const string AvailableGap = "AvailableGap";
    public const string AvailableAboveCounter = "AvailableAboveCounter";

    /// <summary>حالة تسلسلٍ شاغر بالنسبة للعداد: التالي · فجوةٌ تحته · أو قفزةٌ فوقه.</summary>
    public static string ClassifyFree(int serial, int counter) =>
        serial == counter + 1 ? AvailableNext
        : serial <= counter ? AvailableGap
        : AvailableAboveCounter;

    /// <summary>
    /// قيمة العداد بعد حذف كتابٍ معتمد — أو <c>null</c> إن لم يتغيّر.
    /// 🔴 **لا يتراجع إلا إذا كان المحذوف آخر رقم**، وحينها إلى **أعلى تسلسلٍ حيّ باقٍ** لا إلى «ناقص واحد» —
    /// فلو كانت تحته فجوةٌ (يدوية أو من حذفٍ سابق) لم يُعطَ رقمٌ مستخدم ولم تُترك قفزة.
    /// </summary>
    public static int? CounterAfterDelete(int counter, int deletedSerial, int? maxRemainingSerial) =>
        counter == deletedSerial ? Math.Max(0, maxRemainingSerial ?? 0) : null;
}

/// <summary>
/// حكم الختم الموقّع الخامّ (<c>DMS1/DMS2</c>) — بعد أن صار رقم الكتاب المحذوف يُعاد استعماله (ADR-064).
/// </summary>
/// <remarks>
/// 🔴 **الرقم وحده لم يعُد هويّة**: كتابٌ حُذف بعد طباعته ثم أخذ كتابٌ جديد رقمه — فلو حُكم بالرقم
/// قيل عن الورقة الملغاة «صادرٌ فعلاً». الحكم بمطابقة **الرقم والتاريخ والجهة** (قرار المالك 2026-10-28)،
/// والمحتوى الموقّع المطابق حرفياً يحسم أولاً، **وعند الالتباس يُحكم بالسحب** — الخطأ نحو الحذر.
/// </remarks>
public static class LegacyQrVerdict
{
    /// <summary>كتابٌ يحمل الرقم المختوم: محتواه الموقّع الحالي وتاريخه وجهته.</summary>
    public sealed record Candidate(string? QrContent, string Date, string Entity);

    /// <returns><c>true</c> = صادرٌ فعلاً (الكتاب الحيّ هو صاحب الختم)، <c>false</c> = سُحب.</returns>
    public static bool IsGenuine(
        string signedContent, string signedDate, string signedEntity,
        Candidate? live, IReadOnlyCollection<Candidate> deleted)
    {
        if (live is null) return false;

        var content = signedContent.Trim();
        if (Same(live.QrContent, content)) return true;
        if (deleted.Any(d => Same(d.QrContent, content))) return false;

        bool Matches(Candidate c) =>
            string.Equals(c.Date, signedDate.Trim(), StringComparison.Ordinal)
            && string.Equals(c.Entity.Trim(), signedEntity.Trim(), StringComparison.Ordinal);

        // ⚠️ **كتابٌ أُعيد إصداره في اليوم نفسه للجهة نفسها**: التاريخ والجهة لا يفرّقان بين الحيّ والمحذوف ⟵ سُحب.
        return Matches(live) && !deleted.Any(Matches);
    }

    private static bool Same(string? stored, string content) =>
        !string.IsNullOrEmpty(stored) && string.Equals(stored.Trim(), content, StringComparison.Ordinal);
}
