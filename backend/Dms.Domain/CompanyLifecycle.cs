namespace Dms.Domain;

/// <summary>ما تحويه الشركة فعلاً — يُعرَض للمالك **قبل** الحذف (ADR-047).</summary>
/// <remarks>
/// 🔑 **«لا تحذف ما لا تراه».** الحذف الجذريّ بلا بيانٍ مسبق يجعل المالك يوافق على ما
/// لا يعرفه — وهو بعينه ما أوقعه في تصفير القاعدة: زرٌّ أحمر وحوارُ تحذيرٍ عامّ بلا رقم.
/// </remarks>
/// <param name="LiveOutgoing">صادرٌ **غير محذوف**.</param>
/// <param name="DeletedOutgoing">صادرٌ محذوفٌ ناعماً — يُذكر ليُعلم أنه سيُمحى فعلياً.</param>
public sealed record CompanyContents(
    int LiveOutgoing, int DeletedOutgoing,
    int LiveIncoming, int DeletedIncoming,
    int Archive, int Employees, int Tasks, int CaseFiles,
    int Users, int SoleCompanyUsers, int Departments, int Entities, int Templates)
{
    /// <summary>ما يمنع الحذف: أيُّ سجلٍّ **غير محذوف** (قرار المالك 2026-09-21).</summary>
    /// <remarks>
    /// ⚠️ **الموظفون والمهام والمعاملات معه** — لا الكتب وحدها: شركةٌ فيها موظفٌ له كشف
    /// رواتب ليست «فارغة» بأي معنى.
    /// </remarks>
    public int LiveRecords => LiveOutgoing + LiveIncoming + Archive + Employees + Tasks + CaseFiles;

    /// <summary>ما سيُمحى فعلياً لو مضى الحذف — **بما فيه المحذوف ناعماً**.</summary>
    public int WillBeErased => LiveRecords + DeletedOutgoing + DeletedIncoming;
}

/// <summary>سببُ منع تعطيل الشركة أو حذفها — <c>null</c> يعني «مسموح».</summary>
public enum CompanyBlockReason
{
    None = 0,
    /// <summary>فيها مستخدمٌ لا يملك شركةً غيرها ⇒ تعطيلُها يُقفله خارج النظام كلِّه.</summary>
    SoleCompanyUsers = 1,
    /// <summary>الشركة الفعّالة الآن — يُبدَّل منها أولاً.</summary>
    IsActiveCompany = 2,
    /// <summary>آخر شركةٍ في النظام — نظامٌ بلا شركةٍ لا يعمل.</summary>
    LastCompany = 3,
    /// <summary>لم تُعطَّل بعد — والحذف خطوتان لا واحدة.</summary>
    StillEnabled = 4,
    /// <summary>فيها سجلّاتٌ غير محذوفة.</summary>
    HasLiveRecords = 5,
    /// <summary>نصُّ التأكيد لا يطابق اسم الشركة.</summary>
    BadConfirmation = 6,
}

/// <summary>
/// قواعد دورة حياة الشركة: **التعطيل ثم الحذف** — منطق مجالٍ نقيّ (ADR-047).
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **لماذا مستويان؟** لأن «حذف الشركة» طلبان مختلفان يلبسان اسماً واحداً:
/// <b>«أنشأتُها بالخطأ فأزيلوها»</b> و<b>«توقّفنا عن العمل بها»</b>. الأول يريد محواً،
/// والثاني يريد **إخفاءً مع بقاء السجلّ** — ودمجُهما في زرٍّ واحد يعني أن أحدهما يقع
/// بالخطأ مكان الآخر.
/// </para>
/// <para>
/// ⚠️ **والتعطيل كان علَماً تجميلياً**: <c>Company.IsActive</c> كان يُقرأ ويُكتب **ولا
/// يُفحص في موضعٍ واحد** في الخادم ولا في الواجهة — فالشركة «المعطَّلة» تظهر في المبدّل
/// ويُنشأ فيها كتاب. وهي **ثالثُ** تكرارٍ للعائلة نفسها (ADR-028 · ADR-036).
/// 🔑 **والأسوأ أن رسالة رفض الحذف كانت تقول «عطّل الشركة بدل حذفها»** — أي تُحيل
/// المالك إلى ميزةٍ لا وجود لها، فيبحث عن مخرجٍ ثالث. **وقد وجده: زرّ تصفير القاعدة.**
/// </para>
/// </remarks>
public static class CompanyLifecycle
{
    /// <summary>هل يجوز تعطيل الشركة؟</summary>
    /// <param name="soleCompanyUsers">
    /// عددُ المستخدمين الذين **هذه الشركة إسنادُهم الوحيد** (السوبر أدمن مستثنى — يرى الكل).
    /// </param>
    /// <remarks>
    /// 🔴 **الحارس الوحيد هنا وجوديّ لا تجميليّ**: التعطيل يُخرج الشركة من توكن المستخدم،
    /// فمن لا يملك غيرها يصير **بلا شركةٍ فعّالة** — فلا يرى صادراً ولا وارداً ولا حتى
    /// لوحة تحكّم، **ولا رسالةَ تشرح له لماذا**. ⇒ يُنقل أولاً أو يُعطَّل حسابه.
    /// </remarks>
    public static CompanyBlockReason CanDeactivate(int soleCompanyUsers)
        => soleCompanyUsers > 0 ? CompanyBlockReason.SoleCompanyUsers : CompanyBlockReason.None;

