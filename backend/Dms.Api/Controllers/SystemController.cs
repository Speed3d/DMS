using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Dms.Api.Seeding;

namespace Dms.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SystemController(AppDbContext db, IServiceProvider services, IConfiguration config, ILogger<SystemController> logger) : ControllerBase
{
    [HttpPost("reset-db")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> ResetDb()
    {
        // CAUTION: This is for development only!
        await db.Database.EnsureDeletedAsync();
        await DbSeeder.MigrateAndSeedAsync(services, config, logger);
        return Ok(new { message = "تم تصفير قاعدة البيانات بنجاح." });
    }
}
