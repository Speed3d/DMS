using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Hr;

// ─────────────────────────── العقود ───────────────────────────

public sealed record PayrollYearSummary(int Year, int MonthsCreated, int MonthsPaid, decimal TotalIqd);

public sealed record PayrollMonthSummary(
    int Year, int Month, bool Exists, PayrollStatus? Status, int EmployeeCount, decimal TotalIqd);

/// <summary>
/// مدخلات سطر واحد عند الحفظ الجماعي. **بلا صافٍ** — الخادم يحسبه ولا يقبله.
/// </summary>
public sealed record SaveEntryInput(
    int EntryId, int AbsenceDays, decimal? BonusAmount, decimal? DeductionAmount,
    decimal? ManualAbsenceDeduction, int? EligibleDaysOverride, string? Notes);

public sealed record PeriodSettingsInput(
    decimal? ExchangeRate, WorkingDaysMode WorkingDaysMode, int WorkingDays, string? Notes);

public sealed record PaymentInput(
    DateTime PaidAt, int? OutgoingBookId, string? ManualBookNumber, string? Notes);

/// <summary>حصيلة التوليد — يراها المستخدم فيعرف ماذا تغيّر بالضبط.</summary>
public sealed record GenerateResult(int Added, int Existing, int Skipped);

/// <summary>تنبيه «مدفوع من شركة أخرى» (ADR-024).</summary>
public sealed record ExternalPaymentHint(
    int EntryId, string EmployeeName, int PaidByCompanyId, string PaidByCompanyName);

public interface IPayrollService
{
    Task<List<PayrollYearSummary>> YearsAsync(CancellationToken ct = default);
    Task<List<PayrollMonthSummary>> MonthsAsync(int year, CancellationToken ct = default);
    Task<PayrollPeriod?> FindPeriodAsync(int year, int month, CancellationToken ct = default);
    Task<GenerateResult> GenerateAsync(int year, int month, CancellationToken ct = default);
    Task<PayrollPeriod> UpdateSettingsAsync(int year, int month, PeriodSettingsInput input, byte[] rowVersion, CancellationToken ct = default);
    Task<PayrollPeriod> SaveEntriesAsync(int year, int month, List<SaveEntryInput> entries, byte[] rowVersion, CancellationToken ct = default);
    Task PayAsync(int year, int month, PaymentInput input, byte[] rowVersion, CancellationToken ct = default);
    Task DeletePeriodAsync(int year, int month, CancellationToken ct = default);
    Task DeleteYearAsync(int year, CancellationToken ct = default);
    Task<List<ExternalPaymentHint>> DetectExternalPaymentsAsync(int year, int month, CancellationToken ct = default);
    Task ConfirmExternalPaymentAsync(int entryId, CancellationToken ct = default);
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

        var totals = await db.PayrollEntries
            .GroupBy(e => e.Period!.Year)
            .Select(g => new { Year = g.Key, Total = g.Sum(x => x.NetSalaryIqd) })
            .ToDictionaryAsync(x => x.Year, x => x.Total, ct);

