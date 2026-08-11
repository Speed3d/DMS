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

    /// <summary>
    /// حالةُ سطرٍ جديد لموظفٍ **مزدوج**، بحملِ قرار الشهر السابق (G14).
    /// </summary>
    /// <param name="isDual">هل يعمل في أكثر من شركة؟ غيرُ المزدوج لا قرارَ له أصلاً.</param>
    /// <param name="previous">حالته في الشهر السابق، أو <c>null</c> إن لم يكن له سطر.</param>
    /// <remarks>
    /// 🔴 **الحملُ في اتجاهٍ واحد عمداً — وهذا جوهر القاعدة لا تفصيلٌ فيها:**
    ///
    /// | القرار السابق | يُحمَل؟ | لماذا |
    /// |---|---|---|
    /// | «يُصرف من هنا» | ✅ | أسوأ نتائجه أن ندفع، وهو الافتراض أصلاً |
    /// | «مدفوع» (سُدِّد الشهر) | ✅ | هو القرار نفسه بعد أن تحوّل بالتسديد |
    /// | **«صُرف من شركة أخرى»** | ❌ | كونُها صرفت في آذار لا يعني أنها ستصرف في نيسان. وحملُه **يستثني راتباً فلا يقبضه الموظف من أحد** — وسكوتٌ يُنتج جوعاً أسوأ من سؤالٍ يُنتج ضغطة |
    ///
    /// ⚠️ **وإغفال «مدفوع» يُلغي الميزة كلَّها:** بعد تسديد الشهر تتحوّل
    /// <see cref="PayrollPaymentStatus.ConfirmedByThisCompany"/> إلى
    /// <see cref="PayrollPaymentStatus.PaidByThisCompany"/>، فلا يبقى القرار الصريح ظاهراً
    /// في أيّ شهرٍ مُسدَّد — ولن يُحمَل شيءٌ أبداً.
    ///
    /// ⚠️ **وحارس التقادم يبقى فوق هذا كلّه:** قرارٌ محمول ثم صرفت الشركة الأخرى ⇒ التسديد
    /// يُمنع ويُطلب حسمٌ جديد.
    /// </remarks>
    public static PayrollPaymentStatus CarryDecision(bool isDual, PayrollPaymentStatus? previous)
    {
        if (!isDual || previous is not { } last) return PayrollPaymentStatus.Unpaid;

        return last is PayrollPaymentStatus.ConfirmedByThisCompany
                    or PayrollPaymentStatus.PaidByThisCompany
            ? PayrollPaymentStatus.ConfirmedByThisCompany
            : PayrollPaymentStatus.Unpaid;
    }
}
