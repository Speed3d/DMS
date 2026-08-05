using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Hr;

// ─────────────────────────── المدخلات ───────────────────────────

/// <summary>بيانات الموظف الشخصية (لا تخصّ شركة بعينها).</summary>
public sealed record EmployeeProfileInput(
    string FullName, string? FullNameEn, string? NationalId, string? Phone,
    string? Address, string? Notes, ReceiptLanguage ReceiptLanguage);

/// <summary>شروط العمل في شركة واحدة.</summary>
public sealed record EmploymentInput(
    string Position, string? PositionEn, DateTime HireDate,
    Currency SalaryCurrency, decimal BaseSalary, int DisplayOrder, bool IsActive = true);

public sealed record TerminationInput(DateTime TerminationDate, TerminationReason Reason, string? Notes);

/// <summary>نتيجة البحث برقم الهوية — **الحدّ الأدنى الذي يكفي لاتخاذ القرار، لا أكثر**.</summary>
public sealed record ExistingEmployeeHint(int EmployeeId, string FullName, bool AlreadyInThisCompany);

public interface IEmployeeService
{
    Task<List<EmployeeCompany>> ListAsync(bool? activeOnly, string? search, CancellationToken ct = default);
    Task<Employee> GetAsync(int employeeId, CancellationToken ct = default);
    Task<Employee> CreateAsync(EmployeeProfileInput profile, EmploymentInput employment, CancellationToken ct = default);
    Task<Employee> UpdateProfileAsync(int employeeId, EmployeeProfileInput profile, CancellationToken ct = default);
    Task<EmployeeCompany> UpsertEmploymentAsync(int employeeId, EmploymentInput employment, CancellationToken ct = default);
    Task TerminateAsync(int employeeId, TerminationInput input, CancellationToken ct = default);
    Task DeleteAsync(int employeeId, CancellationToken ct = default);
    Task SetPhotoAsync(int employeeId, string fileName, byte[] content, CancellationToken ct = default);
    Task<(byte[] content, string fileName)> GetPhotoAsync(int employeeId, CancellationToken ct = default);
    Task<ExistingEmployeeHint?> LookupByNationalIdAsync(string nationalId, CancellationToken ct = default);
    Task<List<PayrollEntry>> SalaryHistoryAsync(int employeeId, int take, CancellationToken ct = default);
}

