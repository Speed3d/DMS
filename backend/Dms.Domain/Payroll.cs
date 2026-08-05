namespace Dms.Domain;

/// <summary>
/// كشف رواتب شهر واحد في شركة واحدة. **لا كيان «سنة»** — السنوات تُشتق بـ<c>GROUP BY Year</c>
/// على هذه الفترات، فلا تُخزَّن سنةٌ فارغة لا معنى لها.
/// </summary>
public class PayrollPeriod
{
    public int PeriodId { get; set; }
    public int CompanyId { get; set; }
    public int Year { get; set; }

    /// <summary>1..12</summary>
    public int Month { get; set; }

    /// <summary>
    /// سعر صرف الدولار لهذا الشهر — **يُجمَّد على الفترة** فلا يتغيّر بتغيّر السعر المركزي لاحقاً
    /// (نفس مبدأ تجميد <see cref="OutgoingBook.AmountInIqd"/>). يُملأ افتراضاً من <see cref="ExchangeRate"/>.
    /// </summary>
    public decimal? ExchangeRate { get; set; }

    public WorkingDaysMode WorkingDaysMode { get; set; }

    /// <summary>أيام العمل المعتمدة لهذا الشهر (30 عرفاً، أو أيام الشهر التقويمي).</summary>
    public int WorkingDays { get; set; } = PayrollCalculator.DefaultWorkingDays;

    public PayrollStatus Status { get; set; }
    public DateTime? PaidAt { get; set; }
    public int? PaidByUserId { get; set; }

    /// <summary>وقت آخر تعديلٍ **بعد التسديد** — `null` إن لم يُعدَّل قطّ (ADR-026).</summary>
    /// <remarks>
    /// ⚠️ **مرجعُ تقادم الإيصالات الموقَّعة**: إيصالٌ رُفع قبل هذا الوقت صار إقراراً بمبلغٍ
    /// قد لا يكون هو المخزَّن. ولهذا يُخزَّن الوقت على **الشهر** لا على السطر: تغيير سعر
    /// الصرف يمسّ كل السطور، فربطُه بسطرٍ واحد كان يُخفي أثره عن البقية.
    ///
    /// ⚠️ **ولا يُخلط بـ`UpdatedAt`**: الأخير يتغيّر مع كل حفظٍ في المسودّة أيضاً، فلو
    /// اعتُمد عليه لبدت كلُّ الإيصالات متقادمةً منذ أول تحرير.
    /// </remarks>
    public DateTime? LastAmendedAt { get; set; }

    /// <summary>عدد التعديلات بعد التسديد — يُعرض بجانب حالة الشهر ليُرى الأثر بلا فتح السجلّ.</summary>
    public int AmendmentCount { get; set; }

    /// <summary>ربط اختياري بكتاب صادر (أمر الصرف).</summary>
    public int? OutgoingBookId { get; set; }

    /// <summary>رقم كتاب يدوي حين لا يكون أمر الصرف مسجَّلاً في النظام.</summary>
    public string? ManualBookNumber { get; set; }