    /// <summary>هل يجوز الحذف الجذريّ؟ — تُفحص الشروط **بالترتيب**، وأوّلُ مانعٍ يفوز.</summary>
    /// <param name="isEnabled">الشركة ما زالت مفعَّلة.</param>
    /// <param name="isActiveCompany">هي الشركة الفعّالة للطالب الآن.</param>
    /// <param name="isLastCompany">لا شركةَ غيرها في النظام.</param>
    /// <param name="contents">بيانُ ما فيها.</param>
    /// <param name="confirmation">ما كتبه المستخدم، ويجب أن يطابق <paramref name="name"/>.</param>
    /// <remarks>
    /// ⚠️ **الترتيب مقصود**: تُفحص الشروط **الرخيصة والمفهومة** أولاً (لم تُعطَّل · هي
    /// الفعّالة · آخر شركة) قبل بيان المحتويات — فيفهم المستخدم سببَ المنع من أول رسالة
    /// بدل أن يُقال له «فيها 3 سجلّات» وهو لم يصل إلى تلك المرحلة أصلاً.
    ///
    /// 🔴 **والتأكيد يُفحص أخيراً**: طلبُ كتابة الاسم قبل التأكّد من الجواز يجعل المستخدم
    /// يكتبه ثم يُرفض — فيظنّ الكتابة هي المشكلة.
    /// </remarks>
    public static CompanyBlockReason CanDelete(
        bool isEnabled, bool isActiveCompany, bool isLastCompany,
        CompanyContents contents, string name, string? confirmation)
    {
        if (isEnabled) return CompanyBlockReason.StillEnabled;
        if (isActiveCompany) return CompanyBlockReason.IsActiveCompany;
        if (isLastCompany) return CompanyBlockReason.LastCompany;
        if (contents.SoleCompanyUsers > 0) return CompanyBlockReason.SoleCompanyUsers;
        if (contents.LiveRecords > 0) return CompanyBlockReason.HasLiveRecords;

        // ⚠️ **المقارنة بعد التشذيب لا بالحرف الخام** — مسافةٌ لاصقة في آخر اللصق تُفشل
        //    مستخدماً كتب الاسم صحيحاً، فيعيد المحاولة ظانّاً أنه أخطأ.
        if (!string.Equals((confirmation ?? "").Trim(), name.Trim(), StringComparison.Ordinal))
            return CompanyBlockReason.BadConfirmation;

        return CompanyBlockReason.None;
    }

    /// <summary>رسالةٌ عربية تشرح المنع — **وتقول ماذا يفعل المستخدم بعدها**.</summary>
    /// <remarks>
    /// 🔑 **رسالةٌ تقول «لا» بلا «افعل كذا» تدفع المستخدم إلى البحث عن مخرجٍ آخر** — وهو
    /// بالضبط ما وقع. فكلُّ رسالةٍ هنا تنتهي بالخطوة التالية.
    /// </remarks>
    public static string Explain(CompanyBlockReason reason, string name, CompanyContents c) => reason switch
    {
        CompanyBlockReason.SoleCompanyUsers =>
            $"«{name}» هي الإسناد الوحيد لـ{c.SoleCompanyUsers} مستخدم — وتعطيلُها يُقفلهم خارج النظام. "
            + "أسنِدهم إلى شركةٍ أخرى أو عطّل حساباتهم أولاً.",

        CompanyBlockReason.StillEnabled =>
            $"عطّل «{name}» أولاً ثم احذفها. **الحذف خطوتان لا واحدة** — عمداً.",

        CompanyBlockReason.IsActiveCompany =>
            $"«{name}» هي شركتك الفعّالة الآن. بدّل إلى شركةٍ أخرى ثم احذفها.",

        CompanyBlockReason.LastCompany =>
            "لا يمكن حذف آخر شركةٍ في النظام — النظام بلا شركةٍ لا يعمل.",

        CompanyBlockReason.HasLiveRecords =>
            $"«{name}» تحوي {c.LiveRecords} سجلّاً غير محذوف "
            + $"({Describe(c)}). احذفها من شاشاتها أولاً، ثم احذف الشركة.",

        CompanyBlockReason.BadConfirmation =>
            $"نصُّ التأكيد لا يطابق اسم الشركة. اكتب «{name}» حرفياً.",

        _ => string.Empty,
    };

    private static string Describe(CompanyContents c)
    {
        var parts = new List<string>();
        if (c.LiveOutgoing > 0) parts.Add($"{c.LiveOutgoing} صادر");
        if (c.LiveIncoming > 0) parts.Add($"{c.LiveIncoming} وارد");
        if (c.Archive > 0) parts.Add($"{c.Archive} أرشيف");
        if (c.Employees > 0) parts.Add($"{c.Employees} موظف");
        if (c.Tasks > 0) parts.Add($"{c.Tasks} مهمة");
        if (c.CaseFiles > 0) parts.Add($"{c.CaseFiles} معاملة");
        return parts.Count > 0 ? string.Join(" · ", parts) : "—";
    }
}
