using Dms.Documents.Reports;
using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Hr;

/// <summary>هويّة المستخدم كما يراها في بروفايله — **قراءةٌ خالصة** (ADR-033).</summary>
/// <remarks>
/// الحقول المشتقّة من البطاقة فارغةٌ لمن لا بطاقةَ له (سوبر أدمن · مستخدمٌ لم يُربط بعد)،
/// وليست خطأً: في النظام مستخدمون ليسوا موظفين وموظفون ليسوا مستخدمين.
/// </remarks>
public sealed record MyIdentity(
    int UserId, string FullName, string Username, UserRole Role,
    string? CompanyName, string? DepartmentName,
    int? EmployeeId, string? EmployeeFullName, string? EmployeeFullNameEn,
    string? Position, DateTime? HireDate, string? NationalId, string? Phone,
    string? Address, bool HasPhoto);

/// <summary>شهرٌ من رواتبي — **مُسدَّدٌ حصراً** (ADR-033).</summary>
public sealed record MyPayslip(
    int PeriodId, int Year, int Month, string MonthLabel,
    decimal BaseSalary, int EligibleDays, int WorkingDays, int AbsenceDays,
    decimal AbsenceDeduction, decimal? BonusAmount, decimal? DeductionAmount,
    decimal NetSalary, decimal NetSalaryIqd, Currency Currency,
    PayrollPaymentStatus PaymentStatus, string PaymentStatusLabel, DateTime? PaidAt);

/// <summary>طلب إجازةٍ ذاتيّ — **بلا قرار حسم** (يقرّره المراجع).</summary>
public sealed record LeaveRequestInput(
    LeaveType LeaveType, DateTime FromDate, DateTime ToDate, string? Notes);

public interface IProfileService
{
    Task<MyIdentity> IdentityAsync(CancellationToken ct = default);
    Task<(byte[] content, string fileName)> PhotoAsync(CancellationToken ct = default);

    /// <summary>أُغيّر صورتي بنفسي — **على بطاقتي أنا** (ADR-035).</summary>
    Task SetPhotoAsync(string fileName, byte[] content, CancellationToken ct = default);
    Task<List<EmployeeLeave>> MyLeavesAsync(CancellationToken ct = default);
    Task<EmployeeLeave> RequestLeaveAsync(LeaveRequestInput input, CancellationToken ct = default);
    Task CancelLeaveRequestAsync(int leaveId, CancellationToken ct = default);
    Task<List<MyPayslip>> MyPayslipsAsync(int? year, CancellationToken ct = default);
    Task<byte[]> MyReceiptAsync(int periodId, CancellationToken ct = default);
}

