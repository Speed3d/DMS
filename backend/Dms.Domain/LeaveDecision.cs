namespace Dms.Domain;

/// <summary>
/// **قواعد الإجازة الذاتيّة والبتّ فيها** — منطق مجال نقيّ (ADR-033).
/// </summary>
/// <remarks>
/// 🔴 **سبب وجود هذا الملف:** الطلب الذاتيّ يصل بـ<c>DeductFromSalary = false</c> **لا
/// كقرارٍ بل كغيابِ قرار**. والفرق بينهما لا يظهر في نوع البيانات — كلاهما <c>false</c> —
/// فيمرّ الافتراض صامتاً عند الموافقة، وتُحتسب إجازةُ شهرٍ **بلا راتب** مدفوعةً.
///
/// وهذا **العطل نفسه** الذي كلّف الوحدة ADR-028: علَمٌ يبدو محسوماً وهو لم يُحسم. ولذلك
/// تُكتب القاعدة هنا مرّةً ويُسأل عنها، بدل أن تتوزّع شرطاً في الخدمة وشرطاً في الواجهة
/// وشرطاً في السكربت — فتتباعد الثلاثة بعد أشهر بلا أن يسقط شيء.
/// </remarks>
public static class LeaveDecision
{
    /// <summary>
    /// **حالة الطلب الذاتيّ عند إنشائه — معلّقةٌ دائماً**.
    /// </summary>
    /// <remarks>
    /// ⚠️ ثابتٌ لا معطى: <c>LeaveService.CreateAsync</c> يشتقّ الحالة من
    /// <c>RequiresApproval</c> القادمة من العميل، وذلك صحيحٌ هناك لأن المُدخِل **كاتب
    /// شؤون** يملك منح الإجازة بلا موافقة. أمّا الطالبُ لنفسه فلا يملكها — ولو قُرئت منه
    /// لمنح نفسه إجازةً مقبولةً فور تسجيلها.
    /// </remarks>
    public const LeaveStatus SelfRequestStatus = LeaveStatus.Pending;

    /// <summary>
    /// قرارُ الحسم بعد المراجعة.
    /// </summary>
    /// <param name="approve">هل وُوفق على الإجازة؟</param>
    /// <param name="reviewerDecision">
    /// ما قرّره المراجع — <c>null</c> يعني **لم يقرّر شيئاً** فيبقى المسجَّل كما هو.
    /// </param>
    /// <param name="current">الحسم المسجَّل على السطر الآن.</param>
    /// <remarks>
    /// 🔴 **الرفض لا يمسّ الحسم** — إجازةٌ مرفوضة لم تقع، فلا معنى لقرارٍ في شأنها. ولو
    /// كُتب الحسم عند الرفض لبقي أثرُه لو أُعيد فتح الطلب لاحقاً.
    ///
    /// 🔴 **و<c>null</c> تُبقي المسجَّل ولا تكتب <c>false</c>** — وهذا هو التوافق الخلفي
    /// كلُّه: سطرٌ أدخله كاتب الشؤون بقرار «تُحسم» يمرّ من هنا عند الموافقة، ولو كتبنا
    /// <c>false</c> لأن العميل القديم لا يرسل الحقل **لانقلب قرارُه صامتاً**.
    /// </remarks>
    public static bool ResolveDeduction(bool approve, bool? reviewerDecision, bool current)
    {
        if (!approve) return current;
        return reviewerDecision ?? current;
    }

    /// <summary>
    /// هل يسحب صاحبُ الطلب طلبَه؟
    /// </summary>
    /// <remarks>
    /// **شرطان معاً لا أحدهما:**
    /// <list type="number">
    /// <item><b>ذاتيّ</b> — وإلا محا الموظف إجازةً سجّلها عليه كاتب الشؤون، وهي
    /// **واقعةٌ حصلت** لا طلبٌ ينتظر.</item>
    /// <item><b>معلّق</b> — وإلا سحب إجازةً موافَقاً عليها بعد أن بُني عليها كشفُ الشهر،
    /// أو أعاد فتح طلبٍ مرفوض بمحوه.</item>
    /// </list>
    /// </remarks>
    public static bool CanSelfCancel(bool isSelfRequested, LeaveStatus status) =>
        isSelfRequested && status == LeaveStatus.Pending;

    /// <summary>
    /// هل يحتاج هذا الطلب قرارَ حسمٍ من المراجع قبل الموافقة؟
    /// </summary>
    /// <remarks>
    /// ⚠️ **مرآةُ سؤال الواجهة**: حوارُ «تُحسم؟» يظهر بهذا الشرط بالضبط — فلا يُسأل
    /// المراجع عن سطرٍ جاء بقراره معه، ولا يُترك بلا سؤالٍ سطرٌ جاء بلا قرار.
    /// </remarks>
    public static bool NeedsDeductionDecision(bool isSelfRequested, LeaveStatus status) =>
        isSelfRequested && status == LeaveStatus.Pending;
}
