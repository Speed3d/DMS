using Dms.Api.Dtos;
using Dms.Infrastructure.Reports;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public sealed class ReportsController(IReportService reports) : ControllerBase
{
    /// <summary>التقرير المالي لفترة (يجمع الصادر المعتمد + الأرشيف بالدينار). source: All/Outgoing/Archive.</summary>
    [HttpGet("financial")]
    public async Task<ActionResult<FinancialReportDto>> Financial(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var r = await reports.FinancialAsync(from, to, entityId, source, ct);
        return new FinancialReportDto(r.From, r.To,
            r.Rows.Select(x => new FinancialRowDto(x.Source, x.Number, x.Date, x.EntityName, x.Amount, x.Currency, x.AmountInIqd)).ToList(),
            r.TotalIqd, r.Count);
    }

    [HttpGet("financial/pdf")]
    public async Task<IActionResult> FinancialPdf(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var bytes = await reports.FinancialPdfAsync(from, to, entityId, source, ct);
        return File(bytes, "application/pdf", "financial-report.pdf");
    }

    [HttpGet("financial/excel")]
    public async Task<IActionResult> FinancialExcel(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? entityId, [FromQuery] string source = "All", CancellationToken ct = default)
    {
        var bytes = await reports.FinancialExcelAsync(from, to, entityId, source, ct);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "financial-report.xlsx");
    }
}
