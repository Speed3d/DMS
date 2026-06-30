using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/exchange-rates")]
public sealed class ExchangeRatesController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<ExchangeRateResponse>>> List(CancellationToken ct)
        => await db.ExchangeRates.OrderByDescending(r => r.EffectiveDate)
            .Select(r => new ExchangeRateResponse(r.ExchangeRateId, r.Currency, r.Rate, r.EffectiveDate))
            .ToListAsync(ct);

    [HttpGet("latest")]
    public async Task<ActionResult<ExchangeRateResponse>> Latest([FromQuery] Currency currency, CancellationToken ct)
    {
        var r = await db.ExchangeRates.Where(x => x.Currency == currency)
            .OrderByDescending(x => x.EffectiveDate).FirstOrDefaultAsync(ct)
            ?? throw new NotFoundException("لا يوجد سعر صرف مُسجّل لهذه العملة.");
        return new ExchangeRateResponse(r.ExchangeRateId, r.Currency, r.Rate, r.EffectiveDate);
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<ExchangeRateResponse>> Create(ExchangeRateRequest req, CancellationToken ct)
    {
        if (req.Rate <= 0) throw new ValidationException("سعر الصرف يجب أن يكون موجباً.");
        var r = new ExchangeRate
        {
            Currency = req.Currency,
            Rate = req.Rate,
            EffectiveDate = req.EffectiveDate,
            CreatedByUserId = current.UserId!.Value,
            CreatedAt = DateTime.UtcNow,
        };
        db.ExchangeRates.Add(r);
        audit.Add("Create", nameof(ExchangeRate), null, $"{req.Currency} = {req.Rate}", current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);
        return new ExchangeRateResponse(r.ExchangeRateId, r.Currency, r.Rate, r.EffectiveDate);
    }
}
