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

        await db.SaveChangesAsync();
    }
}