    public string? Notes { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    /// <summary>
    /// تزامن متفائل — الكشف يُحفَظ **دفعةً واحدة**، فمستخدمان على الشهر نفسه بلا هذا الحارس
    /// يعني أن الأخير يمحو عمل الأول بلا أن يعلم أحد.
    /// </summary>
    public byte[]? RowVersion { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    public ICollection<PayrollEntry> Entries { get; set; } = new List<PayrollEntry>();
    public OutgoingBook? OutgoingBook { get; set; }
}

/// <summary>
/// سطر راتب موظف واحد في كشف شهر واحد.
/// </summary>
/// <remarks>
/// حقول <c>Snapshot*</c> **لقطةٌ لحظةَ التوليد**: تغيير راتب الموظف في آذار يجب ألّا يُعيد كتابة
/// كشف شباط المُسدَّد. نفس مبدأ تجميد المعادل بالدينار على الكتاب الصادر.
///
/// و<see cref="NetSalary"/> و<see cref="NetSalaryIqd"/> **يحسبهما الخادم دائماً** ولا يُقبلان من
/// العميل — قاعدة المشروع أن كل منطق العمل في الباك-إند، وقيمةٌ ماليةٌ يرسلها العميل قيمةٌ
/// يستطيع العميل تزويرها.
/// </remarks>
public class PayrollEntry
{
    public int EntryId { get; set; }
    public int PeriodId { get; set; }
    public int EmployeeCompanyId { get; set; }

    /// <summary>منسوخ من الفترة — ليُفلتَر السطر مباشرةً بدل فلترٍ عبر خاصية تنقّل.</summary>
    public int CompanyId { get; set; }

    public int DisplayOrder { get; set; }

    // ── لقطات وقت التوليد ──
    public string SnapshotName { get; set; } = string.Empty;
    public string SnapshotPosition { get; set; } = string.Empty;
    public Currency SnapshotCurrency { get; set; }
    public decimal SnapshotBaseSalary { get; set; }

    // ── مدخلات ──

    /// <summary>
    /// الأيام المستحقّة من <c>WorkingDays</c>. **NOT NULL ويحسبها الخادم** — لو تُركت فارغة
    /// لكان راتب الموظف العادي صفراً.
    /// </summary>
    public int EligibleDays { get; set; }

    /// <summary>
    /// هل عدّل المستخدم الأيام المستحقّة يدوياً؟ نظير <see cref="AbsenceDeductionIsManual"/>.
    /// </summary>
    /// <remarks>
    /// ⚠️ **بدون هذا العلَم كانت الأيام تتجمّد بعد أول حساب.** كانت الخدمة تستنتج «يدويّ» من
    /// <c>EligibleDays &gt; 0</c> — وهو صحيحٌ لكل سطرٍ حُسِب مرّةً واحدة، فصار **كل** سطر
    /// محميّاً من إعادة الحساب. أثرُ ذلك أن تغيير أيام العمل أو تاريخ التعيين يُعيد حساب
    /// **الصافي** بمقامٍ جديد وبَسطٍ قديم: شباط بأيامٍ مجمّدة عند 28 ومقامٍ 30 ⇒ 28/30 من
    /// الراتب (بلاغ المالك 2026-08-05 — وهو السبب الثاني للعطل، ولم تكشفه اختبارات الوحدة
    /// لأنها تختبر <c>PayrollCalculator</c> مباشرةً ولا تمرّ من هنا).
    /// **«قيمةٌ موجودة» ليست «قيمةً اختارها إنسان» — والفرق يحتاج علَماً لا استنتاجاً.**
    /// </remarks>
    public bool EligibleDaysIsManual { get; set; }

    public int AbsenceDays { get; set; }
    public decimal? BonusAmount { get; set; }
    public decimal? DeductionAmount { get; set; }

    /// <summary>خصم الغياب المطبَّق فعلاً.</summary>
    public decimal AbsenceDeduction { get; set; }

    /// <summary>
    /// هل عدّل المستخدم خصم الغياب يدوياً؟ بدون هذا العلَم كانت كل إعادة حساب **تمحو تعديله**
    /// وتعيده إلى الرقم المقترح بلا إنذار.
    /// </summary>
    public bool AbsenceDeductionIsManual { get; set; }

    public string? Notes { get; set; }

    // ── محسوب على الخادم حصراً ──
    public decimal NetSalary { get; set; }
    public decimal NetSalaryIqd { get; set; }

    // ── حالة الدفع ──
    public PayrollPaymentStatus PaymentStatus { get; set; }

    /// <summary>الشركة التي صرفت الراتب فعلاً حين يكون مدفوعاً من الخارج (ADR-024).</summary>
    public int? PaidByCompanyId { get; set; }

    /// <summary>لقطةُ اسم تلك الشركة — فتغيير اسمها لاحقاً لا يغيّر سجلّاً مُسدَّداً.</summary>
    public string? PaidByCompanyName { get; set; }

    /// <summary>
    /// مكافأة نهاية الخدمة — تُضاف في شهر الإنهاء وحده، **بقرار المستخدم لا تلقائياً**.
    /// </summary>
    /// <remarks>بعملة الموظف كسائر المبالغ، وتدخل في الصافي كمكافأة إضافية.</remarks>
    public decimal? EndOfServiceAmount { get; set; }

    // ── حالات تُلوَّن في الكشف ──
    /// <summary>
    /// وقتُ بتّ المستخدم في **تقادم إيصال هذا الموظف** بعد تعديل الشهر (ADR-026).
    /// </summary>
    /// <remarks>
    /// حين يُعدَّل شهرٌ مُسدَّد يصير كلُّ إيصالٍ موقَّعٍ رُفع قبله **مشكوكاً فيه**، فيسأل
    /// النظامُ عن كلٍّ: **«قبول»** ⇒ يُرفع إيصالٌ جديد، أو **«رفض»** ⇒ يُضبط هذا الحقل
    /// بمعنى «تعديل الشهر لا يمسّ هذا الموظف، وإيصاله باقٍ صحيحاً».
    ///
    /// ⚠️ **القرار للإنسان لا للنظام** — نظير «التعليم يدويّ» في ADR-024: النظامُ لا يعرف
    /// أيَّ موظفٍ تأثّر بتعديلٍ ما، والمحاسب يعرف. وحسابُه آلياً كان سيُبطل إيصالات صحيحة
    /// أو يُبقي باطلةً، وكلاهما أسوأ من سؤال.
    ///
    /// إيصالُ الموظف «متقادم» إذا: رُفع قبل <c>Period.LastAmendedAt</c> **و**هذا الحقل
    /// ناقصٌ أو أقدم منه.
    /// </remarks>
    public DateTime? ReceiptAcknowledgedAt { get; set; }

    public bool IsNewHire { get; set; }
    public bool IsTerminated { get; set; }
    public DateTime? TerminationDate { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    public PayrollPeriod? Period { get; set; }
    public EmployeeCompany? EmployeeCompany { get; set; }
}

/// <summary>إعدادات وحدة الموظفين والرواتب — لكل شركة على حدة.</summary>
public class HrSettings
{
    public int SettingsId { get; set; }
    public int CompanyId { get; set; }

    /// <summary>وضع أيام العمل الافتراضي لأي شهر جديد.</summary>
    public WorkingDaysMode DefaultWorkingDaysMode { get; set; }

    public int DefaultWorkingDays { get; set; } = PayrollCalculator.DefaultWorkingDays;

    // ── مكافأة نهاية الخدمة (الدفعة ٢) ──

    /// <summary>مطفأة افتراضياً — الشركة تُفعّلها بقرار.</summary>
    public bool EndOfServiceEnabled { get; set; }

    public EndOfServiceRatio EndOfServiceRatio { get; set; }

    /// <summary>أيام مستحقّة عن كل سنة خدمة حين تكون النسبة <c>CustomDays</c>.</summary>
    public int? EndOfServiceCustomDays { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
