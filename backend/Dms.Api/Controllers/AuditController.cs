using Dms.Api.Dtos;
using Dms.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
// سجل التدقيق يكشف بيانات كل الأقسام (مواضيع/أرقام الصادر، الأرشيف، المستخدمون...).
// يُقصر على الأدوار المعفاة من تقييد الأقسام (رئيس الشركة فأعلى) لتفادي تسرّب عبر الأقسام لمدير مقيّد.
[Authorize(Roles = "SuperAdmin,President")]
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
