using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Backup;

/// <summary>خدمة خلفية تُشغّل النسخ الاحتياطي المجدول عند حلول موعده.</summary>
public sealed class BackupScheduler(
    IServiceScopeFactory scopeFactory, IMaintenanceState maintenance, ILogger<BackupScheduler> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); } catch { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Hint: أثناء الاستعادة تكون القاعدة في وضع مستخدم-واحد؛ لو حاول المجدول النسخ الآن
                //       لأخفق (القاعدة قيد الاستخدام) أو نازع الاستعادة على الاتصال الحصري. نتخطّى ببساطة.
                if (maintenance.IsActive)
                {
                    await Sleep(stoppingToken);
                    continue;
                }

                using var scope = scopeFactory.CreateScope();
                var svc = scope.ServiceProvider.GetRequiredService<IBackupService>();
                var sched = await svc.GetScheduleAsync(stoppingToken);

                if (sched.Enabled && sched.Frequency != BackupFrequency.Off
                    && sched.NextRunAt is not null && sched.NextRunAt <= DateTime.Now)
                {
                    // نطاق وتصنيف النسخة يُحسبان من التاريخ (يومية خفيفة، وترقية أسبوعية/شهرية تلقائياً).
                    var (backupScope, category) = BackupRetention.ClassifyScheduled(sched.Frequency, DateTime.Now);
                    logger.LogInformation("تشغيل نسخة مجدولة ({Category}/{Scope}).", category, backupScope);
                    await svc.RunAsync(BackupType.Scheduled, backupScope, category, stoppingToken);

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

            await Sleep(stoppingToken);
        }
    }

    private static async Task Sleep(CancellationToken ct)
    {
        try { await Task.Delay(TimeSpan.FromMinutes(1), ct); } catch { /* إيقاف الخدمة */ }
    }
}
