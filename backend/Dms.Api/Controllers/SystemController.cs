using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Dms.Api.Seeding;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SystemController(AppDbContext db, IServiceProvider services, IConfiguration config, IWebHostEnvironment env, ILogger<SystemController> logger, IMaintenanceState maintenance) : ControllerBase
{
    /// <summary>
    /// حالة النظام — مسموح بلا مصادقة ليعرف العميل متى يكون النظام قيد الصيانة (أثناء استعادة نسخة).
    /// Hint: هذا المسار مستثنى من MaintenanceMiddleware، فيبقى مجيباً حتى أثناء الصيانة.
    /// </summary>
    [HttpGet("status")]
    [AllowAnonymous]
    public IActionResult Status()
        => Ok(new { maintenance = maintenance.IsActive, reason = maintenance.Reason, since = maintenance.SinceUtc });

    [HttpPost("reset-db")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ResetDb()
    {
        // عملية تدميرية شاملة — متاحة في بيئة التطوير فقط (لا يجوز مسح قاعدة الإنتاج عبر الـ API).
        if (!env.IsDevelopment())
            throw new ForbiddenException("تصفير قاعدة البيانات غير متاح في بيئة الإنتاج.");

        await db.Database.EnsureDeletedAsync();
        await DbSeeder.MigrateAndSeedAsync(services, config, logger);
        return Ok(new { message = "تم تصفير قاعدة البيانات بنجاح." });
    }
}
