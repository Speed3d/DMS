namespace Dms.Domain;

/// <summary>أولوية الإشعار — تحكم لونه وترتيبه لا أكثر.</summary>
public enum NotificationPriority
{
    Normal = 0,
    High = 1,
}

/// <summary>
/// إشعارٌ لمستخدمٍ بعينه — **كيانٌ عامّ يخدم كل الوحدات** لا المهام وحدها (ADR-038).
/// </summary>
/// <remarks>
/// 🔴 **الإشعار ملكُ صاحبه** — وهذه أهمّ قاعدة فيه: لا سوبر أدمن يقرؤه ولا رئيس. وقراءةُ
/// إشعارات الغير ليست «إشرافاً» بل **اطّلاعٌ على ما وصل شخصاً بعينه**، وهو أمرٌ لا تحتاجه
/// الرقابة (لها سجلّ التدقيق) وتحتاجه الفضولُ وحده.
///
/// ⚠️ **وحذفُه فعليٌّ لا ناعم — استثناءٌ صريح من قاعدة المشروع** (`rules/security.md`):
/// الإشعار **إخطارٌ بحدث لا سجلُّ الحدث**. والسجلّ في <c>DmsTaskUpdate</c> و<c>AuditLog</c>
/// وكلاهما باقٍ. وبقاؤه إلى الأبد يعني **نموّاً بلا سقف** على قرص السيرفر الداخلي: عشرة
/// مستخدمين × إشعارَين يومياً = سبعة آلاف صفٍّ سنوياً لا يقرؤها أحد بعد أسبوع.
/// ⇒ تنظيفٌ تلقائيّ بعد <b>90 يوماً</b>.
/// </remarks>
public class Notification
{
    /// <summary>⚠️ <c>long</c> لا <c>int</c> — الجدول ينمو أسرع من كل جداول النظام.</summary>
    public long NotificationId { get; set; }

    public int CompanyId { get; set; }

    /// <summary>صاحب الإشعار — **والقراءة مقصورةٌ عليه دائماً**.</summary>
    public int RecipientUserId { get; set; }

    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;

    /// <summary>تصنيفٌ عامّ: <c>Task</c> · <c>Incoming</c> · <c>Payroll</c> …</summary>
    /// <remarks>نصٌّ لا enum: الوحدات القادمة تضيف تصنيفاتها بلا مهاجرة.</remarks>
    public string Category { get; set; } = string.Empty;

    /// <summary>الكيان المعنيّ — ليفتحه العميل عند النقر.</summary>
    public string? EntityType { get; set; }
    public int? EntityId { get; set; }

    public NotificationPriority Priority { get; set; }

    public bool IsRead { get; set; }
    public DateTime? ReadAt { get; set; }

    /// <summary>مَن تسبّب فيه — <c>null</c> تعني **النظام** (خدمةٌ خلفية).</summary>
    public int? CreatedByUserId { get; set; }

    public DateTime CreatedAt { get; set; }

    /// <summary>
    /// مفتاح إزالة التكرار — مثل <c>"task:42:esc:2"</c>.
    /// </summary>
    /// <remarks>
    /// 🔴 **حارسٌ ضدّ إغراقٍ لا ضدّ خطأ برمجيّ فقط.** الخدمة الخلفية تعمل **كل ساعة**، ومهمةٌ
    /// متأخرةٌ أسبوعين تعني — بلا هذا المفتاح — **336 إشعاراً** عن واقعةٍ واحدة. والمستخدم
    /// الذي يرى مئة إشعارٍ متطابق **يتوقّف عن قراءة الإشعارات كلها**، فيضيع النافع مع الضارّ.
    ///
    /// ⚠️ **وفهرسٌ فريد مُرشَّح على <c>(RecipientUserId, DedupKey)</c>** — فحتى تشغيلان
    /// متزامنان للخدمة لا يُنتجان صفَّين.
    /// </remarks>
    public string? DedupKey { get; set; }

    public User Recipient { get; set; } = null!;
}

/// <summary>
/// تصنيفات الإشعارات ومفاتيح إزالة تكرارها — **في موضعٍ واحد** (ADR-038).
/// </summary>
/// <remarks>
/// ⚠️ **نصوصٌ متناثرة في الخدمات تتباعد**: مفتاحٌ يُكتب <c>"task:42:esc:2"</c> هنا و
/// <c>"Task:42:Esc:2"</c> هناك يُنتج إشعارين لواقعةٍ واحدة — والفهرس الفريد **لا يكشفه**
/// لأنهما نصّان مختلفان فعلاً.
/// </remarks>
public static class NotificationKeys
{
    public const string TaskCategory = "Task";

    public static string TaskAssigned(int taskId) => $"task:{taskId}:assigned";
    public static string TaskReopened(int taskId) => $"task:{taskId}:reopened";
    public static string TaskCompleted(int taskId) => $"task:{taskId}:completed";

    /// <summary>تذكير «يقترب موعدها» — **مرّةً واحدة لكل مهمة** (الدفعة ٦).</summary>
    public static string TaskDueSoon(int taskId) => $"task:{taskId}:duesoon";

    /// <summary>تصعيدٌ بمستوى — **إشعارٌ واحد لكل (مهمة × مستوى)** لا تذكيرٌ يوميّ.</summary>
    /// <remarks>
    /// قرارٌ مُعلَّل: مهمةٌ متأخرة أسبوعين × خمسة مديرين = **70 إشعاراً بلا معلومةٍ جديدة**.
    /// والتصعيد يقول «ساءت الحال» — **والحال لا تسوء كل يوم**.
    /// </remarks>
    public static string TaskEscalation(int taskId, int level) => $"task:{taskId}:esc:{level}";
}
