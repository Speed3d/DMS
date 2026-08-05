using System.Globalization;
using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Documents.Reports;
using Dms.Domain;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Hr;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

/// <summary>كشوف الرواتب (ADR-023). السنوات مشتقّة من الفترات — لا كيان «سنة».</summary>
[ApiController]
[Authorize]
[RequireHrModule(AppModule.Payroll)]
[Route("api/payroll")]
public sealed class PayrollController(
    IPayrollService payroll, AppDbContext db, ICurrentUser current,
    IAttachmentService attachments) : ControllerBase
{
    // ─────────────────────────── تصفّح ───────────────────────────

    [HttpGet("years")]
    public async Task<ActionResult<List<PayrollYearResponse>>> Years(CancellationToken ct)
        => (await payroll.YearsAsync(ct))
            .Select(y => new PayrollYearResponse(y.Year, y.MonthsCreated, y.MonthsPaid, y.TotalIqd)).ToList();

    [HttpGet("years/{year:int}/months")]
    public async Task<ActionResult<List<PayrollMonthResponse>>> Months(int year, CancellationToken ct)
        => (await payroll.MonthsAsync(year, ct))
            .Select(m => new PayrollMonthResponse(
                m.Year, m.Month, PayrollCalculator.ArabicMonth(m.Month),
                m.Exists, m.Status, m.EmployeeCount, m.TotalIqd)).ToList();

    [HttpGet("periods/{year:int}/{month:int}")]
    public async Task<ActionResult<PayrollPeriodResponse?>> Period(int year, int month, CancellationToken ct)
    {
        var period = await payroll.FindPeriodAsync(year, month, ct);
        return period is null ? Ok(null) : Ok(await MapAsync(period, ct));
    }

    // ─────────────────────────── تحرير ───────────────────────────

    /// <summary>توليد/تحديث الكشف — **تراكميّ**: يضيف الناقص ولا يمسّ ما أُدخل يدوياً.</summary>
    [HttpPost("periods/{year:int}/{month:int}")]
    public async Task<ActionResult<GenerateResponse>> Generate(
        int year, int month, [FromBody] GenerateRequest? req, CancellationToken ct)
    {
        var r = await payroll.GenerateAsync(year, month, req?.AmendmentReason, ct);
        return new GenerateResponse(r.Added, r.Existing, r.Skipped);
    }

    [HttpPut("periods/{year:int}/{month:int}")]
    public async Task<ActionResult<PayrollPeriodResponse>> UpdateSettings(
        int year, int month, PeriodSettingsRequest req, CancellationToken ct)
    {
        var period = await payroll.UpdateSettingsAsync(year, month,
            new PeriodSettingsInput(req.ExchangeRate, req.WorkingDaysMode, req.WorkingDays, req.Notes),
            req.RowVersion, req.AmendmentReason, ct);
        return await MapAsync(period, ct);
    }

    [HttpPut("periods/{year:int}/{month:int}/entries")]
    public async Task<ActionResult<PayrollPeriodResponse>> SaveEntries(
        int year, int month, SaveEntriesRequest req, CancellationToken ct)
    {
        var inputs = req.Entries.Select(e => new SaveEntryInput(
            e.EntryId, e.AbsenceDays, e.BonusAmount, e.DeductionAmount,
            e.ManualAbsenceDeduction, e.EligibleDaysOverride, e.Notes,
            e.EndOfServiceAmount)).ToList();

        var period = await payroll.SaveEntriesAsync(
            year, month, inputs, req.RowVersion, req.AmendmentReason, ct);
        return await MapAsync(period, ct);
    }

    [HttpPost("periods/{year:int}/{month:int}/pay")]
    public async Task<IActionResult> Pay(int year, int month, PayRequest req, CancellationToken ct)
    {
        await payroll.PayAsync(year, month,
            new PaymentInput(req.PaidAt, req.OutgoingBookId, req.ManualBookNumber, req.Notes),
            req.RowVersion, ct);
        return NoContent();
    }

    // ─────────── إيصال الاستلام الموقَّع (بلاغ المالك ٦ + ADR-026) ───────────

    /// <summary>إيصالات موظفٍ بعينه في هذا الشهر — الموقَّعة المرفوعة.</summary>
    [HttpGet("entries/{entryId:int}/receipts")]
    public async Task<ActionResult<List<SignedReceiptResponse>>> SignedReceipts(
        int entryId, CancellationToken ct)
        => (await attachments.ListAsync(OwnerType.PayrollEntry, entryId, ct))
            .Select(a => new SignedReceiptResponse(
                a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt))
            .ToList();

    /// <summary>رفع الإيصال بعد توقيع الموظف — مرجعٌ كامل بأنه استلم ووقّع.</summary>
    /// <remarks>
    /// ⚠️ **يُقبل على شهرٍ مُسدَّد عمداً** — بل هو موضعه الطبيعي: الموظف يوقّع **بعد**
    /// الصرف لا قبله. ولهذا لا يمرّ من حارس التعديل.
    /// </remarks>
    [HttpPost("entries/{entryId:int}/receipts")]
    public async Task<ActionResult<SignedReceiptResponse>> UploadSignedReceipt(
        int entryId, IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) throw new ValidationException("الملف مطلوب.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var att = await attachments.AddAsync(
            OwnerType.PayrollEntry, entryId, file.FileName, ms.ToArray(), ct);

        // ⚠️ **الرفع بتٌّ في التقادم كذلك**: مَن رفع إيصالاً جديداً بعد التعديل فقد أجاب
        //    السؤال بـ«قبول» فعلاً — فسؤالُه ثانيةً بعد ذلك عبث.
        await payroll.AcknowledgeReceiptAsync(entryId, ct);

        return new SignedReceiptResponse(
            att.AttachmentId, att.FileName, att.FileType, att.FileSize, att.UploadedAt);
    }

    /// <summary>
    /// **«رفض»**: تعديلُ الشهر لا يمسّ هذا الموظف، وإيصاله الموقَّع باقٍ صحيحاً (ADR-026).
    /// </summary>
    /// <remarks>
    /// القرار للإنسان لا للنظام: النظام لا يعرف أيَّ موظفٍ تأثّر بتعديلٍ ما، والمحاسب يعرف.
    /// </remarks>
    [HttpPost("entries/{entryId:int}/receipts/acknowledge")]
    public async Task<IActionResult> AcknowledgeReceipt(int entryId, CancellationToken ct)
    {
        await payroll.AcknowledgeReceiptAsync(entryId, ct);
        return NoContent();
    }

    [HttpGet("entries/{entryId:int}/receipts/{attachmentId:int}/download")]
    public async Task<IActionResult> DownloadSignedReceipt(
        int entryId, int attachmentId, bool inline, CancellationToken ct)
    {
        var (meta, content) = await attachments.GetAsync(attachmentId, ct);
        if (inline) return File(content, MimeTypes.For(meta.FileName));
        return File(content, "application/octet-stream", meta.FileName);
    }

    /// <summary>سجلّ تعديلات الشهر بعد التسديد (ADR-026) — الأحدث أولاً.</summary>
    [HttpGet("periods/{year:int}/{month:int}/amendments")]
    public async Task<ActionResult<List<PayrollAmendmentResponse>>> Amendments(
        int year, int month, CancellationToken ct)
        => (await payroll.AmendmentsAsync(year, month, ct))
            .Select(a => new PayrollAmendmentResponse(
                a.VersionNo, a.Reason, a.ChangedBy, a.ChangedAt, a.SnapshotJson))
            .ToList();

    [HttpDelete("periods/{year:int}/{month:int}")]
    public async Task<IActionResult> DeletePeriod(int year, int month, CancellationToken ct)
    {
        await payroll.DeletePeriodAsync(year, month, ct);
        return NoContent();
    }

    [HttpDelete("years/{year:int}")]
    public async Task<IActionResult> DeleteYear(int year, CancellationToken ct)
    {
        await payroll.DeleteYearAsync(year, ct);
        return NoContent();
    }

    // ─────────────────────────── «مدفوع من شركة أخرى» (ADR-024) ───────────────────────────

    [HttpGet("periods/{year:int}/{month:int}/external-payments")]
    public async Task<ActionResult<List<ExternalPaymentResponse>>> ExternalPayments(
        int year, int month, CancellationToken ct)
        => (await payroll.DetectExternalPaymentsAsync(year, month, ct))
            .Select(h => new ExternalPaymentResponse(
                h.EntryId, h.EmployeeName, h.PaidByCompanyId, h.PaidByCompanyName,
                h.PaidAt)).ToList();

    [HttpPost("entries/{entryId:int}/confirm-external")]
    public async Task<IActionResult> ConfirmExternal(int entryId, CancellationToken ct)
    {
        await payroll.ConfirmExternalPaymentAsync(entryId, ct);
        return NoContent();
    }

    /// <summary>مكافآت نهاية الخدمة **المقترَحة** لمن انتهت خدمتهم هذا الشهر (الدفعة ٢).</summary>
    /// <remarks>اقتراحٌ لا تطبيق — تُضاف بحفظ السطر بقيمة يقرّرها المستخدم.</remarks>
    [HttpGet("periods/{year:int}/{month:int}/end-of-service")]
    public async Task<ActionResult<List<EndOfServiceResponse>>> EndOfService(
        int year, int month, CancellationToken ct)
        => (await payroll.SuggestEndOfServiceAsync(year, month, ct))
            .Select(s => new EndOfServiceResponse(
                s.EntryId, s.EmployeeName, s.Amount, s.Currency, s.YearsServed, s.DaysPerYear))
            .ToList();

    // ─────────────────────────── مخرجات ───────────────────────────

    [HttpGet("periods/{year:int}/{month:int}/excel")]
    public async Task<IActionResult> Excel(int year, int month, CancellationToken ct)
    {
        var period = await RequirePeriodAsync(year, month, ct);

        string[] headers =
        [
            "م", "الاسم", "الصفة", "العملة", "الأساسي", "مكافأة", "خصم",
            "أيام الغياب", "خصم الغياب", "الصافي", "الصافي (د.ع)", "حالة الدفع", "ملاحظات",
        ];

        var i = 1;
        var rows = period.Entries.OrderBy(e => e.DisplayOrder).Select(e => new ExcelRow(
        [
            (i++).ToString(), e.SnapshotName, e.SnapshotPosition, CurrencyLabel(e.SnapshotCurrency),
            Num(e.SnapshotBaseSalary), Num(e.BonusAmount), Num(e.DeductionAmount),
            e.AbsenceDays.ToString(), Num(e.AbsenceDeduction),
            Num(e.NetSalary), Num(e.NetSalaryIqd), PaymentLabel(e), e.Notes ?? "",
        ],
            e switch
            {
                { IsTerminated: true } => ExcelRowStyle.Warning,
                { IsNewHire: true } => ExcelRowStyle.Highlight,
                { PaymentStatus: PayrollPaymentStatus.PaidByOtherCompany } => ExcelRowStyle.Note,
                _ => ExcelRowStyle.Normal,
            })).ToList();

        rows.Add(new ExcelRow(
            ["", "الإجمالي", "", "", "", "", "", "", "", "", Num(period.Entries.Sum(e => e.NetSalaryIqd)), "", ""],
            ExcelRowStyle.Total));

        var bytes = ExcelExporter.CreateStyled($"رواتب {month:D2}-{year}", headers, rows);
        return File(bytes, MimeTypes.For(".xlsx"), $"payroll-{year}-{month:D2}.xlsx");
    }

    [HttpGet("periods/{year:int}/{month:int}/pdf")]
    public async Task<IActionResult> Pdf(int year, int month, CancellationToken ct)
    {
        var period = await RequirePeriodAsync(year, month, ct);
        var company = await CompanyNameAsync(ct);

        var model = new PayrollSheetModel(
            company, PayrollCalculator.ArabicMonth(month), year,
            period.Status == PayrollStatus.Paid ? "مُسدَّد" : "مسودة",
            period.WorkingDays.ToString(),
            period.ExchangeRate is { } r ? Num(r) : null,
            period.Entries.OrderBy(e => e.DisplayOrder).Select(e => new PayrollSheetLine(
                e.SnapshotName, e.SnapshotPosition, CurrencyLabel(e.SnapshotCurrency),
                Num(e.SnapshotBaseSalary), Num(e.BonusAmount), Num(e.DeductionAmount),
                e.AbsenceDays.ToString(), Num(e.AbsenceDeduction),
                Num(e.NetSalary), Num(e.NetSalaryIqd), PaymentLabel(e), e.Notes,
                e.IsNewHire, e.IsTerminated)).ToList(),
            Num(period.Entries.Sum(e => e.NetSalaryIqd)));

        return File(PayrollSheetPdf.Generate(model), MimeTypes.For(".pdf"));
    }

    /// <summary>إيصالات كل موظفي الشهر في ملف واحد — صفحة لكل موظف.</summary>
    [HttpGet("periods/{year:int}/{month:int}/receipts")]
    public async Task<IActionResult> Receipts(
        int year, int month, [FromQuery] int? employeeId, CancellationToken ct)
    {
        var period = await RequirePeriodAsync(year, month, ct);
        var company = await CompanyNameAsync(ct);

        var entries = period.Entries.OrderBy(e => e.DisplayOrder).ToList();
        var linkIds = entries.Select(e => e.EmployeeCompanyId).ToList();

        var people = await db.EmployeeCompanies.Include(x => x.Employee)
            .Where(x => linkIds.Contains(x.EmployeeCompanyId))
            .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x, ct);

        if (employeeId is { } eid)
            entries = entries.Where(e =>
                people.TryGetValue(e.EmployeeCompanyId, out var p) && p.EmployeeId == eid).ToList();

        if (entries.Count == 0) throw new NotFoundException("لا توجد إيصالات لهذا الطلب.");

        var models = entries.Select(e =>
        {
            people.TryGetValue(e.EmployeeCompanyId, out var link);
            var emp = link?.Employee;
            var english = emp?.ReceiptLanguage == ReceiptLanguage.English;

            var name = english ? emp?.FullNameEn ?? e.SnapshotName : e.SnapshotName;
            var position = english ? link?.PositionEn ?? e.SnapshotPosition : e.SnapshotPosition;

            // المبلغ بالعملة الأجنبية يُذكر إلى جانب الدينار فقط حين تختلف عنه.
            var foreign = e.SnapshotCurrency == Currency.USD
                ? $"{Num(e.NetSalary)} {(english ? "USD" : "دولار أمريكي")}"
                : null;

            return new SalaryReceiptModel(
                company, name, position,
                english ? PayrollCalculator.EnglishMonth(month) : PayrollCalculator.ArabicMonth(month),
                year, Num(e.NetSalaryIqd), foreign,
                DateTime.Now.ToString("yyyy-MM-dd"), english);
        }).ToList();

        return File(SalaryReceiptPdf.Generate(models), MimeTypes.For(".pdf"));
    }

    // ─────────────────────────── مساعدات ───────────────────────────

    private async Task<PayrollPeriod> RequirePeriodAsync(int year, int month, CancellationToken ct)
        => await payroll.FindPeriodAsync(year, month, ct)
           ?? throw new NotFoundException("كشف هذا الشهر غير موجود.");

    private async Task<PayrollPeriodResponse> MapAsync(PayrollPeriod p, CancellationToken ct)
    {
        var linkIds = p.Entries.Select(e => e.EmployeeCompanyId).ToList();
        var employeeByLink = await db.EmployeeCompanies
            .Where(x => linkIds.Contains(x.EmployeeCompanyId))
            .ToDictionaryAsync(x => x.EmployeeCompanyId, x => x.EmployeeId, ct);

        // ── إيصالات الاستلام الموقَّعة وتقادمها (ADR-026) ──
        // ⚠️ **استعلامٌ واحد لكل السطور** لا واحدٌ لكل سطر: كشفُ مئة موظف كان يُنتج مئة
        //    رحلة إلى القاعدة عند كل فتحٍ للشاشة.
        var entryIds = p.Entries.Select(e => e.EntryId).ToList();
        var receiptTimes = await db.Attachments
            .Where(a => a.OwnerType == OwnerType.PayrollEntry && entryIds.Contains(a.OwnerId))
            .GroupBy(a => a.OwnerId)
            .Select(g => new { EntryId = g.Key, Count = g.Count(), Latest = g.Max(x => x.UploadedAt) })
            .ToDictionaryAsync(x => x.EntryId, x => x, ct);

        // إيصالٌ «متقادم» = رُفع **قبل** آخر تعديلٍ للشهر، ولم يُبَتّ فيه بعده.
        bool IsStale(PayrollEntry e)
        {
            if (p.LastAmendedAt is not { } amended) return false;
            if (!receiptTimes.TryGetValue(e.EntryId, out var r)) return false;
            if (r.Latest >= amended) return false;
            return e.ReceiptAcknowledgedAt is not { } ack || ack < amended;
        }

        var entries = p.Entries.OrderBy(e => e.DisplayOrder).Select(e => new PayrollEntryResponse(
            e.EntryId, e.EmployeeCompanyId,
            employeeByLink.TryGetValue(e.EmployeeCompanyId, out var empId) ? empId : 0,
            e.DisplayOrder, e.SnapshotName, e.SnapshotPosition, e.SnapshotCurrency, e.SnapshotBaseSalary,
            e.EligibleDays, e.EligibleDaysIsManual, e.AbsenceDays, e.BonusAmount, e.DeductionAmount,
            e.AbsenceDeduction, e.AbsenceDeductionIsManual, e.EndOfServiceAmount,
            e.NetSalary, e.NetSalaryIqd,
            e.PaymentStatus, e.PaidByCompanyId, e.PaidByCompanyName,
            e.IsNewHire, e.IsTerminated, e.Notes,
            receiptTimes.TryGetValue(e.EntryId, out var rc) ? rc.Count : 0,
            IsStale(e))).ToList();

        return new PayrollPeriodResponse(
            p.PeriodId, p.Year, p.Month, PayrollCalculator.ArabicMonth(p.Month), p.Status,
            p.ExchangeRate, p.WorkingDaysMode, p.WorkingDays,
            p.PaidAt, p.OutgoingBookId, p.ManualBookNumber, p.Notes,
            p.RowVersion ?? [], entries.Sum(e => e.NetSalaryIqd), entries,
            p.LastAmendedAt, p.AmendmentCount, current.CanAmendPaidPayroll);
    }

    private async Task<string> CompanyNameAsync(CancellationToken ct)
        => await db.Companies.Where(c => c.CompanyId == current.ActiveCompanyId)
               .Select(c => c.Name).FirstOrDefaultAsync(ct) ?? "—";

    private static string Num(decimal? v) =>
        v is null ? "—" : v.Value.ToString("#,0.##", CultureInfo.InvariantCulture);

    private static string CurrencyLabel(Currency c) => c == Currency.USD ? "دولار" : "دينار";

    private static string PaymentLabel(PayrollEntry e) => e.PaymentStatus switch
    {
        PayrollPaymentStatus.PaidByThisCompany => "مصروف",
        PayrollPaymentStatus.PaidByOtherCompany => $"مدفوع من {e.PaidByCompanyName ?? "شركة أخرى"}",
        _ => "لم يُصرف",
    };
}
