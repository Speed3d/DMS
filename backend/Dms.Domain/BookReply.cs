namespace Dms.Domain;

/// <summary>
/// ربطُ كتابٍ صادرٍ بكتابٍ واردٍ يردّ عليه — علاقةٌ **كثيرٌ إلى كثير** (ADR-045).
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **حلّ محلّ عمودين مفردين** (<c>IncomingBook.ReplyOutgoingId</c> و
/// <c>OutgoingBook.ReplyToIncomingId</c>) بقرار المالك بعد سيناريو حقيقيّ كسر افتراضَين معاً:
/// صادرٌ واحد أجاب **ثلاثة** واردات، وواردٌ واحد يُجاب **بردٍّ أوّليّ ثم نهائيّ**.
/// </para>
/// <para>
/// ⚠️ **والعمودان كانا ازدواجاً يُزامَن يدوياً في ثلاثة مواضع** — وقد انحرفا فعلاً:
/// حذفُ الوارد كان يُفرغ جهة الصادر ويترك جهته، وحذفُ الصادر **لا يُفرغ شيئاً**. الجدول
/// الواحد يُغلق هذا الباب بالبناء.
/// </para>
/// <para>
/// **فريد على (IncomingId, OutgoingId):** ربطُ الزوج نفسه مرّتين لا معنى له، والفهرس حارسُ
/// تسابقٍ فوق فحص الوجود في الخدمة (نظير <c>EmployeeLeaveSettlement</c>).
/// </para>
/// </remarks>
public class BookReply
{
    public int BookReplyId { get; set; }

    public int IncomingId { get; set; }
    public IncomingBook? Incoming { get; set; }

    public int OutgoingId { get; set; }
    public OutgoingBook? Outgoing { get; set; }

    /// <summary>
    /// الشركة المالكة — **منسوخةٌ للفلترة المباشرة** خلافاً لسابقة <see cref="IncomingAssignment"/>.
    /// </summary>
    /// <remarks>
    /// ⚠️ تلك تُقرأ عبر أبيها المفلتَر وحده، أما هذا الجدول فيُستعلَم عنه **مباشرةً** من جهة
    /// الصادر («ما الوارداتُ التي ردّ عليها هذا الكتاب؟») — واستعلامٌ بلا فلتر يرى شركتين.
    /// </remarks>
    public int CompanyId { get; set; }

    /// <summary>مَن ربط — **لاغٍ وبلا مفتاح أجنبيّ**.</summary>
    /// <remarks>
    /// 🔴 **لاغٍ** لأن الروابط المنقولة من العمودين القديمين **بلا فاعلٍ تاريخيّ**، و<c>0</c>
    /// يخرق أيّ مفتاحٍ أجنبيّ فتفشل المهاجرة.
    /// ⚠️ **وبلا مفتاحٍ أجنبيّ** نظير <c>Employee.UserId</c>: <c>User</c> له فلترٌ عامّ مختلف،
    /// ومفتاحٌ أجنبيّ نحوه يجعل حذف المستخدم يتعثّر أو يجرّ الرابط معه. والاسم يُجلب عند
    /// العرض ويعود «—» لما لا يُعرَف (نمط ADR-034).
    /// </remarks>
    public int? LinkedByUserId { get; set; }

    public DateTime LinkedAt { get; set; }
}
