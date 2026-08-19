using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Hr;

// ─────────────────────────── العقود ───────────────────────────

/// <param name="TotalIqd">
/// 🔴 **ما صُرف فعلاً — أشهرٌ مُسدَّدة فقط** (بلاغ المالك 2026-08-06).
/// كان يجمع المسودّات معها، فيقول «صرفنا 25 مليوناً» عن سنةٍ صرفت 21 والباقي أرقامٌ
/// تحت التحرير قد تتغيّر قبل أن تُصرف.
/// </param>
/// <param name="DraftTotalIqd">
/// ما في المسودّات — **رقمٌ منفصل لا مطروح**: المالك يحتاج أن يعرف ما ينتظره كما يحتاج
/// أن يعرف ما صرفه. وإخفاؤه كان سيبدّل عيباً بعيب.
/// </param>
public sealed record PayrollYearSummary(
    int Year, int MonthsCreated, int MonthsPaid, decimal TotalIqd, decimal DraftTotalIqd);

public sealed record PayrollMonthSummary(
    int Year, int Month, bool Exists, PayrollStatus? Status, int EmployeeCount, decimal TotalIqd);

/// <summary>
/// مدخلات سطر واحد عند الحفظ الجماعي. **بلا صافٍ** — الخادم يحسبه ولا يقبله.
/// </summary>
public sealed record SaveEntryInput(
    int EntryId, int AbsenceDays, decimal? BonusAmount, decimal? DeductionAmount,
    decimal? ManualAbsenceDeduction, int? EligibleDaysOverride, string? Notes,
    decimal? EndOfServiceAmount = null);

/// <summary>مكافأة نهاية الخدمة المقترَحة لسطرٍ بعينه (الدفعة ٢).</summary>
public sealed record EndOfServiceSuggestion(
    int EntryId, string EmployeeName, decimal Amount, string Currency,
    decimal YearsServed, int DaysPerYear);

/// <summary>إجازةٌ محسومة تنتظر البتّ في كشف هذا الشهر (ADR-036).</summary>
/// <remarks>
/// ⚠️ <see cref="LeaveYear"/>/<see cref="LeaveMonth"/> هما **شهر هذه الأيام** لا شهر الكشف —
/// والفرق يظهر حين تُرحَّل إجازةُ شهرٍ مُسدَّد إلى الكشف التالي.
/// </remarks>
public sealed record LeaveDeductionHint(
    int LeaveId, int EntryId, string EmployeeName, string LeaveTypeLabel,
    DateTime FromDate, DateTime ToDate,
    int LeaveYear, int LeaveMonth, string LeaveMonthLabel,
    int Days, decimal SuggestedDeduction, Currency Currency, bool IsLate);

public sealed record PeriodSettingsInput(
    decimal? ExchangeRate, WorkingDaysMode WorkingDaysMode, int WorkingDays, string? Notes);

public sealed record PaymentInput(
    DateTime PaidAt, int? OutgoingBookId, string? ManualBookNumber, string? Notes);

/// <summary>حصيلة التوليد — يراها المستخدم فيعرف ماذا تغيّر بالضبط.</summary>
public sealed record GenerateResult(int Added, int Existing, int Skipped);

/// <summary>تنبيه «مدفوع من شركة أخرى» (ADR-024).</summary>
/// <remarks>
/// <paramref name="PaidAt"/> هو **تاريخ صرف الشركة الأخرى** لا تاريخ الاطّلاع — بلاغ المالك
/// 2026-08-05: «يكون هناك إشعار بأن هذا الموظف سبق واستلم راتبه من شركة كذا **بهذا التاريخ**».
/// وقد يكون فارغاً لو سُدِّد الشهر هناك بلا تسجيل تاريخ.
/// </remarks>
public sealed record ExternalPaymentHint(
    int EntryId, string EmployeeName, int PaidByCompanyId, string PaidByCompanyName,
    DateTime? PaidAt);

/// <summary>
/// موظفٌ في الكشف **يعمل في أكثر من شركة** — وحالُ قراره (ADR-028).
/// </summary>
/// <remarks>
/// 🔴 **أوسع من <see cref="ExternalPaymentHint"/> عمداً، وهذا جوهر ADR-028.** ذاك يكشف مَن
/// **صرفت له** شركةٌ أخرى فعلاً، فيبقى بابٌ مفتوح: لو لم تكن الأخرى قد سدّدت بعد فلا تنبيه
/// ولا منع — **فتدفع الشركتان معاً**. وهذا يكشف **كل مزدوج** فيُلزم بالحسم قبل التسديد.
///
/// و<paramref name="OtherPaidAt"/> فارغٌ يعني «الشركة الأخرى لم تسدّد بعد» — وهو فرقٌ
/// يقرّر أيّ القرارَين مسموح: تعليمُ «صُرف من الخارج» لا يجوز بلا صرفٍ حقيقي هناك.
/// </remarks>
public sealed record DualCompanyRow(
    int EntryId, string EmployeeName, int OtherCompanyId, string OtherCompanyName,
    DateTime? OtherPaidAt, PayrollPaymentStatus Decision)
{
    /// <summary>لم يُحسم أمره بعد.</summary>
    public bool NeedsDecision => Decision == PayrollPaymentStatus.Unpaid;

    /// <summary>
    /// حُسم «يُصرف من هنا» **ثم صرفت الشركة الأخرى بعده** — قرارٌ تقادم فيجب إعادة حسمه.
    /// </summary>
    /// <remarks>
    /// ⚠️ **بلا هذا الفحص تبقى ثغرةٌ كاملة:** المحاسب يقرّر الصرف من هنا يوم 1، وتصرف
    /// الشركة الأخرى يوم 3، ويُسدَّد الكشف يوم 5 — فيُصرف الراتب مرّتين **وقد مرّ من
    /// بوّابة الحسم**. القرار يُقاس بأحدث الوقائع لا بوقت اتّخاذه.
    /// </remarks>
    public bool IsStale =>
        Decision == PayrollPaymentStatus.ConfirmedByThisCompany && OtherPaidAt is not null;
}

/// <summary>قيدٌ في سجلّ تعديلات شهرٍ مُسدَّد (ADR-026).</summary>
/// <remarks>
/// ⚠️ **يُعرض ولا يُعدَّل ولا يُحذف** — نظير `EmployeeLog`. سجلٌّ يمكن تنقيحه لا يُحتجّ به.
/// و<see cref="SnapshotJson"/> هو **الشهر كما كان قبل التعديل** لا بعده.
/// </remarks>
public sealed record PayrollAmendment(
    int VersionNo, string Reason, string ChangedBy, DateTime ChangedAt, string SnapshotJson);

public interface IPayrollService
{
    Task<List<PayrollYearSummary>> YearsAsync(CancellationToken ct = default);
    Task<List<PayrollMonthSummary>> MonthsAsync(int year, CancellationToken ct = default);
    Task<PayrollPeriod?> FindPeriodAsync(int year, int month, CancellationToken ct = default);
    // ⚠️ `amendmentReason` غير فارغ ⇒ **تعديلٌ لشهرٍ مُسدَّد** (ADR-026): يتطلّب
    //    `CanAmendPaidPayroll` ويحفظ لقطة إصدار. وفارغاً ⇒ السلوك القديم بلا تغيير.
    Task<GenerateResult> GenerateAsync(int year, int month, string? amendmentReason = null, CancellationToken ct = default);
    Task<PayrollPeriod> UpdateSettingsAsync(int year, int month, PeriodSettingsInput input, byte[] rowVersion, string? amendmentReason = null, CancellationToken ct = default);
    Task<PayrollPeriod> SaveEntriesAsync(int year, int month, List<SaveEntryInput> entries, byte[] rowVersion, string? amendmentReason = null, CancellationToken ct = default);

    /// <summary>سجلّ تعديلات الشهر بعد التسديد — الأحدث أولاً (ADR-026).</summary>
    Task<List<PayrollAmendment>> AmendmentsAsync(int year, int month, CancellationToken ct = default);

    /// <summary>بتٌّ في تقادم إيصال سطرٍ بعد تعديل الشهر — «رفض» أو رفعُ بديل (ADR-026).</summary>
    Task AcknowledgeReceiptAsync(int entryId, CancellationToken ct = default);
    Task PayAsync(int year, int month, PaymentInput input, byte[] rowVersion, CancellationToken ct = default);
    Task DeletePeriodAsync(int year, int month, CancellationToken ct = default);
    Task DeleteYearAsync(int year, CancellationToken ct = default);
    Task<List<ExternalPaymentHint>> DetectExternalPaymentsAsync(int year, int month, CancellationToken ct = default);
    Task<List<DualCompanyRow>> DetectDualCompanyAsync(int year, int month, CancellationToken ct = default);
    Task ConfirmExternalPaymentAsync(int entryId, CancellationToken ct = default);
    Task ConfirmPayHereAsync(int entryId, CancellationToken ct = default);
    Task<List<EndOfServiceSuggestion>> SuggestEndOfServiceAsync(int year, int month, CancellationToken ct = default);