        return periods
            .GroupBy(p => p.Year)
            .Select(g => new PayrollYearSummary(
                g.Key,
                g.Count(),
                g.Count(p => p.Status == PayrollStatus.Paid),
                totals.TryGetValue(g.Key, out var t) ? t : 0m))
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
                Total = p.Entries.Where(e => !e.IsDeleted).Sum(e => (decimal?)e.NetSalaryIqd) ?? 0m,
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
    public async Task<GenerateResult> GenerateAsync(int year, int month, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        ValidateYearMonth(year, month);

        var period = await db.PayrollPeriods
            .Include(p => p.Entries)
            .FirstOrDefaultAsync(p => p.Year == year && p.Month == month, ct);

        if (period is { Status: PayrollStatus.Paid })
            throw new ConflictException("الكشف مُسدَّد — لا يمكن إضافة موظفين إليه.");

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
                PaymentStatus = PayrollPaymentStatus.Unpaid,
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
        int year, int month, PeriodSettingsInput input, byte[] rowVersion, CancellationToken ct = default)
    {
        RequireWrite();
        var period = await RequireDraftAsync(year, month, ct);
        Guard(period, rowVersion);

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
        int year, int month, List<SaveEntryInput> entries, byte[] rowVersion, CancellationToken ct = default)
    {
        RequireWrite();
        var period = await RequireDraftAsync(year, month, ct);
        Guard(period, rowVersion);

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

            if (input.EligibleDaysOverride is { } days)
            {
                if (days < 0 || days > period.WorkingDays)
                    throw new ValidationException($"الأيام المستحقّة يجب أن تكون بين 0 و{period.WorkingDays}.");
                entry.EligibleDays = days;
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
        PayrollCalculator.EnsureRateSet(
            live.Any(e => e.SnapshotCurrency == Currency.USD), period.ExchangeRate);
        foreach (var e in live) PayrollCalculator.EnsurePayable(e.SnapshotName, e.NetSalary);

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

        // مَن كان «لم يُصرف» يصير مصروفاً من هذه الشركة؛ ومَن عُلِّم مدفوعاً من الخارج يبقى.
        foreach (var e in live.Where(x => x.PaymentStatus == PayrollPaymentStatus.Unpaid))
            e.PaymentStatus = PayrollPaymentStatus.PaidByThisCompany;

        audit.Add("PayPayroll", nameof(PayrollPeriod), $"{year}-{month:D2}",
            $"تسديد {live.Count} راتباً بإجمالي {live.Sum(x => x.NetSalaryIqd):#,0.##} د.ع", period.CompanyId);
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

        var mine = period.Entries
            .Where(e => !e.IsDeleted && e.PaymentStatus == PayrollPaymentStatus.Unpaid)
            .ToList();
        if (mine.Count == 0) return [];

        var linkIds = mine.Select(e => e.EmployeeCompanyId).ToList();
        var employeeByLink = await db.EmployeeCompanies.IgnoreQueryFilters()
            .Where(x => linkIds.Contains(x.EmployeeCompanyId))
            .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x.EmployeeId, ct);
        var employeeIds = employeeByLink.Values.Distinct().ToList();

        // الشركات الأخرى التي صرفت لهؤلاء في هذا الشهر.
        var elsewhere = await db.PayrollEntries.IgnoreQueryFilters()
            .Where(e => !e.IsDeleted
                     && e.CompanyId != companyId
                     && e.Period!.Year == year && e.Period.Month == month
                     && e.Period.Status == PayrollStatus.Paid
                     && employeeIds.Contains(e.EmployeeCompany!.EmployeeId))
            .Select(e => new { e.CompanyId, EmployeeId = e.EmployeeCompany!.EmployeeId })
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
                payerNames.TryGetValue(payer.CompanyId, out var n) ? n : "شركة أخرى"));
        }
        return hints;
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
        entry.UpdatedAt = DateTime.UtcNow;

        audit.Add("ConfirmExternalPayment", nameof(PayrollEntry), entryId.ToString(),
            $"{entry.SnapshotName} — مدفوع من {hint.PaidByCompanyName}", entry.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    // ─────────────────────────── مساعدات ───────────────────────────

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
            entry.AbsenceDays, entry.BonusAmount, entry.DeductionAmount, manualAbsence);

        // الأيام المستحقّة قد يكون المستخدم عدّلها يدوياً ⇒ لا نفرض المحسوبة فوقها.
        var eligible = entry.EligibleDays > 0 ? entry.EligibleDays : amounts.EligibleDays;
        entry.EligibleDays = eligible;
        entry.AbsenceDeduction = amounts.AbsenceDeduction;
        entry.NetSalary = PayrollCalculator.NetSalary(
            entry.SnapshotBaseSalary, eligible, period.WorkingDays,
            entry.BonusAmount, entry.DeductionAmount, amounts.AbsenceDeduction);
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
        if (!current.CanManageHR)
            throw new ForbiddenException("لا تملك صلاحية إدارة الموظفين والرواتب.");
    }

    private int RequireCompany() =>
        current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");
}
