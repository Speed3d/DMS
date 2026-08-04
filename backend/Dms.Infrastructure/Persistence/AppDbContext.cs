using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Persistence;

public class AppDbContext : DbContext
{
    /// <summary>حارس عزل: مستخدم مصادَق بلا شركة قابلة للتحديد ⇒ لا يرى أي صفّ (fail-closed).</summary>
    private const int NoCompanyId = -1;

    private readonly bool _filterByCompany;
    private readonly int _companyId;

    public AppDbContext(DbContextOptions<AppDbContext> options, ICurrentUser currentUser)
        : base(options)
    {
        // غير المصادَق (تسجيل الدخول) والسوبر أدمن بلا شركة فعّالة = بلا فلترة؛ غير ذلك = فلترة على شركته.
        if (!currentUser.IsAuthenticated || (currentUser.IsSuperAdmin && currentUser.ActiveCompanyId is null))
        {
            _filterByCompany = false;
            _companyId = 0;
        }
        else
        {
            _filterByCompany = true;
            _companyId = currentUser.ActiveCompanyId ?? NoCompanyId; // لا يرى شيئاً إن لم تُحدَّد شركته
        }
    }

    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Template> Templates => Set<Template>();
    public DbSet<User> Users => Set<User>();
    public DbSet<UserCompany> UserCompanies => Set<UserCompany>();
    public DbSet<ApprovalDelegation> ApprovalDelegations => Set<ApprovalDelegation>();
    public DbSet<Entity> Entities => Set<Entity>();
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<DocumentType> DocumentTypes => Set<DocumentType>();
    public DbSet<ExchangeRate> ExchangeRates => Set<ExchangeRate>();
    public DbSet<OutgoingBook> OutgoingBooks => Set<OutgoingBook>();
    public DbSet<ArchiveDoc> ArchiveDocs => Set<ArchiveDoc>();
    public DbSet<IncomingBook> IncomingBooks => Set<IncomingBook>();
    public DbSet<MovementLog> MovementLogs => Set<MovementLog>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<DocumentVersion> DocumentVersions => Set<DocumentVersion>();
    public DbSet<Counter> Counters => Set<Counter>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<BackupRecord> BackupRecords => Set<BackupRecord>();
    public DbSet<BackupSchedule> BackupSchedules => Set<BackupSchedule>();
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<EmployeeCompany> EmployeeCompanies => Set<EmployeeCompany>();
    public DbSet<PayrollPeriod> PayrollPeriods => Set<PayrollPeriod>();
    public DbSet<PayrollEntry> PayrollEntries => Set<PayrollEntry>();
    public DbSet<HrSettings> HrSettings => Set<HrSettings>();
    public DbSet<EmployeeLeave> EmployeeLeaves => Set<EmployeeLeave>();
    public DbSet<EmployeeLog> EmployeeLogs => Set<EmployeeLog>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        // ---- Company ----
        b.Entity<Company>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(200);
            e.Property(x => x.Prefix).IsRequired().HasMaxLength(20);
            e.HasIndex(x => x.Prefix).IsUnique();
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- Template ----
        b.Entity<Template>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(200);
            e.Property(x => x.PageSize).HasMaxLength(10);
            e.Property(x => x.FontFamily).HasMaxLength(100);
            e.HasOne(x => x.Company).WithMany(c => c.Templates)
                .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Restrict);
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- User ----
        b.Entity<User>(e =>
        {
            e.Property(x => x.FullName).IsRequired().HasMaxLength(200);
            e.Property(x => x.Username).IsRequired().HasMaxLength(100);
            e.Property(x => x.PasswordHash).IsRequired().HasMaxLength(200);
            e.HasIndex(x => x.Username).IsUnique();
            // العزل الصفّي: المستخدم يُرى ضمن شركته الرئيسية أو أي شركة مُسندة له.
            // (يُتجاوَز عمداً في تسجيل الدخول/فحص التفرّد عبر IgnoreQueryFilters.)
            e.HasQueryFilter(x => !_filterByCompany
                || x.CompanyId == _companyId
                || x.AssignedCompanies.Any(c => c.CompanyId == _companyId));
        });

        b.Entity<UserCompany>(e =>
        {
            e.HasIndex(x => new { x.UserId, x.CompanyId }).IsUnique();
            e.HasOne(x => x.User).WithMany(u => u.AssignedCompanies)
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);

            // قسم المستخدم في هذه الشركة — SetNull حتى لا يُمنع حذف قسم بسبب ارتباط مستخدم به (ADR-017).
            e.HasOne(x => x.Department).WithMany()
                .HasForeignKey(x => x.DepartmentId).OnDelete(DeleteBehavior.SetNull);
        });

        // ---- ApprovalDelegation ----
        b.Entity<ApprovalDelegation>(e =>
        {
            e.HasKey(x => x.DelegationId);
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- Entity (الجهة) ----
        b.Entity<Entity>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(300);
            e.HasIndex(x => new { x.CompanyId, x.Name });
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- DocumentType ----
        b.Entity<DocumentType>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(200);
            // اسم النوع فريد داخل الشركة الواحدة. الحارس في الـController يعطي رسالة عربية
            // واضحة، وهذا الفهرس يمنع التسابق (طلبان متزامنان بنفس الاسم يمرّان من الحارس معاً).
            e.HasIndex(x => new { x.CompanyId, x.Name }).IsUnique();
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- ExchangeRate (عام، بلا فلترة شركة) ----
        b.Entity<ExchangeRate>(e =>
        {
            e.Property(x => x.Rate).HasPrecision(18, 4);
            e.HasIndex(x => new { x.Currency, x.EffectiveDate });
        });

        // ---- OutgoingBook ----
        b.Entity<OutgoingBook>(e =>
        {
            e.HasKey(x => x.OutgoingId);
            e.Property(x => x.Subject).IsRequired().HasMaxLength(500);
            e.Property(x => x.Number).HasMaxLength(40);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.ExchangeRate).HasPrecision(18, 4);
            e.Property(x => x.AmountInIqd).HasPrecision(18, 2);
            e.Property(x => x.RowVersion).IsRowVersion();

            // رقم فريد لكل (شركة + سنة) + رقم رسمي فريد
            e.HasIndex(x => new { x.CompanyId, x.Year, x.SerialNo })
                .IsUnique().HasFilter("[SerialNo] IS NOT NULL");
            e.HasIndex(x => x.Number).IsUnique().HasFilter("[Number] IS NOT NULL");

            e.HasOne(x => x.Entity).WithMany()
                .HasForeignKey(x => x.EntityId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Template).WithMany()
                .HasForeignKey(x => x.TemplateId).OnDelete(DeleteBehavior.SetNull);

            e.HasOne(x => x.ReplyToIncoming).WithMany()
                .HasForeignKey(x => x.ReplyToIncomingId).OnDelete(DeleteBehavior.SetNull);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- IncomingBook ----
        b.Entity<IncomingBook>(e =>
        {
            e.HasKey(x => x.IncomingId);
            
            e.Property(x => x.IncomingNumber).HasMaxLength(40);
            e.Property(x => x.Subject).IsRequired().HasMaxLength(500);
            e.Property(x => x.ExternalNumber).HasMaxLength(100);
            e.Property(x => x.Keywords).HasMaxLength(1000);
            e.Property(x => x.LastAction).HasMaxLength(500);

            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.ExchangeRate).HasPrecision(18, 4);
            e.Property(x => x.AmountInIqd).HasPrecision(18, 2);

            e.HasIndex(x => new { x.CompanyId, x.Year, x.SerialNo })
                .IsUnique().HasFilter("[Year] IS NOT NULL AND [SerialNo] IS NOT NULL");
            e.HasIndex(x => x.IncomingNumber).IsUnique().HasFilter("[IncomingNumber] IS NOT NULL");

            e.HasOne(x => x.Entity).WithMany()
                .HasForeignKey(x => x.EntityId).OnDelete(DeleteBehavior.Restrict);

            e.HasOne(x => x.ReplyOutgoing).WithMany()
                .HasForeignKey(x => x.ReplyOutgoingId).OnDelete(DeleteBehavior.SetNull);

            e.HasIndex(x => x.EntityId);
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.ReceivedDate);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- IncomingAssignment (إحالة لعدة أقسام — ADR-018) ----
        b.Entity<IncomingAssignment>(e =>
        {
            e.HasKey(x => x.IncomingAssignmentId);
            e.Property(x => x.Note).HasMaxLength(1000);

            // فريد: إعادة الإحالة لقسم موجود تُحدّث ملاحظته ولا تُنشئ سطراً ثانياً.
            e.HasIndex(x => new { x.IncomingId, x.DepartmentId }).IsUnique();

            e.HasOne(x => x.Incoming).WithMany(b2 => b2.Assignments)
                .HasForeignKey(x => x.IncomingId).OnDelete(DeleteBehavior.Cascade);

            // Restrict: حذف قسم محال إليه كتب مرفوض أصلاً في DepartmentsController،
            // فلا نسمح بحذف صامت يُفقد الكتاب إسناده.
            e.HasOne(x => x.Department).WithMany()
                .HasForeignKey(x => x.DepartmentId).OnDelete(DeleteBehavior.Restrict);
        });

        // ---- Department (عزل صفّي حسب الشركة) ----
        b.Entity<Department>(e =>
        {
            e.HasKey(x => x.DepartmentId);
            e.Property(x => x.Name).IsRequired().HasMaxLength(150);
            e.HasIndex(x => new { x.CompanyId, x.Name }).IsUnique();
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- MovementLog ----
        b.Entity<MovementLog>(e =>
        {
            e.HasKey(x => x.MovementId);
            e.Property(x => x.Action).IsRequired().HasMaxLength(50);
            e.Property(x => x.Description).IsRequired().HasMaxLength(500);
            e.Property(x => x.FromDepartment).HasMaxLength(200);
            e.Property(x => x.ToDepartment).HasMaxLength(200);

            // العلاقة صريحة على IncomingId — بدونها يولّد EF عموداً شبحاً (IncomingBookIncomingId)
            // ويترك IncomingId = 0 عند الربط عبر خاصية التنقّل، فتُفقد الحركة من السجل.
            e.HasOne(x => x.IncomingBook).WithMany()
                .HasForeignKey(x => x.IncomingId).OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => x.IncomingId);
            e.HasIndex(x => x.PerformedAt);

            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- ArchiveDoc ----
        b.Entity<ArchiveDoc>(e =>
        {
            e.HasKey(x => x.ArchiveId);
            e.Property(x => x.Title).IsRequired().HasMaxLength(500);
            e.Property(x => x.ArchiveNumber).HasMaxLength(40);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.ExchangeRate).HasPrecision(18, 4);
            e.Property(x => x.AmountInIqd).HasPrecision(18, 2);
            e.Property(x => x.Keywords).HasMaxLength(1000);
            e.HasIndex(x => new { x.CompanyId, x.ArchiveNumber });
            // ⚠️ العلاقة تُضبط صراحةً: EF يولّد عموداً شبحاً إن تُركت ضمنية — حدث فعلاً مع
            //    `MovementLog → IncomingBook` فاختفت الحركات نهائياً. و`SetNull` مقصود:
            //    حذف قسم لا يجوز أن يمحو أضبارة، بل يتركها «بلا قسم».
            e.HasOne(x => x.Department).WithMany()
                .HasForeignKey(x => x.DepartmentId).OnDelete(DeleteBehavior.SetNull);
            e.HasIndex(x => new { x.CompanyId, x.DepartmentId });
            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- Attachment / DocumentVersion (وصول عبر المالك المفلتَر) ----
        b.Entity<Attachment>(e =>
        {
            e.Property(x => x.FileName).IsRequired().HasMaxLength(300);
            e.Property(x => x.BlobKey).IsRequired().HasMaxLength(400);
            e.Property(x => x.FileType).HasMaxLength(100);
            e.HasIndex(x => new { x.OwnerType, x.OwnerId });
        });

        b.Entity<DocumentVersion>(e =>
        {
            e.HasKey(x => x.VersionId);
            e.HasIndex(x => new { x.DocType, x.DocId, x.VersionNo });
        });

        // ---- Counter (مفتاح مركّب) ----
        b.Entity<Counter>(e =>
        {
            e.HasKey(x => new { x.CompanyId, x.Year, x.Type });
            e.Property(x => x.Type).HasMaxLength(20);
        });

        // ---- RefreshToken ----
        b.Entity<RefreshToken>(e =>
        {
            e.Property(x => x.TokenHash).IsRequired().HasMaxLength(100);
            e.HasIndex(x => x.TokenHash);
        });

        // ---- Backup (نظامي، بلا عزل شركة — السوبر أدمن فقط) ----
        b.Entity<BackupRecord>(e =>
        {
            e.Property(x => x.FileName).IsRequired().HasMaxLength(200);
            e.Property(x => x.Note).HasMaxLength(1000);
            e.HasIndex(x => x.CreatedAt);
        });
        b.Entity<BackupSchedule>();

        // ═══════════ الموظفون والرواتب (ADR-023) ═══════════

        // ---- Employee (عابر للشركات — العزل عبر الإسناد لا عبر عمود) ----
        b.Entity<Employee>(e =>
        {
            e.HasKey(x => x.EmployeeId);
            e.Property(x => x.FullName).IsRequired().HasMaxLength(200);
            e.Property(x => x.FullNameEn).HasMaxLength(200);
            e.Property(x => x.NationalId).HasMaxLength(50);
            e.Property(x => x.Phone).HasMaxLength(30);
            e.Property(x => x.Address).HasMaxLength(500);
            e.Property(x => x.PhotoBlobKey).HasMaxLength(500);
            e.Property(x => x.Notes).HasMaxLength(2000);

            // رقم الهوية فريد حين يوجد — يمنع تسجيل الشخص نفسه مرتين بملفّين منفصلين.
            e.HasIndex(x => x.NationalId).IsUnique()
                .HasFilter("[NationalId] IS NOT NULL AND [IsDeleted] = 0");

            // 🔐 **الفلتر الذي يقوم مقام CompanyId** — مرآةٌ لفلتر User أعلاه.
            //    بدونه يعود أي موظف في القاعدة لأي مستخدم مصادَق: هويةً وهاتفاً وعنواناً.
            //    وشرط `!c.IsDeleted` صريحٌ عمداً فلا يعتمد على ترتيب تركيب EF للفلاتر.
            e.HasQueryFilter(x => !x.IsDeleted
                && (!_filterByCompany || x.Companies.Any(c => c.CompanyId == _companyId && !c.IsDeleted)));
        });

        // ---- EmployeeCompany (شروط العمل في شركة بعينها) ----
        b.Entity<EmployeeCompany>(e =>
        {
            e.HasKey(x => x.EmployeeCompanyId);
            e.Property(x => x.Position).IsRequired().HasMaxLength(200);
            e.Property(x => x.PositionEn).HasMaxLength(200);
            e.Property(x => x.TerminationNotes).HasMaxLength(1000);
            e.Property(x => x.BaseSalary).HasPrecision(18, 2);

            // إسناد واحد لكل (موظف + شركة). الفلتر على المحذوف يسمح بإعادة الإسناد بعد الحذف الناعم.
            e.HasIndex(x => new { x.EmployeeId, x.CompanyId }).IsUnique()
                .HasFilter("[IsDeleted] = 0");
            e.HasIndex(x => new { x.CompanyId, x.IsActive, x.DisplayOrder });

            // ⚠️ صريحة لا ضمنية: العلاقة المتروكة ضمنيةً تولّد عموداً شبحاً — حدث فعلاً مع
            //    MovementLog → IncomingBook فاختفت الحركات نهائياً.
            e.HasOne(x => x.Employee).WithMany(p => p.Companies)
                .HasForeignKey(x => x.EmployeeId).OnDelete(DeleteBehavior.Cascade);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- PayrollPeriod (كشف شهر) ----
        b.Entity<PayrollPeriod>(e =>
        {
            e.HasKey(x => x.PeriodId);
            e.Property(x => x.ExchangeRate).HasPrecision(18, 4);
            e.Property(x => x.ManualBookNumber).HasMaxLength(100);
            e.Property(x => x.Notes).HasMaxLength(2000);
            e.Property(x => x.RowVersion).IsRowVersion();

            // كشف واحد لكل (شركة + سنة + شهر).
            e.HasIndex(x => new { x.CompanyId, x.Year, x.Month }).IsUnique()
                .HasFilter("[IsDeleted] = 0");

            // SetNull: حذف كتاب الصرف لا يجوز أن يمحو كشف رواتب شهر كامل.
            e.HasOne(x => x.OutgoingBook).WithMany()
                .HasForeignKey(x => x.OutgoingBookId).OnDelete(DeleteBehavior.SetNull);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- PayrollEntry (سطر موظف في الكشف) ----
        b.Entity<PayrollEntry>(e =>
        {
            e.HasKey(x => x.EntryId);
            e.Property(x => x.SnapshotName).IsRequired().HasMaxLength(200);
            e.Property(x => x.SnapshotPosition).IsRequired().HasMaxLength(200);
            e.Property(x => x.PaidByCompanyName).HasMaxLength(200);
            e.Property(x => x.Notes).HasMaxLength(1000);

            e.Property(x => x.SnapshotBaseSalary).HasPrecision(18, 2);
            e.Property(x => x.BonusAmount).HasPrecision(18, 2);
            e.Property(x => x.DeductionAmount).HasPrecision(18, 2);
            e.Property(x => x.AbsenceDeduction).HasPrecision(18, 2);
            e.Property(x => x.NetSalary).HasPrecision(18, 2);
            e.Property(x => x.NetSalaryIqd).HasPrecision(18, 2);

            e.HasIndex(x => new { x.PeriodId, x.EmployeeCompanyId }).IsUnique()
                .HasFilter("[IsDeleted] = 0");

            e.HasOne(x => x.Period).WithMany(p => p.Entries)
                .HasForeignKey(x => x.PeriodId).OnDelete(DeleteBehavior.Cascade);

            // Restrict: حذف إسناد موظف لا يجوز أن يمحو سطره من كشف **مُسدَّد** — السجل المالي
            //           يبقى شاهداً على ما صُرف فعلاً.
            e.HasOne(x => x.EmployeeCompany).WithMany()
                .HasForeignKey(x => x.EmployeeCompanyId).OnDelete(DeleteBehavior.Restrict);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- HrSettings (إعدادات الوحدة لكل شركة) ----
        b.Entity<HrSettings>(e =>
        {
            e.HasKey(x => x.SettingsId);
            e.HasIndex(x => x.CompanyId).IsUnique();
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- EmployeeLeave (الإجازات) ----
        b.Entity<EmployeeLeave>(e =>
        {
            e.HasKey(x => x.LeaveId);
            e.Property(x => x.Notes).HasMaxLength(1000);
            e.Property(x => x.ReviewNotes).HasMaxLength(500);

            e.HasIndex(x => new { x.EmployeeCompanyId, x.FromDate });
            e.HasIndex(x => new { x.CompanyId, x.Status });

            e.HasOne(x => x.EmployeeCompany).WithMany()
                .HasForeignKey(x => x.EmployeeCompanyId).OnDelete(DeleteBehavior.Cascade);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
        });

        // ---- EmployeeLog (سجلّ التغييرات — يُكتب ولا يُعدَّل) ----
        b.Entity<EmployeeLog>(e =>
        {
            e.HasKey(x => x.LogId);
            e.Property(x => x.Description).IsRequired().HasMaxLength(1000);
            e.Property(x => x.OldValue).HasMaxLength(500);
            e.Property(x => x.NewValue).HasMaxLength(500);

            e.HasIndex(x => new { x.EmployeeCompanyId, x.ChangedAt });

            e.HasOne(x => x.EmployeeCompany).WithMany()
                .HasForeignKey(x => x.EmployeeCompanyId).OnDelete(DeleteBehavior.Cascade);

            // بلا حذف ناعم عمداً: السجلّ شاهدٌ لا سجلّ عمل.
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        // ---- AuditLog ----
        b.Entity<AuditLog>(e =>
        {
            e.HasKey(x => x.LogId);
            e.Property(x => x.Action).IsRequired().HasMaxLength(50);
            e.Property(x => x.EntityType).HasMaxLength(100);
            e.Property(x => x.EntityId).HasMaxLength(50);
            e.Property(x => x.Details).HasMaxLength(2000);
            e.HasIndex(x => x.Timestamp);
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId || x.CompanyId == null);
        });
    }
}