    /// <summary>إجازاتٌ محسومة تنتظر البتّ في كشف هذا الشهر (ADR-036).</summary>
    Task<List<LeaveDeductionHint>> DetectLeaveDeductionsAsync(
        int year, int month, CancellationToken ct = default);

    /// <summary>يطبّق حسم إجازةٍ على سطرها — **أيامٌ تبقى قابلة للتعديل** بعدها.</summary>
    Task ApplyLeaveDeductionAsync(
        int year, int month, int leaveId, int leaveYear, int leaveMonth,
        CancellationToken ct = default);

    /// <summary>يصرف النظر عن حسم إجازةٍ — **بتٌّ صريح لا يمسّ رقماً**.</summary>
    Task WaiveLeaveDeductionAsync(
        int year, int month, int leaveId, int leaveYear, int leaveMonth, string? notes,
        CancellationToken ct = default);
}

/// <summary>
/// كشوف الرواتب (ADR-023). **كل مبلغ محسوب يمرّ من <see cref="PayrollCalculator"/>** — لا مسار
/// يخزّن صافياً جاء من العميل.
/// </summary>
public sealed class PayrollService(
    AppDbContext db, ICurrentUser current, IAuditService audit) : IPayrollService
{
    private const int MaxHistoryYearsAhead = 1;

    // ─────────────────────────── قراءة ───────────────────────────

    /// <summary>السنوات **مشتقّة من الفترات** — لا كيان «سنة» يُخزَّن فارغاً.</summary>
    public async Task<List<PayrollYearSummary>> YearsAsync(CancellationToken ct = default)
    {
        var periods = await db.PayrollPeriods
            .Select(p => new { p.PeriodId, p.Year, p.Status })
            .ToListAsync(ct);
        if (periods.Count == 0) return [];

        // 🔴 قاعدة `PayrollPayable` (ADR-028): ما صرفته شركةٌ أخرى **ليس ممّا دفعناه**.
        //    بلا هذا الشرط كانت إجماليات السنة تنتفخ بمبالغ لم تخرج من خزينة الشركة.
        // 🔴 **والتجميع بحالة الشهر أيضاً (بلاغ المالك 2026-08-06):** المسودّة رقمٌ تحت
        //    التحرير لا مبلغٌ صُرف، وجمعُها مع المُسدَّد يجعل «إجمالي السنة» يعِد بما لم يقع.
        var totals = await db.PayrollEntries
            .Where(PayrollPayable.Predicate)
            .GroupBy(e => new { e.Period!.Year, e.Period.Status })
            .Select(g => new { g.Key.Year, g.Key.Status, Total = g.Sum(x => x.NetSalaryIqd) })
            .ToListAsync(ct);

        return periods
            .GroupBy(p => p.Year)
            .Select(g => new PayrollYearSummary(
                g.Key,
                g.Count(),
                g.Count(p => p.Status == PayrollStatus.Paid),
                totals.Where(t => t.Year == g.Key && t.Status == PayrollStatus.Paid)
                      .Sum(t => t.Total),
                totals.Where(t => t.Year == g.Key && t.Status != PayrollStatus.Paid)
                      .Sum(t => t.Total)))
            .OrderByDescending(y => y.Year)
            .ToList();
    }

    /// <summary>الأشهر الاثنا عشر دائماً — غير المُنشأ يعود بـ<c>Exists = false</c>.</summary>
    public async Task<List<PayrollMonthSummary>> MonthsAsync(int year, CancellationToken ct = default)
    {
        var periods = await db.PayrollPeriods
            .Where(p => p.Year == year)
            .Select(p => new
            {
                p.Month, p.Status,
                Count = p.Entries.Count(e => !e.IsDeleted),
                // 🔴 قاعدة `PayrollPayable` (ADR-028) — الشرط مكتوبٌ هنا حرفياً لأن EF لا
                //    تُدرج شجرة تعبيرٍ داخل لامدا متداخلة. **أي تغيير في القاعدة يمسّ هذا السطر.**
                Total = p.Entries
                    .Where(e => !e.IsDeleted && e.PaymentStatus != PayrollPaymentStatus.PaidByOtherCompany)
                    .Sum(e => (decimal?)e.NetSalaryIqd) ?? 0m,
            })
            .ToListAsync(ct);

        return Enumerable.Range(1, 12).Select(m =>
        {
            var p = periods.FirstOrDefault(x => x.Month == m);
            return p is null
                ? new PayrollMonthSummary(year, m, false, null, 0, 0m)
                : new PayrollMonthSummary(year, m, true, p.Status, p.Count, p.Total);
        }).ToList();
    }

    public async Task<PayrollPeriod?> FindPeriodAsync(int year, int month, CancellationToken ct = default)
    {
        ValidateYearMonth(year, month);
        return await db.PayrollPeriods
            .Include(p => p.Entries.Where(e => !e.IsDeleted))
            .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct);
    }

    // ─────────────────────────── التوليد ───────────────────────────

    /// <summary>
    /// يُنشئ كشف الشهر إن غاب، **ويضيف الموظفين الناقصين فقط**.
    /// </summary>
    /// <remarks>
    /// ⚠️ **تراكميّ لا مُعيدَ بناء**: تشغيلُه ثانيةً بعد تعيين موظف في منتصف الشهر يضيف سطره
    /// **ولا يمسّ سطراً قائماً** — لا مكافأةً ولا خصماً ولا ملاحظةً أدخلها المستخدم بيده.
    /// كان البديل (إعادة التوليد من الصفر) يمحو ساعةَ عملٍ بضغطة زر واحدة بلا إنذار.
    /// </remarks>
    public async Task<GenerateResult> GenerateAsync(
        int year, int month, string? amendmentReason = null, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        ValidateYearMonth(year, month);

        var period = await db.PayrollPeriods
            .Include(p => p.Entries)
            .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct);

        // ⚠️ **إضافة موظفٍ فاته الكشف تعديلٌ كغيره** (ADR-026): بلاغ المالك ذكرها صراحةً
        //    («إضافة موظف جديد ويُحتسب على هذا الشهر»). فتمرّ من الشروط الثلاثة نفسها.
        string? amendReason = null;
        if (period is { Status: PayrollStatus.Paid })
        {
            (_, amendReason) = await OpenForWriteAsync(year, month, amendmentReason, ct);
            await SnapshotAsync(period, amendReason!, ct);
        }

        if (period is null)
        {
            var settings = await db.HrSettings.FirstOrDefaultAsync(s => s.CompanyId == companyId, ct);
            var mode = settings?.DefaultWorkingDaysMode ?? WorkingDaysMode.Fixed;
            var fixedDays = settings?.DefaultWorkingDays ?? PayrollCalculator.DefaultWorkingDays;

            period = new PayrollPeriod
            {
                CompanyId = companyId,
                Year = year,
                Month = month,
                WorkingDaysMode = mode,
                WorkingDays = PayrollCalculator.ResolveWorkingDays(mode, fixedDays, year, month),
                ExchangeRate = await LatestUsdRateAsync(ct),
                Status = PayrollStatus.Draft,
                CreatedByUserId = current.UserId ?? 0,
                CreatedAt = DateTime.UtcNow,
            };
            db.PayrollPeriods.Add(period);
        }

        var monthEnd = new DateTime(year, month, DateTime.DaysInMonth(year, month));
        var monthStart = new DateTime(year, month, 1);

        // مرشّحون: كل من كان على رأس عمله **أثناء** هذا الشهر — لا من عُيِّن بعده أو انتهت قبله.
        var candidates = await db.EmployeeCompanies
            .Include(x => x.Employee)
            .Where(x => x.HireDate <= monthEnd
                     && (x.TerminationDate == null || x.TerminationDate >= monthStart)
                     && (x.IsActive || x.TerminationDate != null))
            .OrderBy(x => x.DisplayOrder).ThenBy(x => x.Employee!.FullName)
            .ToListAsync(ct);

        var existingIds = period.Entries.Where(e => !e.IsDeleted)
            .Select(e => e.EmployeeCompanyId).ToHashSet();

        // ── تذكُّر قرار الشهر السابق للموظف المزدوج (G14) ──
        //
        // 🔴 **بوّابة الحسم (ADR-028) تطلب قراراً في كل شهر**، وهي كلفةٌ مقبولة عند موظفَين
        //    وعبءٌ عند عشرين. فنحمل قرار الشهر الماضي **في اتجاهٍ واحد فقط**:
        //
        //    ✅ «يُصرف من هنا» يُحمَل  — أسوأ ما يقع أن ندفع، وهو الافتراض أصلاً.
        //    ❌ «صُرف من شركة أخرى» **لا يُحمَل أبداً** — فكونُها صرفت في آذار لا يعني أنها
        //       ستصرف في نيسان، وحملُه يستثني راتباً بناءً على واقعةٍ قديمة **فلا يقبض
        //       الموظف من أحد**. سكوتٌ يُنتج جوعاً أسوأ من سؤالٍ يُنتج ضغطة.
        //
        // ⚠️ **وحارس التقادم يبقى نافذاً**: لو صرفت الشركة الأخرى هذا الشهر بعد القرار
        //    المحمول، يمنع `EnsureDualCompanyResolvedAsync` التسديدَ ويطلب إعادة الحسم.
        var candidateEmpIds = candidates.Select(c => c.EmployeeId).Distinct().ToList();
        var dualEmployeeIds = (await db.EmployeeCompanies.IgnoreQueryFilters()
            .Where(x => candidateEmpIds.Contains(x.EmployeeId)
                     && x.CompanyId != companyId && !x.IsDeleted)
            .Select(x => x.EmployeeId).Distinct().ToListAsync(ct)).ToHashSet();

        // قرارات الشهر السابق — بمفتاح الإسناد لا الموظف (فالشخص قد يُسنَد مرّتين).
        var prev = month == 1 ? (year - 1, 12) : (year, month - 1);
        var previousDecisions = dualEmployeeIds.Count == 0
            ? []
            : await db.PayrollEntries
                .Where(e => !e.IsDeleted && e.Period!.Year == prev.Item1 && e.Period.Month == prev.Item2)
                .Select(e => new { e.EmployeeCompanyId, e.PaymentStatus })
                .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x.PaymentStatus, ct);

        int added = 0, skipped = 0;
        foreach (var link in candidates)
        {
            if (existingIds.Contains(link.EmployeeCompanyId)) continue;

            var amounts = PayrollCalculator.Compute(
                year, month, period.WorkingDays,
                link.BaseSalary, link.SalaryCurrency, period.ExchangeRate,
                link.HireDate, link.TerminationDate,
                absenceDays: 0, bonus: null, deduction: null, manualAbsenceDeduction: null);

            // لا يستحقّ شيئاً في هذا الشهر ⇒ لا نُثقل الكشف بسطر فارغ.
            if (amounts.EligibleDays == 0) { skipped++; continue; }

            period.Entries.Add(new PayrollEntry
            {
                CompanyId = companyId,
                EmployeeCompanyId = link.EmployeeCompanyId,
                DisplayOrder = link.DisplayOrder,
                SnapshotName = link.Employee?.FullName ?? "—",
                SnapshotPosition = link.Position,
                SnapshotCurrency = link.SalaryCurrency,
                SnapshotBaseSalary = link.BaseSalary,
                EligibleDays = amounts.EligibleDays,
                AbsenceDays = 0,
                AbsenceDeduction = amounts.AbsenceDeduction,
                NetSalary = amounts.NetSalary,
                NetSalaryIqd = amounts.NetSalaryIqd,
                PaymentStatus = CarriedDecision(link, dualEmployeeIds, previousDecisions),
                IsNewHire = link.HireDate >= monthStart && link.HireDate <= monthEnd,
                IsTerminated = link.TerminationDate is { } t && t >= monthStart && t <= monthEnd,
                TerminationDate = link.TerminationDate,
                CreatedAt = DateTime.UtcNow,
            });
            added++;
        }

        period.UpdatedAt = DateTime.UtcNow;
        audit.Add("GeneratePayroll", nameof(PayrollPeriod), $"{year}-{month:D2}",
            $"أُضيف {added} · موجود {existingIds.Count} · متخطّى {skipped}", companyId);
        await db.SaveChangesAsync(ct);

        return new GenerateResult(added, existingIds.Count, skipped);
    }

    // ─────────────────────────── التعديل ───────────────────────────

    public async Task<PayrollPeriod> UpdateSettingsAsync(
        int year, int month, PeriodSettingsInput input, byte[] rowVersion,
        string? amendmentReason = null, CancellationToken ct = default)
    {
        RequireWrite();
        var (period, amendReason) = await OpenForWriteAsync(year, month, amendmentReason, ct);
        Guard(period, rowVersion);
        if (amendReason is not null) await SnapshotAsync(period, amendReason, ct);

        if (input.WorkingDays is < 1 or > 31)
            throw new ValidationException("أيام العمل يجب أن تكون بين 1 و31.");
        if (input.ExchangeRate is <= 0)
            throw new ValidationException("سعر الصرف يجب أن يكون موجباً.");

        period.WorkingDaysMode = input.WorkingDaysMode;
        period.WorkingDays = input.WorkingDaysMode == WorkingDaysMode.Calendar
            ? DateTime.DaysInMonth(year, month)
            : input.WorkingDays;
        period.ExchangeRate = input.ExchangeRate;
        period.Notes = string.IsNullOrWhiteSpace(input.Notes) ? null : input.Notes.Trim();
        period.UpdatedAt = DateTime.UtcNow;

        // أيام العمل وسعر الصرف يدخلان في كل سطر ⇒ يُعاد حساب الكشف كله.
        RecomputeAll(period);

        audit.Add("UpdatePayrollSettings", nameof(PayrollPeriod), $"{year}-{month:D2}", null, period.CompanyId);
        await SaveGuardedAsync(ct);
        return period;
    }

    /// <summary>حفظ الكشف دفعةً واحدة — والصافي يُعاد حسابه هنا مهما أرسل العميل.</summary>
    public async Task<PayrollPeriod> SaveEntriesAsync(
        int year, int month, List<SaveEntryInput> entries, byte[] rowVersion,
        string? amendmentReason = null, CancellationToken ct = default)
    {
        RequireWrite();
        var (period, amendReason) = await OpenForWriteAsync(year, month, amendmentReason, ct);
        Guard(period, rowVersion);
        if (amendReason is not null) await SnapshotAsync(period, amendReason, ct);

        var byId = period.Entries.Where(e => !e.IsDeleted).ToDictionary(e => e.EntryId);

        foreach (var input in entries)
        {
            if (!byId.TryGetValue(input.EntryId, out var entry))
                throw new NotFoundException($"سطر غير موجود في هذا الكشف (#{input.EntryId}).");

            if (input.AbsenceDays < 0) throw new ValidationException("أيام الغياب لا تكون سالبة.");
            if (input.BonusAmount is < 0) throw new ValidationException("المكافأة لا تكون سالبة.");
            if (input.DeductionAmount is < 0) throw new ValidationException("الخصم لا يكون سالباً.");

            entry.AbsenceDays = input.AbsenceDays;
            entry.BonusAmount = input.BonusAmount;
            entry.DeductionAmount = input.DeductionAmount;
            entry.AbsenceDeductionIsManual = input.ManualAbsenceDeduction is not null;
            entry.Notes = string.IsNullOrWhiteSpace(input.Notes) ? null : input.Notes.Trim();

            if (input.EndOfServiceAmount is { } eos)
            {
                if (eos < 0) throw new ValidationException("مكافأة نهاية الخدمة لا تكون سالبة.");
                // تُقبل على سطر المنتهية خدمته وحده — وإلا صارت باباً لمكافأة بلا سبب.
                if (!entry.IsTerminated)
                    throw new ValidationException(
                        $"«{entry.SnapshotName}» لم تنتهِ خدمته هذا الشهر — لا تُضاف له مكافأة نهاية خدمة.");
                entry.EndOfServiceAmount = eos == 0 ? null : eos;
            }

            if (input.EligibleDaysOverride is { } days)
            {
                if (days < 0 || days > period.WorkingDays)
                    throw new ValidationException($"الأيام المستحقّة يجب أن تكون بين 0 و{period.WorkingDays}.");
                entry.EligibleDays = days;
                entry.EligibleDaysIsManual = true;
            }

            Recompute(period, entry, input.ManualAbsenceDeduction);
            entry.UpdatedAt = DateTime.UtcNow;
        }

        period.UpdatedAt = DateTime.UtcNow;
        audit.Add("SavePayroll", nameof(PayrollPeriod), $"{year}-{month:D2}",
            $"حفظ {entries.Count} سطراً", period.CompanyId);
        await SaveGuardedAsync(ct);
        return period;
    }

    // ─────────────────────────── التسديد ───────────────────────────

    public async Task PayAsync(
        int year, int month, PaymentInput input, byte[] rowVersion, CancellationToken ct = default)
    {
        RequireWrite();
        var period = await RequireDraftAsync(year, month, ct);
        Guard(period, rowVersion);

        var live = period.Entries.Where(e => !e.IsDeleted).ToList();
        if (live.Count == 0)
            throw new ValidationException("الكشف فارغ — ولّد الموظفين قبل التسديد.");

        // ما يُتساهَل معه في المسودّة يُرفض هنا: التسديد لا رجعة فيه.
        // ⚠️ والحارسان على **ما يُدفع فعلاً**: صافي مَن صرفته شركةٌ أخرى لا يعنينا، وسعرُ
        //    الصرف لا يلزم من أجل سطرٍ لن نصرفه.
        var payable = PayrollPayable.Payable(live).ToList();
        PayrollCalculator.EnsureRateSet(
            payable.Any(e => e.SnapshotCurrency == Currency.USD), period.ExchangeRate);
        foreach (var e in payable) PayrollCalculator.EnsurePayable(e.SnapshotName, e.NetSalary);

        // 🔴 **بوّابة الحسم (ADR-028):** لا يُسدَّد كشفٌ فيه موظفٌ يعمل في أكثر من شركة ولم
        //    يُحسم أمره. كان التسديد يمرّ بلا سؤال، فصُرف راتبٌ صرفته شركةٌ أخرى.
        // ⚠️ **بعد حارسَي الحساب لا قبلهما**: كشفٌ ناقصُ سعر الصرف غيرُ قابلٍ للحساب أصلاً،
        //    فسؤالُ المحاسب عن قرارٍ في أرقامٍ لم تُحسب بعد يقلب ترتيب العلاج. (كشفه أول
        //    تشغيل: صار «التسديد بلا سعر صرف» يردّ 409 بدل 400.)
        await EnsureDualCompanyResolvedAsync(period, ct);

        if (input.OutgoingBookId is { } bookId)
        {
            var exists = await db.OutgoingBooks.AnyAsync(b => b.OutgoingId == bookId, ct);
            if (!exists) throw new NotFoundException("كتاب الصرف المحدّد غير موجود.");
        }

        period.Status = PayrollStatus.Paid;
        period.PaidAt = input.PaidAt;
        period.PaidByUserId = current.UserId;
        period.OutgoingBookId = input.OutgoingBookId;
        period.ManualBookNumber = string.IsNullOrWhiteSpace(input.ManualBookNumber)
            ? null : input.ManualBookNumber.Trim();
        if (!string.IsNullOrWhiteSpace(input.Notes)) period.Notes = input.Notes.Trim();
        period.UpdatedAt = DateTime.UtcNow;

        // مَن كان «لم يُصرف» أو **حُسم أن يُصرف من هنا** يصير مصروفاً من هذه الشركة؛
        // ومَن عُلِّم مدفوعاً من الخارج يبقى على حاله.
        foreach (var e in live.Where(x => PayrollPayable.Includes(x.PaymentStatus)
                                       && x.PaymentStatus != PayrollPaymentStatus.PaidByThisCompany))
            e.PaymentStatus = PayrollPaymentStatus.PaidByThisCompany;

        // ⚠️ **سجلّ التدقيق يقول ما خرج فعلاً** — كان يسجّل الإجمالي الخام، فيوثّق مبلغاً
        //    أكبر من المصروف ويصير الشاهدُ نفسه مضلِّلاً.
        var excluded = PayrollPayable.ExcludedIqd(live);
        var detail = $"تسديد {payable.Count} راتباً بإجمالي {PayrollPayable.TotalIqd(live):#,0.##} د.ع"
                   + (excluded > 0
                       ? $" (استُثني {live.Count - payable.Count} مدفوعاً من شركة أخرى بقيمة {excluded:#,0.##} د.ع)"
                       : string.Empty);
        audit.Add("PayPayroll", nameof(PayrollPeriod), $"{year}-{month:D2}", detail, period.CompanyId);
        await SaveGuardedAsync(ct);
    }

    // ─────────────────────────── الحذف (ناعم) ───────────────────────────

    public async Task DeletePeriodAsync(int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        var period = await RequireDraftAsync(year, month, ct);
        SoftDelete(period);
        audit.Add("Delete", nameof(PayrollPeriod), $"{year}-{month:D2}", null, period.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteYearAsync(int year, CancellationToken ct = default)
    {
        RequireWrite();
        var periods = await db.PayrollPeriods.Include(p => p.Entries)
            .Where(p => p.Year == year).ToListAsync(ct);
        if (periods.Count == 0) throw new NotFoundException("لا توجد كشوف لهذه السنة.");

        if (periods.Any(p => p.Status == PayrollStatus.Paid))
            throw new ConflictException("السنة تحتوي أشهراً مُسدَّدة — لا يمكن حذفها.");

        foreach (var p in periods) SoftDelete(p);
        audit.Add("Delete", nameof(PayrollPeriod), year.ToString(),
            $"حذف {periods.Count} كشفاً لسنة {year}", current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);
    }

    // ─────────────────────────── «مدفوع من شركة أخرى» (ADR-024) ───────────────────────────

    /// <summary>
    /// يكشف مَن صُرف راتبه من شركة أخرى في الشهر نفسه.
    /// </summary>
    /// <remarks>
    /// ⚠️ **تجاوزٌ متعمَّد للعزل بين الشركات (ADR-024)، بموافقة المالك الصريحة (2026-08-03).**
    /// مستخدم «بوغوصيان» سيعلم أن «أرض العرين» صرفت الراتب، **باسمها**. مقبولٌ لأن الشركتين
    /// لمالك واحد، ولأن البديل — صرفُ الراتب مرتين بالخطأ — أسوأ وأصعب تصحيحاً.
    ///
    /// وثلاثة قيود تحدّه: **قراءة خالصة** (لا يكتب شيئاً في الشركة الأخرى)، و**لمن يملك
    /// <c>CanManageHR</c> هنا وحده**، و**التعليم يدوي** بضغطة المستخدم لا بمزامنة تلقائية.
    /// </remarks>
    public async Task<List<ExternalPaymentHint>> DetectExternalPaymentsAsync(
        int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();

        var period = await FindPeriodAsync(year, month, ct);
        if (period is null) return [];

        // ⚠️ **تشمل «حُسم أن يُصرف من هنا» لا `Unpaid` وحدها (ADR-028):** لولا ذلك لَعجز
        //    المحاسب عن التراجع حين تصرف الشركة الأخرى **بعد** قراره — فيبقى الكشف عالقاً
        //    عند حارس التقادم بلا مخرج.
        var mine = period.Entries
            .Where(e => !e.IsDeleted
                     && e.PaymentStatus is PayrollPaymentStatus.Unpaid
                                        or PayrollPaymentStatus.ConfirmedByThisCompany)
            .ToList();
        if (mine.Count == 0) return [];

        var linkIds = mine.Select(e => e.EmployeeCompanyId).ToList();
        var employeeByLink = await db.EmployeeCompanies.IgnoreQueryFilters()
            .Where(x => linkIds.Contains(x.EmployeeCompanyId))
            .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x.EmployeeId, ct);
        var employeeIds = employeeByLink.Values.Distinct().ToList();

        // الشركات الأخرى التي صرفت لهؤلاء في هذا الشهر — **وتاريخ صرفها** (بلاغ المالك).
        var elsewhere = await db.PayrollEntries.IgnoreQueryFilters()
            .Where(e => !e.IsDeleted
                     && e.CompanyId != companyId
                     && e.Period!.Year == year && e.Period.Month == month
                     && e.Period.Status == PayrollStatus.Paid
                     && employeeIds.Contains(e.EmployeeCompany!.EmployeeId))
            .Select(e => new { e.CompanyId, EmployeeId = e.EmployeeCompany!.EmployeeId, e.Period!.PaidAt })
            .ToListAsync(ct);
        if (elsewhere.Count == 0) return [];

        var payerIds = elsewhere.Select(x => x.CompanyId).Distinct().ToList();
        var payerNames = await db.Companies.IgnoreQueryFilters()
            .Where(c => payerIds.Contains(c.CompanyId))
            .ToDictionaryAsync(c => c.CompanyId, c => c.Name, ct);

        var hints = new List<ExternalPaymentHint>();
        foreach (var entry in mine)
        {
            if (!employeeByLink.TryGetValue(entry.EmployeeCompanyId, out var empId)) continue;
            var payer = elsewhere.FirstOrDefault(x => x.EmployeeId == empId);
            if (payer is null) continue;

            hints.Add(new ExternalPaymentHint(
                entry.EntryId, entry.SnapshotName, payer.CompanyId,
                payerNames.TryGetValue(payer.CompanyId, out var n) ? n : "شركة أخرى",
                payer.PaidAt));
        }
        return hints;
    }

    /// <summary>
    /// كل موظفي الكشف **الذين يعملون في أكثر من شركة** — مع قرار كلٍّ وحال الشركة الأخرى.
    /// </summary>
    /// <remarks>
    /// ⚠️ **خامس موضع <c>IgnoreQueryFilters</c> متعمَّد في الوحدة** (ADR-024 · ADR-027 ·
    /// وثلاثةٌ في `EmployeeService`): السؤال بطبيعته عابرٌ للشركات — «أين يعمل هذا الشخص
    /// أيضاً؟» — والفلترُ العام يحجب الجواب. وقراءةٌ خالصة: لا يكتب حرفاً في أي شركة.
    ///
    /// والمكشوف **اسم الشركة وتاريخ صرفها فقط** — لا راتبه هناك (حدّ ADR-027 نفسه).
    /// </remarks>
    public async Task<List<DualCompanyRow>> DetectDualCompanyAsync(
        int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();

        var period = await FindPeriodAsync(year, month, ct);
        if (period is null) return [];

        var live = period.Entries.Where(e => !e.IsDeleted).ToList();
        if (live.Count == 0) return [];

        // معرّف الموظف خلف كل سطر.
        var linkIds = live.Select(e => e.EmployeeCompanyId).ToList();
        var employeeByLink = await db.EmployeeCompanies.IgnoreQueryFilters()
            .Where(x => linkIds.Contains(x.EmployeeCompanyId))
            .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x.EmployeeId, ct);
        var employeeIds = employeeByLink.Values.Distinct().ToList();

        // إسناداتُهم **خارج** هذه الشركة (حيّةً غير محذوفة).
        var otherLinks = await db.EmployeeCompanies.IgnoreQueryFilters()
            .Where(x => employeeIds.Contains(x.EmployeeId) && x.CompanyId != companyId && !x.IsDeleted)
            .Select(x => new { x.EmployeeId, x.CompanyId })
            .ToListAsync(ct);
        if (otherLinks.Count == 0) return [];

        var otherCompanyIds = otherLinks.Select(x => x.CompanyId).Distinct().ToList();
        var names = await db.Companies.IgnoreQueryFilters()
            .Where(c => otherCompanyIds.Contains(c.CompanyId))
            .ToDictionaryAsync(c => c.CompanyId, c => c.Name, ct);

        // ومَن **صرفت له** إحداها هذا الشهر فعلاً (بتاريخ صرفها).
        var paidElsewhere = await db.PayrollEntries.IgnoreQueryFilters()
            .Where(e => !e.IsDeleted
                     && e.CompanyId != companyId
                     && e.Period!.Year == year && e.Period.Month == month
                     && e.Period.Status == PayrollStatus.Paid
                     && employeeIds.Contains(e.EmployeeCompany!.EmployeeId))
            .Select(e => new { e.CompanyId, EmployeeId = e.EmployeeCompany!.EmployeeId, e.Period!.PaidAt })
            .ToListAsync(ct);

        var rows = new List<DualCompanyRow>();
        foreach (var entry in live)
        {
            if (!employeeByLink.TryGetValue(entry.EmployeeCompanyId, out var empId)) continue;

            // الشركة الأخرى التي **صرفت** أولى بالعرض من مجرّد شركةٍ يعمل فيها.
            var payer = paidElsewhere.FirstOrDefault(x => x.EmployeeId == empId);
            var otherId = payer?.CompanyId
                          ?? otherLinks.FirstOrDefault(x => x.EmployeeId == empId)?.CompanyId;
            if (otherId is not { } oid) continue;

            rows.Add(new DualCompanyRow(
                entry.EntryId, entry.SnapshotName, oid,
                names.TryGetValue(oid, out var n) ? n : "شركة أخرى",
                payer?.PaidAt, entry.PaymentStatus));
        }
        return rows;
    }

    /// <summary>
    /// بوّابة الحسم قبل التسديد (ADR-028) — تمنع ما بُنيت ADR-024 لمنعه وعجزت عنه.
    /// </summary>
    /// <remarks>
    /// ترفض حالتين: **لم يُحسم** أصلاً، و**حُسم ثم تغيّرت الحال** (صرفت الأخرى بعد القرار).
    /// والرسالة تحمل **الأسماء** لا عدداً — «موظفان لم يُحسم أمرهما» يترك المحاسب يبحث.
    /// </remarks>
    private async Task EnsureDualCompanyResolvedAsync(PayrollPeriod period, CancellationToken ct)
    {
        var rows = await DetectDualCompanyAsync(period.Year, period.Month, ct);

        var pending = rows.Where(r => r.NeedsDecision).Select(r => r.EmployeeName).ToList();
        if (pending.Count > 0)
            throw new ConflictException(
                $"لم يُحسم أمر مَن يعمل في أكثر من شركة: {string.Join(" · ", pending)}. "
                + "حدّد لكلٍّ منهم «يُصرف من هنا» أو «صُرف من شركة أخرى» قبل التسديد.");

        var stale = rows.Where(r => r.IsStale)
            .Select(r => $"{r.EmployeeName} (صرفت له {r.OtherCompanyName})").ToList();
        if (stale.Count > 0)
            throw new ConflictException(
                $"تغيّرت الحال بعد قرارك: {string.Join(" · ", stale)}. "
                + "أعِد حسم أمرهم قبل التسديد لئلا يُصرف الراتب مرّتين.");
    }

    /// <summary>
    /// قرارٌ صريح: **يُصرف من هذه الشركة** رغم عمله في شركةٍ أخرى (ADR-028).
    /// </summary>
    /// <remarks>
    /// مسموحٌ دائماً لمن يعمل في أكثر من شركة — بخلاف نظيره «صُرف من الخارج» الذي يشترط
    /// صرفاً حقيقياً هناك. والسبب: أن تقول «سأدفع أنا» لا يحتاج إذناً من أحد، وأن تقول
    /// «دفع غيري» **ادّعاءٌ على واقعة** يجب أن تكون قد حدثت.
    /// </remarks>
    public async Task ConfirmPayHereAsync(int entryId, CancellationToken ct = default)
    {
        RequireWrite();

        var entry = await db.PayrollEntries.Include(e => e.Period)
                        .FirstOrDefaultAsync(e => e.EntryId == entryId, ct)
                    ?? throw new NotFoundException("السطر غير موجود.");

        if (entry.Period!.Status == PayrollStatus.Paid)
            throw new ConflictException("الكشف مُسدَّد — لا يمكن تعديل حالة الدفع.");

        var rows = await DetectDualCompanyAsync(entry.Period.Year, entry.Period.Month, ct);
        if (rows.All(r => r.EntryId != entryId))
            throw new ValidationException("هذا الموظف لا يعمل في شركةٍ أخرى — لا قرار مطلوب.");

        entry.PaymentStatus = PayrollPaymentStatus.ConfirmedByThisCompany;

        // ⚠️ **تُمحى لقطةُ الدافع الخارجي** إن كان السطر معلَّماً سابقاً: بقاؤها يجعل الكشف
        //    يقول «مدفوع من فلانة» عن راتبٍ ندفعه نحن.
        entry.PaidByCompanyId = null;
        entry.PaidByCompanyName = null;
        entry.UpdatedAt = DateTime.UtcNow;

        audit.Add("ConfirmPayHere", nameof(PayrollEntry), entryId.ToString(),
            $"{entry.SnapshotName} — يُصرف من هذه الشركة", entry.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>يُعلّم السطر «مدفوع من الخارج» — **بقرار المستخدم لا تلقائياً**.</summary>
    public async Task ConfirmExternalPaymentAsync(int entryId, CancellationToken ct = default)
    {
        RequireWrite();

        var entry = await db.PayrollEntries.Include(e => e.Period)
                        .FirstOrDefaultAsync(e => e.EntryId == entryId, ct)
                    ?? throw new NotFoundException("السطر غير موجود.");

        if (entry.Period!.Status == PayrollStatus.Paid)
            throw new ConflictException("الكشف مُسدَّد — لا يمكن تعديل حالة الدفع.");

        var hints = await DetectExternalPaymentsAsync(entry.Period.Year, entry.Period.Month, ct);
        var hint = hints.FirstOrDefault(h => h.EntryId == entryId)
                   ?? throw new ValidationException("لا يوجد صرفٌ من شركة أخرى لهذا الموظف في هذا الشهر.");

        entry.PaymentStatus = PayrollPaymentStatus.PaidByOtherCompany;
        entry.PaidByCompanyId = hint.PaidByCompanyId;
        entry.PaidByCompanyName = hint.PaidByCompanyName; // لقطة: تغيّر اسم الشركة لاحقاً لا يغيّر السجل
        entry.Notes = AppendExternalNote(entry.Notes, hint);
        entry.UpdatedAt = DateTime.UtcNow;

        audit.Add("ConfirmExternalPayment", nameof(PayrollEntry), entryId.ToString(),
            $"{entry.SnapshotName} — مدفوع من {hint.PaidByCompanyName}", entry.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>الصدر الثابت لملاحظة الدفع الخارجي — به يُكشف وجودها فلا تتكرّر.</summary>
    private const string ExternalNotePrefix = "مدفوع من ";

    /// <summary>
    /// يُلحق بملاحظات السطر جملةً عربية تذكر الشركة الدافعة **وتاريخ صرفها**.
    /// </summary>
    /// <remarks>
    /// ⚠️ **إلحاقٌ لا استبدال:** الملاحظة حقلٌ يكتب فيه المحاسب، فمحوُه لإدراج جملة النظام
    /// يُضيع كلامه. و⚠️ **محميّة من التكرار**: إعادة التأكيد على السطر نفسه لا تُضيف سطراً
    /// ثانياً (يُكشف بالصدر الثابت).
    ///
    /// ولماذا في الملاحظات أصلاً وحالة الدفع عمودٌ قائم؟ لأن **العمود لا يظهر في الكشف
    /// المطبوع ولا في Excel** — وهما موضع نظر المحاسب. (بلاغ المالك 2026-08-05: «ويكون هذا
    /// مذكور في الملاحظات».)
    /// </remarks>
    private static string AppendExternalNote(string? existing, ExternalPaymentHint hint)
    {
        var date = hint.PaidAt is { } d ? $" بتاريخ {d:yyyy-MM-dd}" : string.Empty;
        var note = $"{ExternalNotePrefix}{hint.PaidByCompanyName}{date}";

        if (string.IsNullOrWhiteSpace(existing)) return note;
        if (existing.Contains(ExternalNotePrefix, StringComparison.Ordinal)) return existing;
        return $"{existing.TrimEnd()} — {note}";
    }

    // ─────────────────────── مكافأة نهاية الخدمة (الدفعة ٢) ───────────────────────

    /// <summary>
    /// يقترح مكافأة نهاية خدمة لمن انتهت خدمته في هذا الشهر — **اقتراحٌ لا تطبيق**.
    /// </summary>
    /// <remarks>
    /// لا تُضاف تلقائياً بحال: المكافأة التزامٌ ماليّ يقرّره صاحب العمل بعد مراجعة الخدمة
    /// والذمّة، وحسابُها آلياً وإدراجُها في الصافي كان سيصرف مبلغاً لم يوافق عليه أحد.
    /// </remarks>
    // ─────────────── حسم الإجازات من الكشف (ADR-036) ───────────────

    /// <remarks>
    /// 🔴 **سبب وجود هذا المسار:** الإجازة المقبولة بعلَم «تُحسم من الراتب» كانت **لا تمسّ
    /// رقماً ولا تُصدر تنبيهاً** — التوليد يكتب <c>AbsenceDays = 0</c> ولا يقرأ الإجازات
    /// أصلاً. وهي عائلة عطل ADR-028 نفسها: **علَمٌ يلوّن سطراً ولا يمسّ مالاً**.
    ///
    /// ⚠️ **تنبيهٌ لا حسمٌ تلقائيّ** (قرار المالك): يُعرض المقترَح ويُطبَّق **بضغطة**، لأن
    /// المراجع قد يتراجع. ونظيرُه القائم <see cref="SuggestEndOfServiceAsync"/>.
    /// </remarks>
    public async Task<List<LeaveDeductionHint>> DetectLeaveDeductionsAsync(
        int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        ValidateYearMonth(year, month);

        var period = await FindPeriodAsync(year, month, ct);
        if (period is null) return [];

        var live = period.Entries.Where(e => !e.IsDeleted).ToList();
        if (live.Count == 0) return [];

        var linkIds = live.Select(e => e.EmployeeCompanyId).ToList();
        var sheetEnd = new DateTime(year, month, 1).AddMonths(1).AddDays(-1);

        // الإجازات المرشَّحة: مقبولةٌ · تُحسم · بدأت قبل نهاية هذا الشهر (لا مستقبلية).
        var leaves = await db.EmployeeLeaves
            .Where(l => linkIds.Contains(l.EmployeeCompanyId)
                     && l.Status == LeaveStatus.Approved
                     && l.DeductFromSalary
                     && l.FromDate <= sheetEnd)
            .ToListAsync(ct);
        if (leaves.Count == 0) return [];

        var leaveIds = leaves.Select(l => l.LeaveId).ToList();
        var settled = await db.EmployeeLeaveSettlements
            .Where(x => leaveIds.Contains(x.LeaveId))
            .Select(x => new { x.LeaveId, x.LeaveYear, x.LeaveMonth })
            .ToListAsync(ct);

        // حالة كشوف الأشهر — لقاعدة الترحيل: تُعالَج في شهرها ما دام مفتوحاً.
        var paidMonths = await db.PayrollPeriods
            .Where(p => p.Status == PayrollStatus.Paid)
            .Select(p => new { p.Year, p.Month })
            .ToListAsync(ct);

        var entryByLink = live.ToDictionary(e => e.EmployeeCompanyId);

        var hints = new List<LeaveDeductionHint>();
        foreach (var leave in leaves)
        {
            if (!entryByLink.TryGetValue(leave.EmployeeCompanyId, out var entry)) continue;

            // كل شهرٍ تمسّه الإجازة — التقسيم بالأيام (قرار المالك).
            var cursor = new DateTime(leave.FromDate.Year, leave.FromDate.Month, 1);
            var last = new DateTime(leave.ToDate.Year, leave.ToDate.Month, 1);
            for (; cursor <= last; cursor = cursor.AddMonths(1))
            {
                int ly = cursor.Year, lm = cursor.Month;

                var days = LeaveDeduction.DaysInMonth(leave.FromDate, leave.ToDate, ly, lm);
                if (days <= 0) continue;

                if (settled.Any(x => x.LeaveId == leave.LeaveId
                                  && x.LeaveYear == ly && x.LeaveMonth == lm)) continue;

                var isPaid = paidMonths.Any(p => p.Year == ly && p.Month == lm);
                if (!LeaveDeduction.ShowsInSheet(ly, lm, year, month, isPaid)) continue;

                hints.Add(new LeaveDeductionHint(
                    leave.LeaveId, entry.EntryId, entry.SnapshotName,
                    leave.LeaveType.ArabicLabel(), leave.FromDate, leave.ToDate,
                    ly, lm, $"{PayrollCalculator.ArabicMonth(lm)} {ly}",
                    days,
                    PayrollCalculator.SuggestAbsenceDeduction(
                        entry.SnapshotBaseSalary, days, period.WorkingDays),
                    entry.SnapshotCurrency,
                    IsLate: !(ly == year && lm == month)));
            }
        }

        return hints
            .OrderByDescending(h => h.IsLate)
            .ThenBy(h => h.EmployeeName)
            .ToList();
    }

    public Task ApplyLeaveDeductionAsync(
        int year, int month, int leaveId, int leaveYear, int leaveMonth,
        CancellationToken ct = default)
        => SettleLeaveDeductionAsync(year, month, leaveId, leaveYear, leaveMonth, true, null, ct);

    public Task WaiveLeaveDeductionAsync(
        int year, int month, int leaveId, int leaveYear, int leaveMonth, string? notes,
        CancellationToken ct = default)
        => SettleLeaveDeductionAsync(year, month, leaveId, leaveYear, leaveMonth, false, notes, ct);

    /// <remarks>
    /// 🔴 **الأيام تُعاد حسابها هنا ولا تُقبل من العميل** — نظير قاعدة الوحدة كلّها: «كل مبلغ
    /// محسوب يمرّ من <see cref="PayrollCalculator"/>». عميلٌ يرسل ٣٠ يوماً بدل يومين يُنتج
    /// راتباً صفرياً بلا أن يخطئ أحد.
    ///
    /// ⚠️ **والتطبيق على المسودّة وحدها**: تعديل شهرٍ مُسدَّد له مسارُه الخاص بلقطةٍ وسبب
    /// (ADR-026)، ولا يُلتفّ عليه من هنا. ولذلك تُرحَّل إجازةُ الشهر المُقفل إلى الكشف
    /// المفتوح بدل أن تُطبَّق على المُقفل.
    /// </remarks>
    private async Task SettleLeaveDeductionAsync(
        int year, int month, int leaveId, int leaveYear, int leaveMonth,
        bool applied, string? notes, CancellationToken ct)
    {
        RequireWrite();
        var period = await RequireDraftAsync(year, month, ct);

        var leave = await db.EmployeeLeaves.Include(l => l.EmployeeCompany)
                        .FirstOrDefaultAsync(l => l.LeaveId == leaveId, ct)
                    ?? throw new NotFoundException("الإجازة غير موجودة.");

        if (leave.Status != LeaveStatus.Approved || !leave.DeductFromSalary)
            throw new ValidationException("هذه الإجازة ليست مقبولةً بحسمٍ من الراتب.");

        var days = LeaveDeduction.DaysInMonth(leave.FromDate, leave.ToDate, leaveYear, leaveMonth);
        if (days <= 0)
            throw new ValidationException("لا أيام لهذه الإجازة في الشهر المطلوب.");

        if (await db.EmployeeLeaveSettlements.AnyAsync(
                x => x.LeaveId == leaveId && x.LeaveYear == leaveYear && x.LeaveMonth == leaveMonth, ct))
            throw new ConflictException("بُتّ في حسم هذه الإجازة من قبل.");

        var entry = period.Entries.FirstOrDefault(
                        e => !e.IsDeleted && e.EmployeeCompanyId == leave.EmployeeCompanyId)
                    ?? throw new NotFoundException("صاحب الإجازة ليس في كشف هذا الشهر.");

        var monthLabel = $"{PayrollCalculator.ArabicMonth(leaveMonth)} {leaveYear}";

        if (applied)
        {
            // ⚠️ **تُضاف ولا تُستبدل**: قد يكون للموظف إجازتان في الشهر، وقد يكون المحاسب
            //    سجّل غياباً يدوياً قبلها — والاستبدال يمحو أيّهما سبق.
            entry.AbsenceDays += days;
            entry.AbsenceDeductionIsManual = false;
            Recompute(period, entry, null);
            entry.UpdatedAt = DateTime.UtcNow;
            period.UpdatedAt = DateTime.UtcNow;
        }

        db.EmployeeLeaveSettlements.Add(new EmployeeLeaveSettlement
        {
            LeaveId = leaveId,
            LeaveYear = leaveYear,
            LeaveMonth = leaveMonth,
            PeriodId = period.PeriodId,
            CompanyId = period.CompanyId,
            Days = days,
            Applied = applied,
            SettledByUserId = current.UserId,
            SettledAt = DateTime.UtcNow,
            Notes = string.IsNullOrWhiteSpace(notes) ? null : notes.Trim(),
        });

        // 🔴 **في ملفّ الموظف أيضاً**: الأثر مالٌ يُنقص راتبه، فمن يقرأ ملفّه لاحقاً يجب أن
        //    يرى لماذا نقص راتب ذلك الشهر ومَن قرّره.
        if (leave.EmployeeCompany is { } link)
            db.EmployeeLogs.Add(new EmployeeLog
            {
                EmployeeCompanyId = link.EmployeeCompanyId,
                CompanyId = link.CompanyId,
                ChangeType = EmployeeChangeType.LeaveDeductionSettled,
                Description = applied
                    ? $"حُسمت إجازة {leave.LeaveType.ArabicLabel()} ({days} يوماً من {monthLabel}) " +
                      $"من كشف {PayrollCalculator.ArabicMonth(month)} {year}"
                    : $"صُرف النظر عن حسم إجازة {leave.LeaveType.ArabicLabel()} " +
                      $"({days} يوماً من {monthLabel})",
                ChangedByUserId = current.UserId ?? 0,
                ChangedAt = DateTime.UtcNow,
            });

        audit.Add(applied ? "ApplyLeaveDeduction" : "WaiveLeaveDeduction",
            nameof(EmployeeLeave), leaveId.ToString(),
            $"{days} يوماً من {monthLabel} — كشف {year}-{month:D2}", period.CompanyId);

        await db.SaveChangesAsync(ct);
    }

    public async Task<List<EndOfServiceSuggestion>> SuggestEndOfServiceAsync(
        int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();

        var settings = await db.HrSettings.FirstOrDefaultAsync(s => s.CompanyId == companyId, ct);
        if (settings is null || !settings.EndOfServiceEnabled) return [];

        var period = await db.PayrollPeriods
            .Include(p => p.Entries.Where(e => !e.IsDeleted)).ThenInclude(e => e.EmployeeCompany)
            .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct);
        if (period is null) return [];

        var days = PayrollCalculator.DaysPerYear(
            settings.EndOfServiceRatio, settings.EndOfServiceCustomDays);

        var result = new List<EndOfServiceSuggestion>();
        foreach (var e in period.Entries.Where(x => x.IsTerminated))
        {
            var link = e.EmployeeCompany;
            if (link?.TerminationDate is not { } term) continue;

            var amount = PayrollCalculator.SuggestEndOfService(
                e.SnapshotBaseSalary, link.HireDate, term,
                settings.EndOfServiceRatio, settings.EndOfServiceCustomDays);
            if (amount <= 0) continue;

            var years = Math.Round((decimal)((term.Date - link.HireDate.Date).TotalDays / 365.25), 2);
            result.Add(new EndOfServiceSuggestion(
                e.EntryId, e.SnapshotName, amount, e.SnapshotCurrency.ToString(), years, days));
        }
        return result;
    }

    // ─────────────────────────── مساعدات ───────────────────────────

    /// <summary>
    /// حالة الدفع الابتدائية لسطرٍ جديد — تحمل قرار الشهر السابق للموظف المزدوج (G14).
    /// </summary>
    /// <remarks>
    /// **في اتجاهٍ واحد عمداً.** «يُصرف من هنا» يُحمَل لأن أسوأ نتائجه أن ندفع — وهو
    /// الافتراض أصلاً. و«صُرف من شركة أخرى» **لا يُحمَل**: حملُه يستثني راتباً بناءً على
    /// واقعةٍ قديمة فلا يقبض الموظف من أحد، وذلك أسوأ من ضغطةِ حسمٍ إضافية.
    ///
    /// ⚠️ **و<see cref="PayrollPaymentStatus.PaidByThisCompany"/> تُقرأ «قرارٌ سابق بالصرف
    /// من هنا»**: الشهر السابق سُدِّد، فتحوّل قرارُه إلى «مدفوع». وإغفالها كان يُلغي أثر
    /// الميزة كلَّه — إذ لا يبقى `ConfirmedByThisCompany` بعد التسديد أبداً.
    /// </remarks>
    private static PayrollPaymentStatus CarriedDecision(
        EmployeeCompany link,
        HashSet<int> dualEmployeeIds,
        IReadOnlyDictionary<int, PayrollPaymentStatus> previousDecisions) =>
        PayrollPayable.CarryDecision(
            isDual: dualEmployeeIds.Contains(link.EmployeeId),
            previous: previousDecisions.TryGetValue(link.EmployeeCompanyId, out var last)
                ? last : null);

    private void RecomputeAll(PayrollPeriod period)
    {
        foreach (var e in period.Entries.Where(x => !x.IsDeleted))
            Recompute(period, e, e.AbsenceDeductionIsManual ? e.AbsenceDeduction : null);
    }

    private static void Recompute(PayrollPeriod period, PayrollEntry entry, decimal? manualAbsence)
    {
        var link = entry.EmployeeCompany;
        var hire = link?.HireDate ?? new DateTime(period.Year, period.Month, 1);
        var term = link?.TerminationDate ?? entry.TerminationDate;

        var amounts = PayrollCalculator.Compute(
            period.Year, period.Month, period.WorkingDays,
            entry.SnapshotBaseSalary, entry.SnapshotCurrency, period.ExchangeRate,
            hire, term,
            entry.AbsenceDays, entry.BonusAmount, entry.DeductionAmount, manualAbsence,
            entry.EndOfServiceAmount);

        // الأيام المستحقّة قد يكون المستخدم عدّلها يدوياً ⇒ لا نفرض المحسوبة فوقها.
        // ⚠️ **بالعلَم الصريح لا بـ`EligibleDays > 0`**: الشرط القديم كان يصدق على كل سطرٍ
        //    حُسِب مرّةً، فيتجمّد عند أول قيمة ولا يتبع تغيّرَ أيام العمل ولا تاريخ التعيين
        //    ولا الإنهاء. (بلاغ المالك 2026-08-05: شباط بأيام 28 مجمّدة ومقام 30 ⇒ 28/30.)
        var eligible = entry.EligibleDaysIsManual ? entry.EligibleDays : amounts.EligibleDays;
        entry.EligibleDays = eligible;
        entry.AbsenceDeduction = amounts.AbsenceDeduction;
        entry.NetSalary = PayrollCalculator.NetSalary(
            entry.SnapshotBaseSalary, eligible, period.WorkingDays,
            entry.BonusAmount, entry.DeductionAmount, amounts.AbsenceDeduction,
            entry.EndOfServiceAmount);
        entry.NetSalaryIqd = PayrollCalculator.ToIqd(
            entry.NetSalary, entry.SnapshotCurrency, period.ExchangeRate);
    }

    private async Task<PayrollPeriod> RequireDraftAsync(int year, int month, CancellationToken ct)
    {
        ValidateYearMonth(year, month);
        var period = await db.PayrollPeriods
                         .Include(p => p.Entries.Where(e => !e.IsDeleted))
                            .ThenInclude(e => e.EmployeeCompany)
                         .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct)
                     ?? throw new NotFoundException("كشف هذا الشهر غير موجود.");

        if (period.Status == PayrollStatus.Paid)
            throw new ConflictException("الكشف مُسدَّد — لا يقبل التعديل.");
        return period;
    }

    // ─────────────────── تعديل الشهر المُسدَّد بإصدارات (ADR-026) ───────────────────

    /// <summary>
    /// يفتح شهراً للكتابة: مسودّةً كالمعتاد، أو **مُسدَّداً بتعديلٍ جراحيّ** إن سُمّي سببُه.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 🔴 **جراحيّ لا إعادةَ فتح**: الشهر يبقى `Paid` طوال التعديل. إسقاطُ الحالة إلى
    /// `Draft` كان يبدو أنظف، لكنه **يُعطّل كشف «مدفوع من شركة أخرى»** الذي يشترط
    /// `Status == Paid` — فتنفتح أثناء التعديل **نافذةُ صرفٍ مزدوج** هي بالضبط ما بُنيت
    /// ADR-024 لمنعه.
    /// </para>
    /// <para>
    /// ⚠️ **ثلاثة شروط معاً، وأولها السبب**: بلا سببٍ صريح لا يقع التعديل أصلاً مهما ملك
    /// الطالبُ من صلاحيات — فلا يُعدَّل شهرٌ مُسدَّد **بالخطأ** من عميلٍ يرسل الحمولة
    /// المعتادة. (سابقة السبب الإلزاميّ: فكّ الأرشفة — ADR-021.)
    /// </para>
    /// </remarks>
    private async Task<(PayrollPeriod Period, string? Reason)> OpenForWriteAsync(
        int year, int month, string? amendmentReason, CancellationToken ct)
    {
        ValidateYearMonth(year, month);
        var period = await db.PayrollPeriods
                         .Include(p => p.Entries.Where(e => !e.IsDeleted))
                            .ThenInclude(e => e.EmployeeCompany)
                         .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct)
                     ?? throw new NotFoundException("كشف هذا الشهر غير موجود.");

        if (period.Status != PayrollStatus.Paid) return (period, null);

        var reason = amendmentReason?.Trim();
        if (string.IsNullOrWhiteSpace(reason))
            throw new ConflictException(
                "الكشف مُسدَّد — التعديل بعد التسديد يحتاج سبباً صريحاً يُحفظ في سجلّ الإصدارات.");
        if (reason.Length < 5)
            throw new ValidationException("سبب التعديل قصيرٌ جداً — اكتب سبباً مفهوماً.");
        if (!current.CanAmendPaidPayroll)
            throw new ForbiddenException("لا تملك صلاحية تعديل شهرٍ مُسدَّد.");

        return (period, reason);
    }

    /// <summary>يحفظ لقطة الشهر **قبل** تغييره، ويرقّم الإصدار.</summary>
    /// <remarks>
    /// يتبع سابقة الصادر حرفياً (<c>OutgoingService.EditApprovedAsync</c>): كيان
    /// <see cref="DocumentVersion"/> العامّ نفسه، وترقيمٌ متسلسل، و<c>ChangeNote</c> هو
    /// السبب. **يُستدعى قبل أي تغيير** — لقطةٌ بعد التغيير تُوثّق الحاضر لا الماضي.
    /// </remarks>
    private async Task SnapshotAsync(PayrollPeriod period, string reason, CancellationToken ct)
    {
        var last = await db.DocumentVersions
            .Where(v => v.DocType == OwnerType.PayrollPeriod && v.DocId == period.PeriodId)
            .MaxAsync(v => (int?)v.VersionNo, ct) ?? 0;

        db.DocumentVersions.Add(new DocumentVersion
        {
            DocType = OwnerType.PayrollPeriod,
            DocId = period.PeriodId,
            VersionNo = last + 1,
            SnapshotJson = SnapshotOf(period),
            ChangedByUserId = current.UserId ?? 0,
            ChangedAt = DateTime.UtcNow,
            ChangeNote = reason,
        });

        period.LastAmendedAt = DateTime.UtcNow;
        period.AmendmentCount = last + 1;

        audit.Add("AmendPaidPayroll", nameof(PayrollPeriod), $"{period.Year}-{period.Month:D2}",
            $"تعديل بعد التسديد (إصدار {last + 1}): {reason}", period.CompanyId);
    }

    /// <summary>
    /// يُعلّم إيصال السطر **مبتوتاً** بعد تعديل الشهر — بقبولٍ (رفعُ بديل) أو رفض.
    /// </summary>
    /// <remarks>
    /// ⚠️ **يتطلّب `CanManagePayroll` لا `CanAmendPaidPayroll`**: البتّ في صحّة إيصالٍ عملُ
    /// محاسبٍ يوميّ، لا صلاحيةُ فتح شهرٍ مُقفَل. حصرُه في المعدِّلين كان يُبقي التنبيه معلّقاً
    /// على شاشة مَن لا يستطيع إزالته.
    /// </remarks>
    public async Task AcknowledgeReceiptAsync(int entryId, CancellationToken ct = default)
    {
        RequireWrite();
        var entry = await db.PayrollEntries.Include(e => e.Period)
                        .FirstOrDefaultAsync(e => e.EntryId == entryId && !e.IsDeleted, ct)
                    ?? throw new NotFoundException("سطر الراتب غير موجود.");

        entry.ReceiptAcknowledgedAt = DateTime.UtcNow;
        entry.UpdatedAt = DateTime.UtcNow;
        audit.Add("AcknowledgeReceipt", nameof(PayrollEntry), entryId.ToString(),
            $"{entry.SnapshotName} — بُتّ في تقادم الإيصال", entry.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>سجلّ تعديلات الشهر — الأحدث أولاً، مع اسم مَن عدّل.</summary>
    /// <remarks>
    /// ⚠️ **قراءةٌ لمن يملك قسم الرواتب، لا لمن يملك التعديل وحده**: مَن يرى الكشف يحقّ له
    /// أن يعرف **لماذا اختلف عمّا وقّع عليه**. حصرُ السجلّ في المعدِّلين كان يجعل الأثر
    /// مرئياً لمن أحدثه وحده — وهو نقيض غرض السجلّ.
    /// </remarks>
    public async Task<List<PayrollAmendment>> AmendmentsAsync(
        int year, int month, CancellationToken ct = default)
    {
        ValidateYearMonth(year, month);
        var period = await db.PayrollPeriods
                         .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct)
                     ?? throw new NotFoundException("كشف هذا الشهر غير موجود.");

        // ⚠️ الوصول محكومٌ بالفلتر العام على `PayrollPeriods` أعلاه: شهرُ شركةٍ أخرى لا
        //    يُعثر عليه أصلاً، فلا يُقرأ سجلّ تعديلاته.
        var rows = await db.DocumentVersions
            .Where(v => v.DocType == OwnerType.PayrollPeriod && v.DocId == period.PeriodId)
            .OrderByDescending(v => v.VersionNo)
            .Select(v => new
            {
                v.VersionNo, v.ChangeNote, v.ChangedByUserId, v.ChangedAt, v.SnapshotJson,
            })
            .ToListAsync(ct);

        // 🔴 **الاسم يُقرأ باستعلامٍ ثانٍ لا برَبطٍ داخليّ (ADR-034):** `db.Users` عليه
        //    فلتر شركة، والسوبر أدمن قد يكون **بلا شركة ولا إسنادات** (ADR-017) فيسقط
        //    صفُّه منه متى حمل الطلب `X-Company-Id`. والـinner join حينئذٍ لا يمحو **اسم
        //    الفاعل** وحده بل **قيد التعديل كلّه** — اللقطة والسبب والتاريخ — فيقول
        //    `AmendmentCount` «١» ويعود السجلّ فارغاً، فيصير أثرُ التعديل على شهرٍ مُسدَّد
        //    غير قابل للتدقيق. **السطر يبقى ولو تعذّر اسم فاعله** — معلومة ناقصة
        //    أهون من معلومة كاذبة، وكلتاهما أهون من محو الأثر.
        //    وهي عائلة ADR-031 نفسها («سطور دخول بلا فاعل») وعلاجها نفسه:
        //    `ReportService.ActivityAsync` — و`IgnoreQueryFilters` **مقصورٌ على حقل الاسم**
        //    لا يفتح صفّ المستخدم، والعزل بَعدُ قائمٌ على الشهر نفسه أعلاه.
        var ids = rows.Select(r => r.ChangedByUserId).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => ids.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.FullName, ct);

        return rows.Select(r => new PayrollAmendment(
            r.VersionNo, r.ChangeNote ?? "",
            names.TryGetValue(r.ChangedByUserId, out var name) ? name : "—",
            r.ChangedAt, r.SnapshotJson)).ToList();
    }

    /// <summary>لقطة الشهر بسطوره — ما يكفي لمعرفة **مَن كان يستحقّ كم** قبل التعديل.</summary>
    private static string SnapshotOf(PayrollPeriod p) => System.Text.Json.JsonSerializer.Serialize(new
    {
        p.Year, p.Month, p.ExchangeRate, p.WorkingDaysMode, p.WorkingDays,
        p.Status, p.PaidAt, p.ManualBookNumber, p.Notes,
        Entries = p.Entries.Where(e => !e.IsDeleted).OrderBy(e => e.DisplayOrder).Select(e => new
        {
            e.EntryId, e.SnapshotName, e.SnapshotPosition, e.SnapshotCurrency, e.SnapshotBaseSalary,
            e.EligibleDays, e.AbsenceDays, e.AbsenceDeduction, e.BonusAmount, e.DeductionAmount,
            e.EndOfServiceAmount, e.NetSalary, e.NetSalaryIqd, e.PaymentStatus, e.Notes,
        }),
    });

    private void Guard(PayrollPeriod period, byte[] rowVersion) =>
        db.Entry(period).Property(p => p.RowVersion).OriginalValue = rowVersion;

    private async Task SaveGuardedAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException)
        {
            throw new ConflictException("عُدّل الكشف من مستخدم آخر — أعد التحميل وحاول مجدداً.");
        }
    }

    private void SoftDelete(PayrollPeriod period)
    {
        var now = DateTime.UtcNow;
        period.IsDeleted = true;
        period.DeletedByUserId = current.UserId;
        period.DeletedAt = now;
        foreach (var e in period.Entries.Where(x => !x.IsDeleted))
        {
            e.IsDeleted = true;
            e.DeletedByUserId = current.UserId;
            e.DeletedAt = now;
        }
    }

    private async Task<decimal?> LatestUsdRateAsync(CancellationToken ct) =>
        await db.ExchangeRates.Where(r => r.Currency == Currency.USD)
            .OrderByDescending(r => r.EffectiveDate)
            .Select(r => (decimal?)r.Rate).FirstOrDefaultAsync(ct);

    private static void ValidateYearMonth(int year, int month)
    {
        if (month is < 1 or > 12) throw new ValidationException("الشهر يجب أن يكون بين 1 و12.");
        if (year < 2000 || year > DateTime.UtcNow.Year + MaxHistoryYearsAhead)
            throw new ValidationException("السنة خارج النطاق المسموح.");
    }

    private void RequireWrite()
    {
        if (!current.CanManagePayroll)
            throw new ForbiddenException("لا تملك صلاحية إدارة كشوف الرواتب.");
    }

    private int RequireCompany() =>
        current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");
}
