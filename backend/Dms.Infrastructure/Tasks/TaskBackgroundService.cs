using Dms.Infrastructure.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Tasks;

/// <summary>
/// الخدمة الخلفية للمهام (ADR-039) — **واحدة لا اثنتان**، تدور كل ساعة.
/// </summary>
/// <remarks>
/// **لماذا خدمةٌ واحدة؟** ثانيةٌ تعني حلقتين ونطاقين وحارسَي صيانة و**نقطتَي فشل** — بلا
/// مقابل. والثلاثة (تصعيد · تذكير · توليد) تعمل على الجدول نفسه بالإيقاع نفسه.
///
/// ⚠️ **نمط <c>BackupScheduler</c> حرفياً**: تأخير إقلاعٍ 20 ثانية · <c>try/catch</c> حول
/// الدورة · تسجيل. والاتباع مقصود — سابقةٌ عاملة خيرٌ من نمطٍ مخترَع.
/// </remarks>
public sealed class TaskBackgroundService(
    IServiceScopeFactory scopeFactory,
    IMaintenanceState maintenance,
    ILogger<TaskBackgroundService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    /// <summary>عدّاد الدورات — التنظيف مرّةً كل 24 دورة (أي يومياً).</summary>
    private int _cycles;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // تأخيرُ الإقلاع يمنع مزاحمة المهاجرة والبذر عند بدء الخدمة.
        try { await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); } catch { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // 🔴 **X4 — نفس حارس `BackupScheduler`**: أثناء الاستعادة تكون القاعدة في
                //    وضع مستخدمٍ واحد، فكتابةٌ الآن تُخفق أو تنازع الاستعادة على الاتصال.
                if (maintenance.IsActive)
                {
                    await Sleep(stoppingToken);
                    continue;
                }

                using var scope = scopeFactory.CreateScope();
                var runner = scope.ServiceProvider.GetRequiredService<ITaskJobRunner>();

                // التنظيف يومياً لا كل ساعة — حذفُ 90 يوماً مسحٌ كامل للجدول لا يستحقّ التكرار.
                var purge = _cycles % 24 == 0;
                var result = await runner.RunOnceAsync(purge, stoppingToken);

                if (result.Escalated > 0 || result.DueSoonReminded > 0
                    || result.RecurringCreated > 0 || result.NotificationsPurged > 0)
                {
                    logger.LogInformation(
                        "دورة المهام: تصعيد {Esc} · تذكير {Due} · متكررة {Rec} · تنظيف {Purge}",
                        result.Escalated, result.DueSoonReminded,
                        result.RecurringCreated, result.NotificationsPurged);
                }
            }
            catch (Exception ex)
            {
                // ⚠️ **الحلقة لا تموت بخطأ دورة** — وإلا توقّف التصعيد كلُّه بصمت حتى إعادة
                //    تشغيل الخدمة، وهو أسوأ صور الفشل: لا رسالة ولا أثر.
                logger.LogError(ex, "خطأ في دورة المهام الخلفية");
            }

            _cycles++;
            await Sleep(stoppingToken);
        }
    }

    private static async Task Sleep(CancellationToken ct)
    {
        try { await Task.Delay(Interval, ct); } catch { /* إلغاءٌ عند الإيقاف */ }
    }
}
