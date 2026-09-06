namespace Dms.Domain;

/// <summary>
/// دورة حياة المهمة — منطق مجال نقيّ بلا اعتماد على بنية تحتية (نمط <see cref="IncomingWorkflow"/>).
/// Hint: هذا هو مصدر الحقيقة الوحيد لانتقالات الحالة؛ الخدمة تفرضه والواجهة تعكسه.
/// </summary>
public static class TaskWorkflow
{
    /// <summary>
    /// مصفوفة الانتقالات المسموحة.
    /// Hint: مصفوفة مغلقة — أي انتقال غير مذكور هنا مرفوض.
    /// </summary>
    /// <remarks>
    /// ⚠️ **«ملغاة» نهائيةٌ و«مكتملة» ليست كذلك**: الإلغاء قرارُ عدولٍ عن العمل، وإعادةُ فتحه
    /// تعني أنه لم يُلغَ أصلاً. أمّا الاكتمال فقد يُنقَض بمراجعةٍ لاحقة — ولذلك
    /// <see cref="DmsTaskStatus.Reopened"/> حالةٌ **مستقلّة** لا عودةٌ إلى
    /// <see cref="DmsTaskStatus.InProgress"/>: الفرق بين «لم يبدأ بعد» و«أُعيد فتحه» يجب أن
    /// يبقى مقروءاً في السجلّ وفي التقرير.
    /// </remarks>
    private static readonly Dictionary<DmsTaskStatus, DmsTaskStatus[]> Transitions = new()
    {
        [DmsTaskStatus.New] = [DmsTaskStatus.InProgress, DmsTaskStatus.Cancelled],
        [DmsTaskStatus.InProgress] = [DmsTaskStatus.OnHold, DmsTaskStatus.Completed, DmsTaskStatus.Cancelled],
        [DmsTaskStatus.OnHold] = [DmsTaskStatus.InProgress, DmsTaskStatus.Cancelled],
        [DmsTaskStatus.Completed] = [DmsTaskStatus.Reopened],
        [DmsTaskStatus.Reopened] = [DmsTaskStatus.InProgress, DmsTaskStatus.Cancelled],

        // Cancelled: حالة نهائية — لا مخرج منها.
    };

    /// <summary>الحالات التي يمكن الانتقال إليها من الحالة المعطاة (قائمة فارغة = حالة نهائية).</summary>
    public static IReadOnlyList<DmsTaskStatus> NextStatuses(DmsTaskStatus from) =>
        Transitions.TryGetValue(from, out var next) ? next : [];

    /// <summary>هل الانتقال مسموح؟ (Hint: البقاء على نفس الحالة ليس انتقالاً صالحاً).</summary>
    public static bool CanTransition(DmsTaskStatus from, DmsTaskStatus to) =>
        from != to && NextStatuses(from).Contains(to);

    /// <summary>
    /// يتحقق من الانتقال ويرمي استثناءً عربياً واضحاً عند الرفض.
    /// Hint: تُستدعى من الخدمة قبل أي تغيير حالة.
    /// </summary>
    public static void EnsureTransitionAllowed(DmsTaskStatus from, DmsTaskStatus to)
    {
        if (from == to)
            throw new ValidationException($"المهمة في حالة ({ArabicName(to)}) أصلاً.");

        if (!CanTransition(from, to))
            throw new ValidationException($"انتقال غير مسموح: من ({ArabicName(from)}) إلى ({ArabicName(to)}).");
    }

    /// <summary>هل المهمة ما تزال قيد العمل؟ (المكتملة والملغاة خارج الحساب).</summary>
    /// <remarks>
    /// ⚠️ **هذه قاعدة التصعيد والتأخّر معاً** — فمهمةٌ مكتملةٌ بعد موعدها ليست «متأخرة»،
    /// وتصعيدُها إلى المدير إزعاجٌ بلا معلومة.
    /// </remarks>
    public static bool IsActive(DmsTaskStatus status) =>
        status is DmsTaskStatus.New
            or DmsTaskStatus.InProgress
            or DmsTaskStatus.OnHold
            or DmsTaskStatus.Reopened;

    /// <summary>
    /// الحالات النشِطة **كمصفوفة** — لأن <see cref="IsActive"/> دالّةٌ لا يترجمها EF إلى SQL.
    /// </summary>
    /// <remarks>
    /// 🔴 **نسختان للقاعدة نفسها، وحارسٌ يثبّت تطابقهما**: الاستعلامات تحتاج شيئاً يُترجَم،
    /// والقارئ يحتاج شرطاً يُقرأ. وموضعُهما **معاً في المجال** لا في الخدمة — فالخدمة لا
    /// تُختبَر بالوحدة (تراجع `Dms.Domain` و`Dms.Documents` وحدهما)، ونسخةٌ هناك تعني قاعدةً
    /// بلا حارس. واختبارٌ يمرّ على **كل قيمة في الـenum** يكشف أي تباعدٍ عند أول حالةٍ جديدة.
    /// </remarks>
    public static readonly DmsTaskStatus[] ActiveStatuses =
    [
        DmsTaskStatus.New, DmsTaskStatus.InProgress, DmsTaskStatus.OnHold, DmsTaskStatus.Reopened,
    ];

    /// <summary>هل المهمة متأخّرة؟ — **نشِطةٌ ومضى يومُها كاملاً** (قاعدة <see cref="LocalClock"/>).</summary>
    public static bool IsOverdue(DmsTaskStatus status, DateTime dueDate) =>
        IsActive(status) && dueDate.Date < LocalClock.Today;

    /// <summary>الاسم العربي للحالة (Hint: يظهر في رسائل الخطأ ووصف سجلّ المهمة).</summary>
    public static string ArabicName(DmsTaskStatus status) => status switch
    {
        DmsTaskStatus.New => "جديدة",
        DmsTaskStatus.InProgress => "قيد التنفيذ",
        DmsTaskStatus.OnHold => "معلّقة",
        DmsTaskStatus.Completed => "مكتملة",
        DmsTaskStatus.Cancelled => "ملغاة",
        DmsTaskStatus.Reopened => "أُعيد فتحها",
        _ => status.ToString(),
    };

    /// <summary>الاسم العربي للأولوية.</summary>
    public static string ArabicName(DmsTaskPriority priority) => priority switch
    {
        DmsTaskPriority.Low => "منخفضة",
        DmsTaskPriority.Normal => "عادية",
        DmsTaskPriority.High => "عالية",
        DmsTaskPriority.Urgent => "عاجلة",
        _ => priority.ToString(),
    };

    /// <summary>الاسم العربي لنوع المهمة.</summary>
    public static string ArabicName(DmsTaskType type) => type switch
    {
        DmsTaskType.Individual => "فردية",
        DmsTaskType.Department => "قسم",
        _ => type.ToString(),
    };
}
