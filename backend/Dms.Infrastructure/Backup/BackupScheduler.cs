using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Backup;

/// <summary>خدمة خلفية تُشغّل النسخ الاحتياطي المجدول عند حلول موعده.</summary>
public sealed class BackupScheduler(IServiceScopeFactory scopeFactory, ILogger<BackupScheduler> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); } catch { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var svc = scope.ServiceProvider.GetRequiredService<IBackupService>();
                var sched = await svc.GetScheduleAsync(stoppingToken);

                if (sched.Enabled && sched.Frequency != BackupFrequency.Off
                    && sched.NextRunAt is not null && sched.NextRunAt <= DateTime.Now)
                {
                    logger.LogInformation("تشغيل نسخة احتياطية مجدولة ({Freq}).", sched.Frequency);
                    await svc.RunAsync(BackupType.Scheduled, stoppingToken);

                    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    var s = await db.BackupSchedules.FirstAsync(stoppingToken);
                    s.LastRunAt = DateTime.UtcNow;
                    s.NextRunAt = BackupService.ComputeNext(s, DateTime.Now);
                    await db.SaveChangesAsync(stoppingToken);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "خطأ في مجدول النسخ الاحتياطي");
            }

            try { await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken); } catch { break; }
        }
    }
}
