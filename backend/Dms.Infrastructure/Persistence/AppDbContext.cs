using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Persistence;

public class AppDbContext : DbContext
{
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
            _companyId = currentUser.ActiveCompanyId ?? -1; // -1: لا يرى شيئاً إن لم تُحدَّد شركته
        }
    }

    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Template> Templates => Set<Template>();
    public DbSet<User> Users => Set<User>();
    public DbSet<UserCompany> UserCompanies => Set<UserCompany>();
    public DbSet<ApprovalDelegation> ApprovalDelegations => Set<ApprovalDelegation>();
    public DbSet<Entity> Entities => Set<Entity>();
    public DbSet<DocumentType> DocumentTypes => Set<DocumentType>();
    public DbSet<ExchangeRate> ExchangeRates => Set<ExchangeRate>();
    public DbSet<OutgoingBook> OutgoingBooks => Set<OutgoingBook>();
    public DbSet<ArchiveDoc> ArchiveDocs => Set<ArchiveDoc>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<DocumentVersion> DocumentVersions => Set<DocumentVersion>();
    public DbSet<Counter> Counters => Set<Counter>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<BackupRecord> BackupRecords => Set<BackupRecord>();
    public DbSet<BackupSchedule> BackupSchedules => Set<BackupSchedule>();

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
            e.HasQueryFilter(x => !_filterByCompany || x.CompanyId == _companyId);
        });

        b.Entity<UserCompany>(e =>
        {
            e.HasIndex(x => new { x.UserId, x.CompanyId }).IsUnique();
            e.HasOne(x => x.User).WithMany(u => u.AssignedCompanies)
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
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
                .HasForeignKey(x => x.TemplateId).OnDelete(DeleteBehavior.Restrict);

            e.HasQueryFilter(x => (!_filterByCompany || x.CompanyId == _companyId) && !x.IsDeleted);
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
