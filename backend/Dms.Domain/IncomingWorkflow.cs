namespace Dms.Domain;

/// <summary>
/// دورة حياة الكتاب الوارد — منطق مجال نقي بلا اعتماد على بنية تحتية.
/// Hint: هذا هو مصدر الحقيقة الوحيد لانتقالات الحالة؛ الخدمة تفرضه والواجهة تعكسه.
/// </summary>
public static class IncomingWorkflow
{
    /// <summary>
    /// مصفوفة الانتقالات المسموحة.
    /// Hint: مصفوفة مغلقة — أي انتقال غير مذكور هنا مرفوض (يحمي السجل الرسمي من العودة للخلف).
    /// </summary>
    private static readonly Dictionary<IncomingStatus, IncomingStatus[]> Transitions = new()
    {
        [IncomingStatus.New] = [IncomingStatus.InReview, IncomingStatus.Closed],
        [IncomingStatus.InReview] = [IncomingStatus.Replied, IncomingStatus.Closed],
        [IncomingStatus.Replied] = [IncomingStatus.Closed],
        [IncomingStatus.Closed] = [IncomingStatus.Archived],

        // ⚠️ **فكّ الأرشفة** (قرار المالك 2026-07-28، يُعدّل ADR-013): الأرشفة كانت نهائية
        //    بلا رجعة، وهو ما جعل خطأً واحداً في الأرشفة غير قابل للتصحيح إلا بحذف الكتاب.
        //    الآن يعود إلى «مغلق» — وهي حالته قبل الأرشفة، فلا يُخترع مسار جديد.
        //    الحارس مضاعف: **المدير فأعلى + سبب إلزامي** (انظر EnsureStatusChangePermission
        //    و ChangeStatusAsync)، لأن هذا يفتح **قفل التعديل الوحيد** على السجل الرسمي.
        [IncomingStatus.Archived] = [IncomingStatus.Closed],
    };

    /// <summary>الحالات التي يمكن الانتقال إليها من الحالة المعطاة (قائمة فارغة = حالة نهائية).</summary>
    public static IReadOnlyList<IncomingStatus> NextStatuses(IncomingStatus from) =>
        Transitions.TryGetValue(from, out var next) ? next : [];

    /// <summary>هل الانتقال مسموح؟ (Hint: البقاء على نفس الحالة ليس انتقالاً صالحاً).</summary>
    public static bool CanTransition(IncomingStatus from, IncomingStatus to) =>
        from != to && NextStatuses(from).Contains(to);

    /// <summary>
    /// يتحقق من الانتقال ويرمي استثناءً عربياً واضحاً عند الرفض.
    /// Hint: تُستدعى من الخدمة قبل أي تغيير حالة يدوي.
    /// </summary>
    public static void EnsureTransitionAllowed(IncomingStatus from, IncomingStatus to)
    {
        if (from == to)
            throw new ValidationException($"الكتاب في حالة ({ArabicName(to)}) أصلاً.");

        if (!CanTransition(from, to))
            throw new ValidationException($"انتقال غير مسموح: من ({ArabicName(from)}) إلى ({ArabicName(to)}).");
    }

    /// <summary>هل الحالة تسمح بالإجراءات التشغيلية (الإحالة والربط بصادر)؟</summary>
    public static bool IsOperable(IncomingStatus status) =>
        status is IncomingStatus.New or IncomingStatus.InReview;

    /// <summary>الاسم العربي للحالة (Hint: يظهر للمستخدم في رسائل الخطأ ووصف سجل الحركة).</summary>
    public static string ArabicName(IncomingStatus status) => status switch
    {
        IncomingStatus.New => "جديد",
        IncomingStatus.InReview => "قيد المراجعة",
        IncomingStatus.Replied => "تم الرد",
        IncomingStatus.Closed => "مغلق",
        IncomingStatus.Archived => "مؤرشف",
        _ => status.ToString(),
    };
}
