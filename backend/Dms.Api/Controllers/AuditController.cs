using Dms.Api.Dtos;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
// سجل التدقيق يكشف بيانات كل الأقسام (مواضيع/أرقام الصادر، الأرشيف، المستخدمون...).
//
// 🔄 **ضُيّق إلى السوبر أدمن وحده (قرار المالك 2026-08-12)** — كان «رئيس الشركة فأعلى» منذ
//    تدقيق 2026-07-14. والمبرّر أن السجلّ **رقابةٌ على المستخدمين أنفسهم بمن فيهم الرئيس**،
//    فمن يُراقَب لا يملك أداة المراقبة.
//
// ⚠️ **يتغيّر مع `/api/reports/activity` دائماً ولا ينفصل عنه**: البابان يقودان إلى البيان
//    نفسه، وحارسان مختلفان عليهما يُوهمان بالإغلاق وهما مفتوحان من أحدهما.
[Authorize(Roles = "SuperAdmin")]
[Route("api/[controller]")]
public sealed class AuditController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<AuditResponse>>> List(
        [FromQuery] int take = 200, CancellationToken ct = default)
        => await db.AuditLogs.OrderByDescending(a => a.Timestamp)
            .Take(Math.Clamp(take, 1, 1000))
            .Select(a => new AuditResponse(a.LogId, a.UserId, a.Action, a.EntityType, a.EntityId, a.Details, a.Timestamp))
            .ToListAsync(ct);
}
