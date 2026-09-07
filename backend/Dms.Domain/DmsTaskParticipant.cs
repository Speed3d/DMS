namespace Dms.Domain;

/// <summary>
/// مشاركٌ في مهمة — **شخصٌ أو قسم** يرى المهمة ويعمل عليها بلا أن يكون مسؤولها (ADR-037).
/// </summary>
/// <remarks>
/// 🔴 **لماذا كيانٌ منفصل ولا يكفي <c>AssignedToUserId</c> و<c>DepartmentId</c> على المهمة؟**
/// لأن كليهما **واحد**، وإعادةُ الإسناد **تستبدل** — فيفقد السابقُ رؤية المهمة صامتاً، ويبقى
/// اسمُه في سجلّها لا يستطيع فتحه ليقرأ ما كتب. (بلاغ المالك 2026-09-06.)
///
/// **والنموذج المُعتمَد: مسؤولٌ واحد محاسَب + مشاركون كُثر** (قرار المالك):
/// <list type="bullet">
/// <item><c>DmsTask.AssignedToUserId</c> يبقى **مَن عليه العمل** — التصعيد يحتاج شخصاً واحداً
/// يُنبَّه أولاً، والتقرير يحتاج «على مَن هذا؟». و«الكلُّ مسؤول» تعني عملياً **لا أحد**.</item>
/// <item>وهذا الكيان يجيب سؤالاً آخر: **مَن يرى؟** — ويُضاف إليه على مراحل.</item>
/// </list>
///
/// ⚠️ **وأحدُ الحقلين لا كلاهما**: صفٌّ يحمل <see cref="UserId"/> **أو** <see cref="DepartmentId"/>
/// — لأن «قسمٌ بعينه لشخصٍ بعينه» معنًى لا يريده أحد، وصفٌّ فارغٌ منهما يفتح المهمة للجميع
/// صامتاً. يحرسه <see cref="TaskParticipation.EnsureValid"/> وقيدٌ في القاعدة.
/// </remarks>
public class DmsTaskParticipant
{
    public int ParticipantId { get; set; }
    public int TaskId { get; set; }

    /// <summary>منسوخٌ للفلترة المباشرة — نظير <see cref="DmsTaskUpdate.CompanyId"/>.</summary>
    public int CompanyId { get; set; }

    /// <summary>مشاركٌ شخص — أو <c>null</c> إن كان الصفّ لقسم.</summary>
    public int? UserId { get; set; }

    /// <summary>مشاركٌ قسم — أو <c>null</c> إن كان الصفّ لشخص.</summary>
    public int? DepartmentId { get; set; }

    public int AddedByUserId { get; set; }
    public DateTime AddedAt { get; set; }

    /// <summary>سبب الإضافة أو ملاحظةٌ عليها — يُقرأ في سجلّ المهمة.</summary>
    public string? Note { get; set; }

    // ── الإزالة: حذفٌ ناعم (قاعدة المشروع) ──
    /// <summary>أُزيل من المشاركين — **فلا يرى المهمة بعدها**.</summary>
    /// <remarks>
    /// ⚠️ **ناعمٌ لا فعليّ**: مَن شارك في مهمةٍ ثم أُزيل **واقعةٌ تُقرأ** — ولو مُحي صفُّه
    /// لصار سجلّ المهمة يذكر اسمه بلا أن يُعرف متى دخل ومتى خرج.
    /// 🔴 **والفلتر عليه في <c>TaskService.Query()</c> وحدها** — وهي الموضع الوحيد لقاعدة
    /// الرؤية، فنسيانُه في موضعٍ ثانٍ يعني **تسريب رؤية**.
    /// </remarks>
    public bool IsRemoved { get; set; }

    public int? RemovedByUserId { get; set; }
    public DateTime? RemovedAt { get; set; }

    // ── تنقّل ──
    public DmsTask Task { get; set; } = null!;
    public User? User { get; set; }
    public Department? Department { get; set; }

    /// <summary>اسم مَن أضاف — **محسوبٌ لا مخزَّن** (<c>[NotMapped]</c>).</summary>
    /// <remarks>
    /// ⚠️ **لماذا حقلٌ مؤقّت ولا خاصيةُ تنقّل إلى <c>User</c>؟** لأن ربطاً ثانياً إلى
    /// <c>Users</c> المفلتَر يُعيد المشكلة نفسها: اسمُ مُضيفٍ سوبر أدمن يصل فارغاً، وخاصيةٌ
    /// إلزامية تُسقط الصفّ كلَّه. الخدمة تملؤه باستعلامٍ ثانٍ — نمط ADR-034.
    /// </remarks>
    [System.ComponentModel.DataAnnotations.Schema.NotMapped]
    public string? AddedByUserName { get; set; }
}

/// <summary>
/// قواعد المشاركة — منطقٌ نقيّ في موضعٍ واحد (نظير <see cref="TaskChangeReason"/>).
/// </summary>
public static class TaskParticipation
{
    /// <summary>يتحقّق أن الصفّ يحمل **أحد الحقلين لا كليهما ولا لا شيء**.</summary>
    /// <remarks>
    /// 🔴 **صفٌّ بلا الاثنين هو الخطر الحقيقي**: لا يشير إلى أحد، فلا يمنح رؤيةً لأحد —
    /// لكنه يظهر في القائمة كمشاركٍ فارغ فيظنّ المالك أنه أضاف من لم يُضِف.
    /// و**صفٌّ بالاثنين معاً** معنًى لا يريده أحد: «سنان بصفته من قسم المالية» ليس شيئاً
    /// ثالثاً — هو إمّا سنان وإمّا القسم.
    /// </remarks>
    public static void EnsureValid(int? userId, int? departmentId)
    {
        if (userId is null && departmentId is null)
            throw new ValidationException("حدّد مشاركاً: مستخدماً أو قسماً.");

        if (userId is not null && departmentId is not null)
            throw new ValidationException("المشارك مستخدمٌ أو قسم — لا الاثنان معاً.");
    }

    /// <summary>وصفٌ عربيٌّ جاهز لقيد السجلّ.</summary>
    public static string DescribeAdded(string who, string? note)
        => string.IsNullOrWhiteSpace(note)
            ? $"أُضيف إلى المهمة: {who}"
            : $"أُضيف إلى المهمة: {who} — {note.Trim()}";

    public static string DescribeRemoved(string who)
        => $"أُزيل من المهمة: {who}";

    /// <summary>وصفُ نقل المسؤولية — **ويقول صراحةً ماذا حلّ بالسابق**.</summary>
    /// <remarks>
    /// ⚠️ **الفرق يجب أن يُقرأ في السجلّ لا أن يُستنتج**: مَن يقرأ «أُسندت من فلان إلى فلان»
    /// بعد شهرٍ لا يعرف أبقي الأولُ يرى المهمة أم نُزعت رؤيته — وهو فرقٌ يغيّر مَن كان
    /// يستطيع متابعتها.
    /// </remarks>
    public static string DescribeHandover(string from, string to, bool keptAsParticipant)
        => keptAsParticipant
            ? $"أُسندت المهمة من ({from}) إلى ({to}) — وبقي ({from}) مشاركاً يراها"
            : $"أُسندت المهمة من ({from}) إلى ({to}) — ونُزعت رؤية ({from}) عنها";
}
