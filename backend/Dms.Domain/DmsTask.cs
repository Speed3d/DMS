namespace Dms.Domain;

/// <summary>
/// مهمة — وحدة عملٍ مُسنَدة لموظفٍ أو لقسم، لها موعدٌ وحالةٌ ونسبةُ تقدّم (ADR-037).
/// </summary>
/// <remarks>
/// ⚠️ **الاسم <c>DmsTask</c> لا <c>Task</c>** — و<c>System.Threading.Tasks.Task</c> مستوردٌ
/// عالمياً بـ<c>ImplicitUsings</c> في المشاريع الثلاثة، فاسمٌ مطابقٌ له يُنتج <c>CS0104</c>
/// في **كل** ملفٍ فيه <c>using Dms.Domain;</c>. والقاعدة نفسها تسري على أنواع الوحدة كلها
/// (<see cref="DmsTaskStatus"/> · <see cref="DmsTaskType"/> · <see cref="DmsTaskPriority"/>).
///
/// 🔴 **والموعد يومٌ لا لحظة** (<see cref="LocalClock"/>): <c>DueDate</c> يُخزَّن عند 00:00
/// ويُقاس بيومه كاملاً. لولا ذلك صارت مهمةٌ موعدها 15 آب **متأخرةً الساعة 3:00 فجراً من
/// يوم 15 نفسه** — وهو صنف العطل الذي كلّف المشروع مرّتين (حساب شباط · انعكاس تاريخ الإيصال).
/// </remarks>
public class DmsTask
{
    // ── المعرّف والترقيم ──
    public int TaskId { get; set; }
    public int CompanyId { get; set; }

    /// <summary>الرقم الرسمي للمهمة — <c>DEN-TSK-2026-00001</c>. يُولَّد عند الإنشاء.</summary>
    public string? TaskNumber { get; set; }

    public int? Year { get; set; }
    public int? SerialNo { get; set; }

    // ── المحتوى ──
    public string Title { get; set; } = string.Empty;

    /// <summary>وصفٌ حرّ — **نصٌّ لا HTML**: المهمة تكليفٌ لا وثيقةٌ تُطبع بقالب.</summary>
    public string? Description { get; set; }

    // ── التصنيف ──
    public DmsTaskType TaskType { get; set; }
    public DmsTaskPriority Priority { get; set; }
    public DmsTaskStatus Status { get; set; }

    /// <summary>نسبة الإنجاز 0..100 — يضبطها صاحب المهمة، ولا تُشتقّ من الحالة.</summary>
    public int ProgressPercent { get; set; }

    // ── المواعيد ──
    /// <summary>**يومُ الاستحقاق لا لحظتُه** — يُخزَّن عند 00:00 ويُقاس بيومه كاملاً.</summary>
    public DateTime DueDate { get; set; }

    public DateTime? StartDate { get; set; }
    public DateTime? CompletedDate { get; set; }

    // ── الإسناد ──
    /// <summary>قسمُ المهمة حين تكون <see cref="DmsTaskType.Department"/> — يراها كل موظفيه.</summary>
    public int? DepartmentId { get; set; }

    public int? AssignedToUserId { get; set; }
    public int CreatedByUserId { get; set; }

    // ── الربط بالوثائق ──
    public int? RelatedIncomingId { get; set; }
    public int? RelatedOutgoingId { get; set; }

    // ── التكرار ──
    /// <summary>**الأمّ وحدها تحمل <c>true</c>** — والنُسَخ المولَّدة منها مهامُّ عاديّة.</summary>
    /// <remarks>
    /// 🔴 بدون هذا القيد تُنجب كلُّ نسخةٍ نسخاً، والخدمة الخلفية تعمل كل ساعة ⇒ **تكاثرٌ
    /// أُسّي**. والحارس مضاعف: فحصُ وجودٍ قبل الإنشاء **وفهرسٌ فريد مُرشَّح** على
    /// <c>(ParentRecurringTaskId, DueDate)</c> في القاعدة — فحتى تشغيلان متزامنان لا يُكرّران.
    /// </remarks>
    public bool IsRecurring { get; set; }

    public DmsRecurrencePattern? RecurrencePattern { get; set; }
    public int? RecurrenceInterval { get; set; }
    public DateTime? RecurrenceEndDate { get; set; }
    public int? ParentRecurringTaskId { get; set; }

    // ── حالة التصعيد — تُكتب من الخدمة الخلفية وحدها ──
    /// <summary>آخر مستوى تصعيدٍ أُرسل (0 = لا شيء · 1 المسؤول · 2 المديرون · 3 الرئاسة).</summary>
    /// <remarks>
    /// ⚠️ **في عمودٍ لا في ذاكرة الخدمة**: خدمةٌ خلفية تُعيد تشغيل نفسها مع كل تحديثٍ أو
    /// إعادة إقلاع، وحالةٌ في الذاكرة تعني **إعادة إرسال كل التصعيدات** بعد كل إقلاع.
    /// </remarks>
    public int LastEscalationLevel { get; set; }

    public DateTime? LastEscalatedAt { get; set; }

    /// <summary>تاريخ إرسال تذكير «يقترب موعدها» — وجودُه يمنع تكراره.</summary>
    public DateTime? DueSoonNotifiedAt { get; set; }

    public string? Notes { get; set; }

    // ── بنية تحتية ──
    /// <summary>تزامنٌ متفائل — **<c>byte[]?</c>** كسابقة <c>OutgoingBook</c> و<c>PayrollPeriod</c>.</summary>
    /// <remarks>
    /// ⚠️ **وفي عقد الـAPI يُمرَّر نصّاً (base64) لا مصفوفةَ أرقام** — فـ<c>byte[]</c> في
    /// ASP.NET Core يُسلسَل <c>"AAAAAAABftE="</c>، وقراءتُه <c>List&lt;int&gt;</c> في العميل
    /// أسقطت شاشةً كاملة في وحدة الرواتب.
    /// </remarks>
    public byte[]? RowVersion { get; set; }

    // حذف ناعم (قاعدة المشروع: لا حذف فعلي)
    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    // ── تنقّل ──
    public Company Company { get; set; } = null!;
    public Department? Department { get; set; }
    public User? AssignedToUser { get; set; }
    public User CreatedByUser { get; set; } = null!;
    public IncomingBook? RelatedIncoming { get; set; }
    public OutgoingBook? RelatedOutgoing { get; set; }
    public DmsTask? ParentRecurringTask { get; set; }

    public ICollection<DmsTaskUpdate> Updates { get; set; } = new List<DmsTaskUpdate>();
    public ICollection<DmsTask> RecurringInstances { get; set; } = new List<DmsTask>();
}