/// <summary>
/// البروفايل الشخصي — **كل نقطةٍ هنا تخصّ صاحب الطلب وحده** (ADR-033).
/// </summary>
/// <remarks>
/// 🔴 **الحارس الوحيد هو <see cref="RequireLinkAsync"/>، ولذلك لا تحتاج هذه الخدمة قسماً
/// ولا دوراً:** لا نقطةَ هنا تقبل معرّف موظفٍ من العميل — الموظف **يُشتقّ** من
/// <c>Employee.UserId == current.UserId</c> داخل الشركة الفعّالة. فمن لا بطاقةَ له لا يرى
/// شيئاً، ومن له بطاقةٌ لا يرى إلا بطاقته.
///
/// 🔴 **وأيّ نقطةٍ تُضاف هنا وتقبل معرّفاً من الخارج تُبطل الوحدة كلَّها** — لأن الحارس
/// الوحيد يصير حينئذٍ مُلتَفّاً عليه. المعرّفات المقبولة هنا (<c>leaveId</c> ·
/// <c>periodId</c>) **تُفلتَر كلُّها بإسنادي** قبل أن يُقرأ منها شيء.
///
/// ⚠️ **ولا فحصَ لـ<see cref="AppModule"/> عمداً**: قسم «الرواتب» يفتح رواتب **الشركة**،
/// وهذا المسار يفتح **راتبك أنت** — واشتراطُ الأول للثاني يعني أن الموظف لا يرى راتبه إلا
/// إذا رأى رواتب زملائه، وهو عكس المقصود تماماً.
///
/// ⚠️ **والقارئ يدخل هنا**: حدّ «فوق القارئ» في <c>[RequireHrModule]</c> يحمي بيانات
/// **الغير**، ولا معنى لحجب بيانات المرء عن نفسه بسبب دوره.
/// </remarks>
public sealed class ProfileService(
    AppDbContext db, ICurrentUser current, IAuditService audit, IFileStorage storage) : IProfileService
{
    /// <summary>أقصى مدّة لطلبٍ واحد — حارسُ إدخالٍ لا سياسةُ إجازات.</summary>
    private const int MaxRequestDays = 365;

    public async Task<MyIdentity> IdentityAsync(CancellationToken ct = default)
    {
        var userId = RequireUserId();

        // ⚠️ تجاوزُ الفلتر مقصود وآمن: الشرط `UserId == userId` **هو** العزل — لا يُقرأ
        //    إلا صفّ صاحب الجلسة. والفلتر العام على `User` يمرّ بالشركات المُسندة، فقد
        //    يحجب المستخدمَ عن نفسه لحظة تبديل شركةٍ لم تُسنَد له بعد.
        var user = await db.Users.IgnoreQueryFilters()
                       .FirstOrDefaultAsync(u => u.UserId == userId, ct)
                   ?? throw new NotFoundException("الحساب غير موجود.");

        var companyId = current.ActiveCompanyId;
        var companyName = companyId is { } cid
            ? await db.Companies.IgnoreQueryFilters()
                .Where(c => c.CompanyId == cid).Select(c => c.Name).FirstOrDefaultAsync(ct)
            : null;

        var departmentName = current.DepartmentId is { } did
            ? await db.Departments.IgnoreQueryFilters()
                .Where(d => d.DepartmentId == did).Select(d => d.Name).FirstOrDefaultAsync(ct)
            : null;

        // البطاقة اختيارية — غيابُها حالةٌ عاديّة لا خطأ.
        var link = await FindLinkAsync(ct);
        var emp = link?.Employee;

        return new MyIdentity(
            user.UserId, user.FullName, user.Username, user.Role,
            companyName, departmentName,
            emp?.EmployeeId, emp?.FullName, emp?.FullNameEn,
            link?.Position, link?.HireDate, emp?.NationalId, emp?.Phone, emp?.Address,
            !string.IsNullOrEmpty(emp?.PhotoBlobKey));
    }

    public async Task<(byte[] content, string fileName)> PhotoAsync(CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);
        var key = link.Employee?.PhotoBlobKey;
        if (string.IsNullOrEmpty(key)) throw new NotFoundException("لا توجد صورة في ملفّك.");
        var bytes = await storage.ReadAsync(key, ct);
        return (bytes, Path.GetFileName(key));
    }

    /// <remarks>
    /// 🔴 **قرار المالك (2026-08-19) يعكس شرطاً من ADR-033**: الصورة صار يغيّرها صاحبها.
    /// و**الصورة تبقى واحدة**: تُكتب على `Employee.PhotoBlobKey` نفسه بالمفتاح نفسه، فما
    /// يراه في بروفايله هو ما تراه شؤون الموظفين في بطاقته — لا صورةَ حسابٍ ثانية بجانب
    /// الصورة الرسمية. (مبدأ «صورةٌ واحدة للشخص» **باقٍ**؛ المتغيّر مَن يملك تحديثها.)
    ///
    /// 🔐 **ولا معرّفَ من العميل**: البطاقة تُشتقّ من <see cref="RequireLinkAsync"/> كبقية
    /// نقاط الوحدة — فمن لا بطاقةَ له يُردّ عليه، ولا يكتب أحدٌ على صورة غيره.
    ///
    /// ⚠️ **وفعلٌ مستقلٌّ في سجلّ التدقيق** (<c>SetOwnPhoto</c> لا <c>SetPhoto</c>): مَن
    /// يقرأ السجلّ يحتاج أن يميّز صورةً وضعتها شؤون الموظفين من صورةٍ وضعها صاحبها.
    /// </remarks>
    public async Task SetPhotoAsync(string fileName, byte[] content, CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);
        var emp = link.Employee ?? throw new NotFoundException("بطاقتك غير موجودة.");

        var ext = EmployeePhotoRules.Validate(fileName, content.Length);

        var old = emp.PhotoBlobKey;
        emp.PhotoBlobKey = await storage.SaveAsync(
            EmployeePhotoRules.BlobKey(emp.EmployeeId, ext), content, ct);

        audit.Add("SetOwnPhoto", nameof(Employee), emp.EmployeeId.ToString(),
            null, current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);

        // بعد نجاح الحفظ لا قبله — فلا تضيع القديمة إن فشلت الكتابة (نظير `EmployeeService`).
        if (!string.IsNullOrEmpty(old) && old != emp.PhotoBlobKey)
            try { await storage.DeleteAsync(old, ct); } catch { /* تجاهل فشل حذف */ }
    }

    public async Task<List<EmployeeLeave>> MyLeavesAsync(CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);
        return await db.EmployeeLeaves
            .Where(l => l.EmployeeCompanyId == link.EmployeeCompanyId)
            .OrderByDescending(l => l.FromDate)
            .ToListAsync(ct);
    }

    /// <summary>طلب إجازةٍ لنفسي — **معلّقةٌ دائماً وبلا حسمٍ مقرَّر** (ADR-033).</summary>
    /// <remarks>
    /// 🔴 **ثلاثة فروق جوهرية عن <c>LeaveService.CreateAsync</c>، وكلٌّ منها مقصود:**
    /// <list type="number">
    /// <item><b>بلا <c>CanManageEmployees</c></b> — وإلا لما استطاع موظفٌ طلب إجازته.</item>
    /// <item><b><c>RequiresApproval</c> مفروضةٌ <c>true</c> ولا تُقرأ من العميل</b> — ولو
    /// قُرئت لمنح الموظف نفسه إجازةً مقبولةً فور تسجيلها.</item>
    /// <item><b><c>DeductFromSalary = false</c> ابتداءً و<c>IsSelfRequested = true</c></b> —
    /// الحسم قرارُ المراجع، والعلَم يخبره أن القرار **لم يُتَّخذ بعد**.</item>
    /// </list>
    /// ⚠️ **وحارس التداخل نفسه يسري** — نسخةٌ من قاعدة <c>LeaveService</c> لا استثناء منها:
    /// إجازتان متداخلتان خطأُ إدخالٍ سواءٌ طلبها صاحبها أو سجّلها له غيره.
    /// </remarks>
    public async Task<EmployeeLeave> RequestLeaveAsync(
        LeaveRequestInput input, CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);

        if (input.ToDate.Date < input.FromDate.Date)
            throw new ValidationException("تاريخ نهاية الإجازة لا يسبق بدايتها.");

        var days = (input.ToDate.Date - input.FromDate.Date).Days + 1;
        if (days > MaxRequestDays)
            throw new ValidationException($"مدّة الطلب الواحد لا تتجاوز {MaxRequestDays} يوماً.");

        var overlaps = await db.EmployeeLeaves.AnyAsync(l =>
            l.EmployeeCompanyId == link.EmployeeCompanyId &&
            l.Status != LeaveStatus.Rejected &&
            l.FromDate <= input.ToDate.Date && l.ToDate >= input.FromDate.Date, ct);
        if (overlaps)
            throw new ConflictException("لديك إجازة مسجَّلة تتداخل مع هذه المدّة.");

        var leave = new EmployeeLeave
        {
            EmployeeCompanyId = link.EmployeeCompanyId,
            CompanyId = link.CompanyId,
            LeaveType = input.LeaveType,
            FromDate = input.FromDate.Date,
            ToDate = input.ToDate.Date,
            DurationDays = days,
            RequiresApproval = true,                       // مفروضة — لا تُقرأ من العميل
            Status = LeaveDecision.SelfRequestStatus,      // معلّقةٌ دائماً
            DeductFromSalary = false,                      // **غيابُ قرار** لا قرار
            IsSelfRequested = true,
            Notes = string.IsNullOrWhiteSpace(input.Notes) ? null : input.Notes.Trim(),
            CreatedByUserId = current.UserId ?? 0,
            CreatedAt = DateTime.UtcNow,
        };
        db.EmployeeLeaves.Add(leave);

        db.EmployeeLogs.Add(new EmployeeLog
        {
            EmployeeCompanyId = link.EmployeeCompanyId,
            CompanyId = link.CompanyId,
            ChangeType = EmployeeChangeType.LeaveRecorded,
            Description = $"طلب الموظف إجازة {LeaveService.ArabicLeave(input.LeaveType)} " +
                          $"{days} يوماً ({input.FromDate:yyyy-MM-dd} → {input.ToDate:yyyy-MM-dd})",
            ChangedByUserId = current.UserId ?? 0,
            ChangedAt = DateTime.UtcNow,
        });

        audit.Add("RequestLeave", nameof(EmployeeLeave), link.EmployeeId.ToString(),
            $"{LeaveService.ArabicLeave(input.LeaveType)} {days} يوماً", link.CompanyId);
        await db.SaveChangesAsync(ct);
        return leave;
    }

    /// <summary>سحب طلبي **قبل بتّه** — وبعد البتّ يبقى سجلّاً لا يُمحى.</summary>
    /// <remarks>
    /// ⚠️ **ثلاثة شروط معاً**: أن يكون في إسنادي أنا، وأن يكون **ذاتيّاً**
    /// (<c>IsSelfRequested</c>)، وأن يكون **معلّقاً**. بدون الثاني يمحو الموظف إجازةً سجّلها
    /// عليه كاتب الشؤون — وهي **واقعةٌ حصلت** لا طلبٌ ينتظر. وبدون الثالث يسحب إجازةً
    /// موافَقاً عليها بعد أن بُني عليها كشفُ الشهر.
    /// </remarks>
    public async Task CancelLeaveRequestAsync(int leaveId, CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);

        var leave = await db.EmployeeLeaves.FirstOrDefaultAsync(
                        l => l.LeaveId == leaveId
                          && l.EmployeeCompanyId == link.EmployeeCompanyId, ct)
                    ?? throw new NotFoundException("الطلب غير موجود.");

        // القاعدة في `LeaveDecision.CanSelfCancel`؛ والرسالتان تفرّقان السببين للمستخدم.
        if (!leave.IsSelfRequested)
            throw new ForbiddenException("هذه إجازة مسجَّلة في ملفّك ولا تُسحب — راجع شؤون الموظفين.");
        if (!LeaveDecision.CanSelfCancel(leave.IsSelfRequested, leave.Status))
            throw new ConflictException("الطلب بُتّ فيه — لا يمكن سحبه.");

        leave.IsDeleted = true;
        leave.DeletedByUserId = current.UserId;
        leave.DeletedAt = DateTime.UtcNow;

        audit.Add("CancelLeaveRequest", nameof(EmployeeLeave), leaveId.ToString(),
            null, link.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    /// <summary>رواتبي — **الأشهر المُسدَّدة وحدها**.</summary>
    /// <remarks>
    /// 🔴 **لماذا لا تُعرض المسودّات؟** لأن سطر المسودّة رقمٌ **غير نهائيّ** يتغيّر بتحرير
    /// المحاسب وبسعر الصرف وبأيام الغياب. وعرضُه للموظف يُنشئ توقّعاً برقمٍ لم يُقرَّر، ثم
    /// يقبض غيرَه — فيصير النظام مصدرَ نزاعٍ بدل أن يكون مصدر ثقة.
    ///
    /// ⚠️ **و«صُرف من شركة أخرى» يُعرض ولا يُخفى**: الموظف قبض راتبه فعلاً من الشركة
    /// الشقيقة، وإخفاءُ السطر يجعله يظنّ شهرَه ضائعاً. يُعرض **بحالته مكتوبةً** — وهو
    /// مبدأ <c>PayrollPayable.ExcludedIqd</c> نفسه: يُعرض ولا يُطرح صامتاً.
    /// </remarks>
    public async Task<List<MyPayslip>> MyPayslipsAsync(int? year, CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);

        var q = db.PayrollEntries
            .Include(e => e.Period)
            .Where(e => e.EmployeeCompanyId == link.EmployeeCompanyId
                     && e.Period!.Status == PayrollStatus.Paid);

        if (year is { } y) q = q.Where(e => e.Period!.Year == y);

        var rows = await q
            .OrderByDescending(e => e.Period!.Year).ThenByDescending(e => e.Period!.Month)
            .ToListAsync(ct);

        return rows.Select(e => new MyPayslip(
            e.PeriodId, e.Period!.Year, e.Period.Month,
            PayrollCalculator.ArabicMonth(e.Period.Month),
            e.SnapshotBaseSalary, e.EligibleDays, e.Period.WorkingDays, e.AbsenceDays,
            e.AbsenceDeduction, e.BonusAmount, e.DeductionAmount,
            e.NetSalary, e.NetSalaryIqd, e.SnapshotCurrency,
            e.PaymentStatus, ArabicPaymentStatus(e.PaymentStatus), e.Period.PaidAt)).ToList();
    }

    /// <summary>إيصال راتبي لشهرٍ مُسدَّد — بلغة إيصالي المحفوظة.</summary>
    /// <remarks>
    /// 🔴 **لا إيصال لِما لم تصرفه هذه الشركة** — القاعدة نفسها في
    /// <c>PayrollController.Receipts</c> (ADR-028): الإيصال إقرارٌ بالاستلام، وطبعُه لشهرٍ
    /// صرفته شركةٌ أخرى يُنتج مستنداً يشهد بما لم يقع هنا.
    /// </remarks>
    public async Task<byte[]> MyReceiptAsync(int periodId, CancellationToken ct = default)
    {
        var link = await RequireLinkAsync(ct);

        var entry = await db.PayrollEntries.Include(e => e.Period)
                        .FirstOrDefaultAsync(e => e.PeriodId == periodId
                                               && e.EmployeeCompanyId == link.EmployeeCompanyId, ct)
                    ?? throw new NotFoundException("لا يوجد راتب لك في هذا الشهر.");

        if (entry.Period!.Status != PayrollStatus.Paid)
            throw new ValidationException("لم يُسدَّد هذا الشهر بعد.");

        if (!PayrollPayable.Includes(entry.PaymentStatus))
            throw new ValidationException(
                "راتب هذا الشهر مدفوع من شركة أخرى — الإيصال يصدر من الشركة التي صرفته.");

        var companyName = await db.Companies.IgnoreQueryFilters()
            .Where(c => c.CompanyId == link.CompanyId).Select(c => c.Name)
            .FirstOrDefaultAsync(ct) ?? "";

        var emp = link.Employee;
        var english = emp?.ReceiptLanguage == ReceiptLanguage.English;
        var name = english ? emp?.FullNameEn ?? entry.SnapshotName : entry.SnapshotName;
        var position = english ? link.PositionEn ?? entry.SnapshotPosition : entry.SnapshotPosition;

        var foreign = entry.SnapshotCurrency == Currency.USD
            ? $"{entry.NetSalary:N2} {(english ? "USD" : "دولار أمريكي")}"
            : null;

        return SalaryReceiptPdf.Generate([new SalaryReceiptModel(
            companyName, name, position,
            english ? PayrollCalculator.EnglishMonth(entry.Period.Month)
                    : PayrollCalculator.ArabicMonth(entry.Period.Month),
            entry.Period.Year, $"{entry.NetSalaryIqd:N0}", foreign,
            DateTime.Now.ToString("yyyy-MM-dd"), english)]);
    }

    // ─────────────────────────── الحارس ───────────────────────────

    private int RequireUserId() =>
        current.UserId ?? throw new ForbiddenException("لا جلسة مصادَقة.");

    /// <summary>
    /// **الحارس الوحيد**: بطاقتي في الشركة الفعّالة، مشتقّةً من الجلسة لا من العميل.
    /// </summary>
    /// <remarks>
    /// ⚠️ **لماذا خطوتان لا استعلامٌ واحد بخاصية تنقّل؟** لأن الفلتر العام على
    /// <see cref="Employee"/> يمرّ بـ<c>Companies.Any(...)</c>، فقراءةُ <c>e.UserId</c> عبر
    /// <c>EmployeeCompanies</c> تُركّب فلترين متداخلين يصعب البرهان على تكافئهما.
    /// الخطوتان صريحتان: **مَن أنا** ثم **إسنادي في هذه الشركة**.
    /// </remarks>
    private async Task<EmployeeCompany?> FindLinkAsync(CancellationToken ct)
    {
        var userId = current.UserId;
        if (userId is null || current.ActiveCompanyId is not { } companyId) return null;

        // الفلتر العام على `Employees` يقصر النتيجة على موظفي الشركة الفعّالة أصلاً،
        // وشرط `CompanyId` أدناه يختار **إسناد هذه الشركة** لمن يعمل في أكثر من واحدة.
        var employeeId = await db.Employees
            .Where(e => e.UserId == userId).Select(e => (int?)e.EmployeeId)
            .FirstOrDefaultAsync(ct);
        if (employeeId is null) return null;

        return await db.EmployeeCompanies.Include(x => x.Employee)
            .FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.CompanyId == companyId, ct);
    }

    private async Task<EmployeeCompany> RequireLinkAsync(CancellationToken ct)
    {
        RequireUserId();
        if (current.ActiveCompanyId is null)
            throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");

        return await FindLinkAsync(ct)
               ?? throw new NotFoundException(
                   "حسابك غير مرتبط ببطاقة موظف في هذه الشركة — راجع شؤون الموظفين.");
    }

    internal static string ArabicPaymentStatus(PayrollPaymentStatus s) => s switch
    {
        PayrollPaymentStatus.PaidByThisCompany => "مصروف",
        PayrollPaymentStatus.PaidByOtherCompany => "مصروف من شركة أخرى",
        PayrollPaymentStatus.ConfirmedByThisCompany => "مقرَّر الصرف من هنا",
        _ => "غير مصروف",
    };
}
