using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Backup;
using Dms.Infrastructure.Documents;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Outgoing;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Reports;
using Dms.Infrastructure.Services;
using Dms.Infrastructure.Users;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Dms.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        services.AddDbContext<AppDbContext>(o =>
            o.UseSqlServer(config.GetConnectionString("Default"),
                    sql => sql.EnableRetryOnFailure())
                // العلاقة User↔UserCompany تُقرأ دائماً عبر User المفلتَر؛ التحذير غير مؤثّر.
                .ConfigureWarnings(w =>
                    w.Ignore(CoreEventId.PossibleIncorrectRequiredNavigationWithQueryFilterInteractionWarning)));

        services.Configure<JwtSettings>(config.GetSection(JwtSettings.Section));
        services.Configure<QrSigningOptions>(config.GetSection(QrSigningOptions.Section));

        services.AddScoped<IPasswordHasher, BCryptPasswordHasher>();
        services.AddScoped<IJwtTokenService, JwtTokenService>();
        services.AddScoped<IAuditService, AuditService>();
        services.AddScoped<INumberingService, NumberingService>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<IDelegationService, DelegationService>();
        services.AddScoped<IOutgoingService, OutgoingService>();
        services.AddScoped<IIncomingService, IncomingService>();
        services.AddScoped<IArchiveService, ArchiveService>();
        services.AddScoped<IAttachmentService, AttachmentService>();
        services.AddScoped<IReportService, ReportService>();
        services.AddScoped<IBackupService, BackupService>();
        services.AddHostedService<BackupScheduler>();
        services.AddScoped<BookRenderer>();

        return services;
    }
}
