using Dms.Infrastructure.Persistence;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Services;

/// <summary>
/// يلتقط تغيّر ملفّ حالة النظام **من خارج الخدمة** — أي أمر الطوارئ على السيرفر
/// (<c>Dms.Api.exe maintenance on|off</c>) — فيسري والخدمة تعمل، ويُدوَّن في التدقيق (ADR-050).
/// </summary>
/// <remarks>
/// ⚠️ **الفحص هنا لا في مسار الطلب**: الوسيط يقرأ الذاكرة وحدها، فلا يلمس القرص في كل طلب.
/// والتأخّر ثانيتان على الأكثر — مقبولٌ لأمرٍ يُكتب يدوياً على السيرفر.
/// </remarks>
public sealed class SystemControlWatcher(
    ISystemControl system,
    IMaintenanceState maintenance,
    IServiceScopeFactory scopeFactory,
    ILogger<SystemControlWatcher> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(2);

    /// <summary>اسم الفاعل في سطر التدقيق حين يأتي التغيير من السيرفر نفسه.</summary>
    public const string ConsoleActor = "وحدة تحكّم السيرفر";

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (system.ReloadIfChangedExternally() is { } change)
                    await AuditAsync(change, stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "فشل فحص ملفّ حالة النظام.");
            }

            try { await Task.Delay(Interval, stoppingToken); } catch { return; }
        }
    }

    private async Task AuditAsync(ExternalLockdownChange change, CancellationToken ct)
    {
        var action = change.After.Active ? "SystemLockdownOn" : "SystemLockdownOff";
        var details = change.After.Active
            ? $"{ConsoleActor}: {change.After.Message}"
            : ConsoleActor;
        logger.LogWarning("تغيّر إيقاف النظام من السيرفر: {Action} — {Details}", action, details);

        // أثناء الاستعادة القاعدة في وضع مستخدمٍ واحد — يكفي سجلّ الخدمة.
        if (maintenance.IsActive) return;

        try
        {
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            scope.ServiceProvider.GetRequiredService<IAuditService>()
                .Add(action, SystemAuditEntity, null, details);
            await db.SaveChangesAsync(ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // القاعدة قد تكون سبب الطوارئ أصلاً — فلا يُفشل التدوينُ الإيقافَ نفسه.
            logger.LogError(ex, "تعذّر تدوين تغيّر الإيقاف في سجلّ التدقيق.");
        }
    }

    /// <summary>نوع الكيان في سطور تدقيق الإيقاف والشريط.</summary>
    public const string SystemAuditEntity = "System";
}
