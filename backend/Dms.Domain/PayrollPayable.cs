using System.Linq.Expressions;

namespace Dms.Domain;

/// <summary>
/// **القاعدة الواحدة لِما تدفعه الشركة فعلاً** — منطق مجال نقيّ (ADR-028).
/// </summary>
/// <remarks>
/// 🔴 **سبب وجود هذا الملف:** كان علَم «مدفوع من شركة أخرى» (ADR-024) يلوّن السطر ويكتب
/// ملاحظةً **ولا يغيّر رقماً واحداً**. فوجدنا في قاعدة عمل المالك (2026-08-06) شهرَين
/// مُسدَّدين احتُسب فيهما راتبُ موظفةٍ صرفته شركةٌ أخرى — **3,680,000 د.ع** ضمن المدفوع،
/// وكانون الثاني كان إجماليه **راتبَها وحدها**.
///
/// والسبب المباشر أن الجمع كان مكرَّراً في **ثمانية مواضع** بلا شرط: إجمالي الكشف · Excel ·
/// PDF · إجماليات السنة · إجماليات الأشهر · سجلّ التدقيق · وبطاقتا لوحة التحكم. وتوزيعُ
/// الشرط عليها ثمانيَ مرّات هو **بالضبط** كيف يعود العيب بعد أشهر: يُضاف مخرجٌ تاسع فينساه.
///
/// ⇒ **القاعدة تُكتب مرّةً هنا، ويُسأل عنها**. ومَن أضاف مخرجاً جديداً فنسيها، تكشفه
/// حرّاس E2E التي تفحص **كل مخرج على حدة** لا واحداً منها.
/// </remarks>
public static class PayrollPayable
{
    /// <summary>
    /// هل يدخل سطرٌ بهذه الحالة في ما **تدفعه هذه الشركة**؟
    /// </summary>
    /// <remarks>
    /// المستثنى واحدٌ فقط: <see cref="PayrollPaymentStatus.PaidByOtherCompany"/>.
    /// و<see cref="PayrollPaymentStatus.ConfirmedByThisCompany"/> **تدخل** — فهي قرارٌ
    /// بالصرف من هنا لا إعفاءٌ منه.
    /// </remarks>
    public static bool Includes(PayrollPaymentStatus status) =>
        status != PayrollPaymentStatus.PaidByOtherCompany;

    /// <summary>
    /// الصيغة نفسها كشجرة تعبير — لاستعلامات EF.
    /// </summary>
    /// <remarks>
    /// ⚠️ **لماذا نسخةٌ ثانية؟** لأن EF لا تترجم استدعاء دالّةٍ عادية داخل شجرة تعبير، فلو
    /// استُعملت <see cref="Includes"/> في <c>Where</c> على <c>IQueryable</c> لانفجر الاستعلام
    /// وقت التشغيل. والنسختان **مربوطتان باختبارٍ يمرّ كل قيم الـenum عليهما معاً**، فلا
    /// تتباعدان صامتتين.
    /// </remarks>
    public static readonly Expression<Func<PayrollEntry, bool>> Predicate =
        e => e.PaymentStatus != PayrollPaymentStatus.PaidByOtherCompany;

    /// <summary>مجموع ما تدفعه الشركة بالدينار — **الرقم الذي يُصرف**.</summary>
    public static decimal TotalIqd(IEnumerable<PayrollEntry> entries) =>
        entries.Where(e => !e.IsDeleted && Includes(e.PaymentStatus)).Sum(e => e.NetSalaryIqd);

    /// <summary>
    /// مجموع ما استُثني لأن شركةً أخرى صرفته — **يُعرض ولا يُطرح صامتاً**.
    /// </summary>
    /// <remarks>
    /// إسقاطُ المبلغ بلا ذكرٍ يجعل المحاسب يرى إجمالياً أقلّ مما في الكشف بلا تفسير،
    /// فيظنّه خطأ حساب. والتصريح به يجيب عن السؤال قبل أن يُطرح.
    /// </remarks>
    public static decimal ExcludedIqd(IEnumerable<PayrollEntry> entries) =>
        entries.Where(e => !e.IsDeleted && !Includes(e.PaymentStatus)).Sum(e => e.NetSalaryIqd);

    /// <summary>السطور التي تدفعها الشركة فعلاً (للإيصالات وحرّاس التسديد).</summary>
    public static IEnumerable<PayrollEntry> Payable(IEnumerable<PayrollEntry> entries) =>
        entries.Where(e => !e.IsDeleted && Includes(e.PaymentStatus));
}
