using Dms.Api.Ops;
using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Seeding;

public static class DbSeeder
{
    /// <summary>يطبّق الـ Migrations وينشئ أول SuperAdmin إن لم يوجد أي مستخدم.</summary>
    public static async Task MigrateAndSeedAsync(IServiceProvider services, IConfiguration config, ILogger logger)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher>();

        await db.Database.MigrateAsync();

        if (!await db.Users.IgnoreQueryFilters().AnyAsync())
        {
            // 🔴 **لا `??` هنا**: `appsettings.json` يشحن `""` و**السلسلة الفارغة ليست `null`**،
            //    فكان يُنشأ مدير باسمٍ وكلمة مرورٍ فارغين ولا حسابَ آخر يُصلحه.
            //    القاعدة في `Dms.Domain/SeedCredentials.cs` وحدها.
            var username = SeedCredentials.Username(config["Seed:AdminUsername"]);
            var password = SeedCredentials.Password(config["Seed:AdminPassword"]);

            db.Users.Add(new User
            {
                FullName = "مدير النظام",
                Username = username,
                PasswordHash = hasher.Hash(password),
                Role = UserRole.SuperAdmin,
                // بلا شركة ولا إسنادات: السوبر أدمن معفى من قيود الأقسام والصلاحيات (ADR-017).
                CompanyId = null,
                IsActive = true,
                MustChangePassword = true,
                CreatedAt = DateTime.UtcNow,
            });
            logger.LogWarning("تم إنشاء حساب SuperAdmin الأول: '{User}' بكلمة مرور مؤقتة — غيّرها فوراً.", username);
        }

        // تم إزالة بذر الشركة الافتراضية بناءً على طلب المستخدم ليكون النظام فارغاً تماماً

        RecordVersionChange(db, await LastRecordedVersionAsync(db), BuildInfo.Current, logger);

        await db.SaveChangesAsync();
    }

    /// <summary>آخر إصدارٍ سُجّل في التدقيق — <c>null</c> إن لم يُسجَّل شيء.</summary>
    private static async Task<string?> LastRecordedVersionAsync(AppDbContext db) =>
        await db.AuditLogs.IgnoreQueryFilters()
            .Where(a => a.Action == "AppVersion")
            .OrderByDescending(a => a.LogId)
            .Select(a => a.EntityId)
            .FirstOrDefaultAsync();

    /// <summary>
    /// يسجّل في التدقيق **أوّلَ إقلاعٍ بإصدارٍ جديد** — «من 0.9.0 إلى 0.9.1» (ADR-054).
    /// </summary>
    /// <remarks>
    /// 🔑 **بالرقم وحده لا بالـcommit** — وإلا سُجّل سطرٌ مع كل بناءٍ للتطوير.
    /// ⚠️ **واستعادةُ نسخةٍ قديمة تُرجع سجلَّ التدقيق معها** — فيُسجَّل الإصدار ثانيةً بعدها، وهذا صحيح:
    /// القاعدة المستعادة لم تشهد هذا الإصدار.
    /// </remarks>
    private static void RecordVersionChange(AppDbContext db, string? last, AppVersion current, ILogger logger)
    {
        if (last == current.Display) return;
        db.AuditLogs.Add(new AuditLog
        {
            UserId = null,
            CompanyId = null,
            Action = "AppVersion",
            EntityType = "System",
            EntityId = current.Display,
            Details = (last is null ? $"أوّل إقلاعٍ بالإصدار {current.Display}" : $"من {last} إلى {current.Display}")
                      + (current.ShortCommit is { } c ? $" · {c}" : ""),
            Timestamp = DateTime.UtcNow,
        });
        logger.LogInformation("إصدار البرنامج: {From} ⟵ {To}", last ?? "—", current.Display);
    }
}
