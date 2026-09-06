namespace Dms.Domain;

/// <summary>
/// سجلّ شاهدٌ على المهمة — **يُكتب ولا يُعدَّل ولا يُحذف** (نمط <see cref="EmployeeLog"/>).
/// </summary>
/// <remarks>
/// 🔴 **وقراءتُه لا تمرّ عبر خاصية التنقّل <see cref="Task"/>** — فهي مفلترةٌ على الحذف
/// الناعم، فيختفي السجلّ **في اللحظة التي يصير فيها أهمَّ ما يُقرأ**. وهو بعينه العيب الذي
/// وقع في فكّ إسناد الموظف (ADR-028) ثم في سجلّ تعديلات الرواتب (ADR-034):
/// <c>db.DmsTaskUpdates.Where(u =&gt; u.TaskId == id)</c> مباشرةً، والعزل باقٍ بشرط
/// <see cref="CompanyId"/>.
///
/// ⚠️ و<see cref="CompanyId"/> **منسوخٌ هنا عمداً** ليُفلتَر السجلّ مباشرةً بلا ربطٍ بجدول
/// المهام — نظيرُ <c>MovementLog</c>.
/// </remarks>
public class DmsTaskUpdate
{
    public int UpdateId { get; set; }
    public int TaskId { get; set; }
    public int CompanyId { get; set; }

    public DmsTaskUpdateType UpdateType { get; set; }

    public string? OldValue { get; set; }
    public string? NewValue { get; set; }
    public string? Comment { get; set; }

    /// <summary>وصفٌ عربيٌّ **جاهز من الخادم** — لا يُركَّب في العميل (سابقة <c>EmployeeLog</c>).</summary>
    /// <remarks>
    /// لماذا؟ لأن تركيبه في العميل يعني ترجمةً موازيةً في كل واجهةٍ قادمة (ويب · هاتف)،
    /// وتباعُدَها مسألةُ وقت. والسجلّ **شهادةٌ** فيجب أن يقرأه الجميع بالنصّ نفسه.
    /// </remarks>
    public string Description { get; set; } = string.Empty;

    public int UpdatedByUserId { get; set; }
    public DateTime UpdatedAt { get; set; }

    public DmsTask Task { get; set; } = null!;
    public User UpdatedByUser { get; set; } = null!;
}
