using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Jobs;
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

    /// <summary>حالة عمليةٍ طويلة بدأت في الخلفية (نسخ · مرآة · استعادة · حذف شركة).</summary>
    /// <remarks>
    /// ⚠️ **أثناء الاستعادة تردّ 503 كبقيّة النقاط** (وضع الصيانة يسبق المصادقة) — والواجهة
    /// تسأل حينها <c>/api/system/status</c> العامّة وحدها حتى تعود. **وهذا مقصود**: لو سُمح
    /// بها وانتهت صلاحية الرمز لحاول العميل التجديد، والتجديد مرفوضٌ في الصيانة، **فيُخرج
    /// المستخدم من النظام في منتصف الاستعادة**.
    /// 🔐 **للسوبر أدمن وحده** — مَن يملك بدء هذه العمليات أصلاً.
    /// </remarks>
    [HttpGet("jobs/{id:guid}")]
    [Authorize(Roles = "SuperAdmin")]
    public ActionResult<JobResponse> Job(Guid id, [FromServices] IBackgroundJobs jobs)
        => jobs.Get(id) is { } j
            ? JobResponse.From(j)
            : throw new NotFoundException(
                "العملية غير معروفة — ربما أُعيد تشغيل الخادم أثناءها. تحقّق من النتيجة ثم أعد المحاولة إن لزم.");

    /// <summary>العملية الطويلة الجارية الآن — لتستأنف الشاشة متابعتها بعد إعادة التحميل (204 إن لم توجد).</summary>
    [HttpGet("jobs/current")]
    [Authorize(Roles = "SuperAdmin")]
    public IActionResult CurrentJob([FromServices] IBackgroundJobs jobs)
        => jobs.Current is { } j ? Ok(JobResponse.From(j)) : NoContent();

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
