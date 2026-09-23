using Dms.Infrastructure.Services;

namespace Dms.Api.Ops;

/// <summary>
/// أمر الطوارئ على السيرفر: إيقاف النظام عن المستخدمين أو تشغيله **بلا واجهة** (ADR-050).
///
/// الاستخدام:
///   Dms.Api.exe maintenance on "النظام متوقّف للتحديث — نعود خلال نصف ساعة"
///   Dms.Api.exe maintenance off
///   Dms.Api.exe maintenance status
///   (واختيارياً: --file &lt;مسار&gt; لتجاوز المسار المشتقّ من الإعداد)
///
/// 🔑 **متى؟** حين لا تعمل الواجهة أصلاً، **وفي سكربت التحديث**: يُوقَف النظام أولاً، ثم تُوقَف
/// الخدمة وتُحدَّث وتُشغَّل — **فتعود موقوفةً** (الحالة في ملفّ) حتى يفحصها المالك ويشغّلها من
/// الإعدادات. والخدمة إن كانت تعمل تلتقط التغيير خلال ثانيتين وتدوّنه في التدقيق.
/// </summary>
public static class MaintenanceCommand
{
    public static int Run(string[] args)
    {
        var rest = args.Skip(1).ToList();
        string? fileOverride = null;
        var fileIdx = rest.FindIndex(a => a.Equals("--file", StringComparison.OrdinalIgnoreCase));
        if (fileIdx >= 0)
        {
            if (fileIdx + 1 >= rest.Count) return Usage();
            fileOverride = rest[fileIdx + 1];
            rest.RemoveRange(fileIdx, 2);
        }
        if (rest.Count == 0) return Usage();

        var path = fileOverride is null ? ResolveFromConfig() : Path.GetFullPath(fileOverride);
        var system = new SystemControl(path);
        var verb = rest[0].ToLowerInvariant();

        try
        {
            switch (verb)
            {
                case "on":
                    var message = string.Join(' ', rest.Skip(1));
                    system.SetLockdown(true, message, null, SystemControlWatcher.ConsoleActor);
                    Console.WriteLine("⏸ النظام موقوفٌ عن المستخدمين (السوبر أدمن وحده يدخل).");
                    break;
                case "off":
                    system.SetLockdown(false, null, null, SystemControlWatcher.ConsoleActor);
                    Console.WriteLine("▶ النظام يعمل للجميع.");
                    break;
                case "status":
                    break;
                default:
                    return Usage();
            }
        }
        catch (Dms.Domain.ValidationException ex)
        {
            Console.Error.WriteLine($"✖ {ex.Message}");
            return 1;
        }

        var l = system.Lockdown;
        Console.WriteLine($"الملف: {system.FilePath}");
        Console.WriteLine(l.Active
            ? $"الحالة: موقوف منذ {l.SinceUtc?.ToLocalTime():yyyy-MM-dd HH:mm} — «{l.Message}»"
            : "الحالة: يعمل");
        return 0;
    }

    /// <summary>
    /// يقرأ الإعداد كما يقرؤه الخادم: <c>appsettings.json</c> ثم ملفّ البيئة ثم متغيّرات البيئة،
    /// **من مجلد البرنامج** (كما تفعل خدمة ويندوز) لا من المجلد الحاليّ.
    /// </summary>
    private static string ResolveFromConfig()
    {
        var env = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT")
                  ?? Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT")
                  ?? "Production";
        var baseDir = AppContext.BaseDirectory;
        var config = new ConfigurationBuilder()
            .SetBasePath(baseDir)
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile($"appsettings.{env}.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var storageRoot = config["Storage:LocalRoot"];
        if (string.IsNullOrWhiteSpace(storageRoot))
            storageRoot = Path.Combine(baseDir, "App_Data", "storage");
        return SystemControlPath.Resolve(config[SystemControlPath.ConfigKey], storageRoot);
    }

    private static int Usage()
    {
        Console.Error.WriteLine("الاستخدام: Dms.Api.exe maintenance on \"الرسالة\" | off | status  [--file <مسار>]");
        return 1;
    }
}
