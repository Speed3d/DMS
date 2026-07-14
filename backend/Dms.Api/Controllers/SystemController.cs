using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Dms.Api.Seeding;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SystemController(AppDbContext db, IServiceProvider services, IConfiguration config, IWebHostEnvironment env, ILogger<SystemController> logger) : ControllerBase
{
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