/// <summary>
/// إدارة الموظفين (ADR-023). العزل بين الشركات يفرضه الفلتر العام على <see cref="Employee"/>
/// و<see cref="EmployeeCompany"/>، وهذه الخدمة تفرض فوقه **صلاحية الكتابة**.
/// </summary>
public sealed class EmployeeService(
    AppDbContext db, ICurrentUser current, IAuditService audit, IFileStorage storage) : IEmployeeService
{
    private const long MaxPhotoBytes = 5 * 1024 * 1024;
    private static readonly string[] PhotoExtensions = [".jpg", ".jpeg", ".png"];

    public async Task<List<EmployeeCompany>> ListAsync(
        bool? activeOnly, string? search, CancellationToken ct = default)
    {
        // الفلتر العام يقصر النتيجة على الشركة الفعّالة — لا حاجة لشرط CompanyId هنا.
        var q = db.EmployeeCompanies.Include(x => x.Employee).AsQueryable();

        if (activeOnly is true) q = q.Where(x => x.IsActive && x.TerminationDate == null);
        else if (activeOnly is false) q = q.Where(x => !x.IsActive || x.TerminationDate != null);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(x => x.Employee!.FullName.Contains(s)
                          || (x.Employee.FullNameEn != null && x.Employee.FullNameEn.Contains(s))
                          || (x.Employee.NationalId != null && x.Employee.NationalId.Contains(s))
                          || x.Position.Contains(s));
        }

        return await q.OrderBy(x => x.DisplayOrder).ThenBy(x => x.Employee!.FullName).ToListAsync(ct);
    }

    public async Task<Employee> GetAsync(int employeeId, CancellationToken ct = default)
    {
        // ⚠️ `Companies` تُحمَّل عبر الفلتر العام لـEmployeeCompany ⇒ **إسنادات الشركة الفعّالة
        //    وحدها**. لولاه لكشف هذا السطر راتب الموظف في شركة أخرى لمن لا شأن له بها.
        var emp = await db.Employees.Include(e => e.Companies)
                      .FirstOrDefaultAsync(e => e.EmployeeId == employeeId, ct)
                  ?? throw new NotFoundException("الموظف غير موجود أو لا تملك صلاحية رؤيته.");
        return emp;
    }

    public async Task<Employee> CreateAsync(
        EmployeeProfileInput profile, EmploymentInput employment, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        ValidateProfile(profile);
        ValidateEmployment(employment);
        await EnsureNationalIdFreeAsync(profile.NationalId, null, ct);

        var emp = new Employee
        {
            FullName = profile.FullName.Trim(),
            FullNameEn = Clean(profile.FullNameEn),
            NationalId = Clean(profile.NationalId),
            Phone = Clean(profile.Phone),
            Address = Clean(profile.Address),
            Notes = Clean(profile.Notes),
            ReceiptLanguage = profile.ReceiptLanguage,
            CreatedByUserId = current.UserId,
            CreatedAt = DateTime.UtcNow,
        };
        emp.Companies.Add(BuildEmployment(new EmployeeCompany { CompanyId = companyId }, employment, isNew: true));

        db.Employees.Add(emp);
        audit.Add("Create", nameof(Employee), null, $"إضافة موظف {emp.FullName}", companyId);
        await db.SaveChangesAsync(ct);
        return emp;
    }

    public async Task<Employee> UpdateProfileAsync(
        int employeeId, EmployeeProfileInput profile, CancellationToken ct = default)
    {
        RequireWrite();
        ValidateProfile(profile);

        var emp = await GetAsync(employeeId, ct);
        await EnsureNationalIdFreeAsync(profile.NationalId, employeeId, ct);

        emp.FullName = profile.FullName.Trim();
        emp.FullNameEn = Clean(profile.FullNameEn);
        emp.NationalId = Clean(profile.NationalId);
        emp.Phone = Clean(profile.Phone);
        emp.Address = Clean(profile.Address);
        emp.Notes = Clean(profile.Notes);
        emp.ReceiptLanguage = profile.ReceiptLanguage;

        audit.Add("Update", nameof(Employee), employeeId.ToString(), emp.FullName, current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);
        return emp;
    }

    /// <summary>
    /// ينشئ أو يحدّث شروط عمل الموظف **في الشركة الفعّالة**.
    /// </summary>
    /// <remarks>
    /// عمداً لا يقبل <c>companyId</c> من الطلب: الإسناد يجري دائماً للشركة الفعّالة، ومن أراد
    /// إسناد موظف لشركته الثانية **بدّل الشركة**. قبولُ معرّف شركة من العميل كان سيصير باباً
    /// خلفياً لكتابة صفوف في شركة لا يملكها المستخدم.
    /// </remarks>
    public async Task<EmployeeCompany> UpsertEmploymentAsync(
        int employeeId, EmploymentInput employment, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        ValidateEmployment(employment);

        // ⚠️ IgnoreQueryFilters مقصود: الموظف قد يكون في شركة أخرى وحدها، فالفلتر يُخفيه —
        //    وهو بالضبط ما نحتاج تجاوزه لنسنده إلى شركتنا (بعد أن دلّنا عليه البحث بالهوية).
        var exists = await db.Employees.IgnoreQueryFilters()
            .AnyAsync(e => e.EmployeeId == employeeId && !e.IsDeleted, ct);
        if (!exists) throw new NotFoundException("الموظف غير موجود.");

        var link = await db.EmployeeCompanies
            .FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.CompanyId == companyId, ct);

        var isNew = link is null;

        // لقطة ما قبل التعديل — منها يُكتب سجلّ التغييرات بنصٍّ يقرأه المحاسب لا بحقول خام.
        var oldSalary = link?.BaseSalary;
        var oldPosition = link?.Position;
        var oldActive = link?.IsActive;

        link = BuildEmployment(link ?? new EmployeeCompany { EmployeeId = employeeId, CompanyId = companyId },
            employment, isNew);

        if (isNew)
        {
            db.EmployeeCompanies.Add(link);
            AddLog(link, EmployeeChangeType.Created,
                $"إسناد للشركة بصفة «{link.Position}» وراتب {Money(link.BaseSalary)} {CurrencyName(link.SalaryCurrency)}");
        }
        else
        {
            if (oldSalary is { } os && os != link.BaseSalary)
                AddLog(link, EmployeeChangeType.SalaryChange,
                    $"تغيّر الراتب من {Money(os)} إلى {Money(link.BaseSalary)} {CurrencyName(link.SalaryCurrency)}",
                    Money(os), Money(link.BaseSalary));

            if (oldPosition is { } op && op != link.Position)
                AddLog(link, EmployeeChangeType.PositionChange,
                    $"تغيّرت الصفة من «{op}» إلى «{link.Position}»", op, link.Position);

            if (oldActive is { } oa && oa != link.IsActive)
                AddLog(link, EmployeeChangeType.HireStatusChange,
                    link.IsActive ? "أُعيد إلى رأس العمل" : "أُوقف مؤقتاً");
        }

        audit.Add(isNew ? "AssignEmployee" : "UpdateEmployment", nameof(EmployeeCompany),
            employeeId.ToString(), $"{link.Position} — {link.BaseSalary} {link.SalaryCurrency}", companyId);
        await db.SaveChangesAsync(ct);
        return link;
    }

    public async Task TerminateAsync(int employeeId, TerminationInput input, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();

        var link = await db.EmployeeCompanies
                       .FirstOrDefaultAsync(x => x.EmployeeId == employeeId && x.CompanyId == companyId, ct)
                   ?? throw new NotFoundException("الموظف غير مُسنَد لهذه الشركة.");

        if (input.TerminationDate.Date < link.HireDate.Date)
            throw new ValidationException("تاريخ إنهاء الخدمة لا يسبق تاريخ التعيين.");

        link.TerminationDate = input.TerminationDate.Date;
        link.TerminationReason = input.Reason;
        link.TerminationNotes = Clean(input.Notes);
        link.IsActive = false;
        link.UpdatedAt = DateTime.UtcNow;

        AddLog(link, EmployeeChangeType.TerminationRecorded,
            $"إنهاء الخدمة بتاريخ {input.TerminationDate:yyyy-MM-dd} ({ArabicReason(input.Reason)})");

        audit.Add("Terminate", nameof(EmployeeCompany), employeeId.ToString(),
            $"إنهاء خدمة بتاريخ {input.TerminationDate:yyyy-MM-dd} ({input.Reason})", companyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(int employeeId, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        var emp = await GetAsync(employeeId, ct);

        // سطرٌ في كشف **مُسدَّد** سجلٌّ مالي — حذف الموظف لا يجوز أن يُفقده سنده.
        var paid = await db.PayrollEntries
            .AnyAsync(e => e.EmployeeCompany!.EmployeeId == employeeId
                        && e.Period!.Status == PayrollStatus.Paid, ct);
        if (paid)
            throw new ConflictException(
                "لا يمكن حذف موظف له رواتب مُسدَّدة — استخدم «إنهاء الخدمة» بدلاً من الحذف.");

        var now = DateTime.UtcNow;
        emp.IsDeleted = true;
        emp.DeletedByUserId = current.UserId;
        emp.DeletedAt = now;
        foreach (var link in emp.Companies)
        {
            link.IsDeleted = true;
            link.DeletedByUserId = current.UserId;
            link.DeletedAt = now;
        }

        audit.Add("Delete", nameof(Employee), employeeId.ToString(), emp.FullName, companyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task SetPhotoAsync(int employeeId, string fileName, byte[] content, CancellationToken ct = default)
    {
        RequireWrite();
        var emp = await GetAsync(employeeId, ct);

        if (content.Length == 0) throw new ValidationException("الملف فارغ.");
        if (content.Length > MaxPhotoBytes) throw new ValidationException("حجم الصورة يتجاوز 5 ميغابايت.");
        var ext = Path.GetExtension(fileName).ToLowerInvariant();
        if (!PhotoExtensions.Contains(ext)) throw new ValidationException("صيغة الصورة غير مسموحة (JPG/PNG).");

        var old = emp.PhotoBlobKey;
        emp.PhotoBlobKey = await storage.SaveAsync($"emp-{employeeId}{ext}", content, ct);

        audit.Add("SetPhoto", nameof(Employee), employeeId.ToString(), null, current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);

        // بعد نجاح الحفظ لا قبله — فلا نفقد الصورة القديمة إن فشلت الكتابة.
        if (!string.IsNullOrEmpty(old))
            try { await storage.DeleteAsync(old, ct); } catch { /* تجاهل فشل حذف */ }
    }

    public async Task<(byte[] content, string fileName)> GetPhotoAsync(int employeeId, CancellationToken ct = default)
    {
        var emp = await GetAsync(employeeId, ct);
        if (string.IsNullOrEmpty(emp.PhotoBlobKey)) throw new NotFoundException("لا توجد صورة لهذا الموظف.");
        var bytes = await storage.ReadAsync(emp.PhotoBlobKey, ct);
        return (bytes, Path.GetFileName(emp.PhotoBlobKey));
    }

    /// <summary>
    /// البحث عن موظف قائم برقم هويته — **الجسر الوحيد بين الشركات** في هذه الخدمة.
    /// </summary>
    /// <remarks>
    /// ⚠️ **تجاوزٌ متعمَّد للفلتر العام** بلا بديل: موظفٌ يعمل في «أرض العرين» وحدها **مخفيٌّ
    /// تماماً** عن مستخدم «بوغوصيان»، فلو لم يوجد هذا الباب لأنشأ المستخدم **ملفاً ثانياً**
    /// لنفس الشخص — وهو ما بُني الكيان العابر للشركات كله ليمنعه.
    ///
    /// والكشف **مقصورٌ على أقلّ ما يكفي للقرار**: الاسم فقط. لا راتب ولا صفة ولا اسم الشركة
    /// الأخرى ولا تاريخ تعيين — ومَن يبحث يعرف رقم الهوية أصلاً.
    /// </remarks>
    public async Task<ExistingEmployeeHint?> LookupByNationalIdAsync(
        string nationalId, CancellationToken ct = default)
    {
        RequireWrite();
        var companyId = RequireCompany();
        if (string.IsNullOrWhiteSpace(nationalId)) return null;
        var id = nationalId.Trim();

        var emp = await db.Employees.IgnoreQueryFilters()
            .Where(e => e.NationalId == id && !e.IsDeleted)
            .Select(e => new { e.EmployeeId, e.FullName })
            .FirstOrDefaultAsync(ct);
        if (emp is null) return null;

        var here = await db.EmployeeCompanies.IgnoreQueryFilters()
            .AnyAsync(x => x.EmployeeId == emp.EmployeeId && x.CompanyId == companyId && !x.IsDeleted, ct);

        return new ExistingEmployeeHint(emp.EmployeeId, emp.FullName, here);
    }

    public async Task<List<PayrollEntry>> SalaryHistoryAsync(
        int employeeId, int take, CancellationToken ct = default)
    {
        await GetAsync(employeeId, ct); // حارس الرؤية
        return await db.PayrollEntries
            .Include(e => e.Period)
            .Where(e => e.EmployeeCompany!.EmployeeId == employeeId)
            .OrderByDescending(e => e.Period!.Year).ThenByDescending(e => e.Period!.Month)
            .Take(take)
            .ToListAsync(ct);
    }

    // ─────────────────────────── مساعدات ───────────────────────────

    private static EmployeeCompany BuildEmployment(EmployeeCompany link, EmploymentInput i, bool isNew)
    {
        link.Position = i.Position.Trim();
        link.PositionEn = Clean(i.PositionEn);
        link.HireDate = i.HireDate.Date;
        link.SalaryCurrency = i.SalaryCurrency;
        link.BaseSalary = i.BaseSalary;
        link.DisplayOrder = i.DisplayOrder;
        link.IsActive = i.IsActive;
        if (isNew) link.CreatedAt = DateTime.UtcNow;
        else link.UpdatedAt = DateTime.UtcNow;
        return link;
    }

    private static void ValidateProfile(EmployeeProfileInput p)
    {
        if (string.IsNullOrWhiteSpace(p.FullName))
            throw new ValidationException("اسم الموظف مطلوب.");
        if (p.ReceiptLanguage == ReceiptLanguage.English && string.IsNullOrWhiteSpace(p.FullNameEn))
            throw new ValidationException("الاسم بالإنجليزية مطلوب لمن لغة إيصاله إنجليزية.");
    }

    private static void ValidateEmployment(EmploymentInput e)
    {
        if (string.IsNullOrWhiteSpace(e.Position))
            throw new ValidationException("صفة الموظف مطلوبة.");
        if (e.BaseSalary < 0)
            throw new ValidationException("الراتب الأساسي لا يكون سالباً.");
        if (e.HireDate == default)
            throw new ValidationException("تاريخ التعيين مطلوب.");
    }

    /// <summary>يمنع ملفّين لشخص واحد. يتجاوز الفلتر عمداً — التفرّد عالميٌّ لا داخل الشركة.</summary>
    private async Task EnsureNationalIdFreeAsync(string? nationalId, int? exceptId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(nationalId)) return;
        var id = nationalId.Trim();
        var taken = await db.Employees.IgnoreQueryFilters()
            .AnyAsync(e => e.NationalId == id && !e.IsDeleted && (exceptId == null || e.EmployeeId != exceptId), ct);
        if (taken)
            throw new ConflictException("رقم الهوية مسجَّل لموظف آخر — ابحث عنه وأسنِده لشركتك بدل إنشاء ملف ثانٍ.");
    }

    private void RequireWrite()
    {
        if (!current.CanManageEmployees)
            throw new ForbiddenException("لا تملك صلاحية إدارة بطاقات الموظفين.");
    }

    private int RequireCompany() =>
        current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة الفعّالة.");

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    /// <summary>سطر في سجلّ الموظف — نصٌّ عربي جاهز للعرض لا حقولٌ تُركَّب عند القراءة.</summary>
    private void AddLog(EmployeeCompany link, EmployeeChangeType type, string description,
        string? oldValue = null, string? newValue = null)
    {
        db.EmployeeLogs.Add(new EmployeeLog
        {
            EmployeeCompany = link,          // الإسناد قد يكون جديداً بلا مفتاح بعد
            EmployeeCompanyId = link.EmployeeCompanyId,
            CompanyId = link.CompanyId,
            ChangeType = type,
            Description = description,
            OldValue = oldValue,
            NewValue = newValue,
            ChangedByUserId = current.UserId ?? 0,
            ChangedAt = DateTime.UtcNow,
        });
    }

    private static string Money(decimal v) => v.ToString("#,0.##");

    private static string CurrencyName(Currency c) => c == Currency.USD ? "دولار" : "دينار";

    internal static string ArabicReason(TerminationReason r) => r switch
    {
        TerminationReason.Resignation => "استقالة",
        TerminationReason.Termination => "فصل",
        TerminationReason.Retirement => "تقاعد",
        TerminationReason.Death => "وفاة",
        _ => "أخرى",
    };
}
