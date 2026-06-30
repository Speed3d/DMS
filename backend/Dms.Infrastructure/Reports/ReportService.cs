using System.Globalization;
using Dms.Documents.Reports;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Reports;

public sealed record FinancialReportRow(
    string Source, string Number, DateTime Date, string EntityName,
    decimal? Amount, Currency? Currency, decimal? AmountInIqd);

public sealed record FinancialReportResult(
    DateTime? From, DateTime? To, List<FinancialReportRow> Rows, decimal TotalIqd, int Count);

public sealed record ActivityRow(
    DateTime Timestamp, int? UserId, string UserName, string Action, string EntityType, string? EntityId, string? Details);

public interface IReportService
{
    Task<FinancialReportResult> FinancialAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);
    Task<byte[]> FinancialPdfAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);
    Task<byte[]> FinancialExcelAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);
    Task<List<ActivityRow>> ActivityAsync(DateTime? from, DateTime? to, int? userId, CancellationToken ct = default);
}

public sealed class ReportService(AppDbContext db, ICurrentUser current) : IReportService
{
    private bool OwnOnly => current.Role is UserRole.Employee or UserRole.Reader;

    public async Task<FinancialReportResult> FinancialAsync(
        DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var rows = new List<FinancialReportRow>();
        var includeOutgoing = source is "All" or "Outgoing";
        var includeArchive = source is "All" or "Archive";

        if (includeOutgoing)
        {
            var oq = db.OutgoingBooks.Where(b => b.Status == BookStatus.Final && b.AmountInIqd != null);
            if (OwnOnly) oq = oq.Where(b => b.CreatedByUserId == current.UserId);
            if (from is not null) oq = oq.Where(b => b.Date >= from);
            if (to is not null) oq = oq.Where(b => b.Date <= to);
            if (entityId is not null) oq = oq.Where(b => b.EntityId == entityId);

            rows.AddRange(await oq
                .Select(b => new FinancialReportRow("صادر", b.Number!, b.Date, b.Entity!.Name,
                    b.Amount, b.Currency, b.AmountInIqd))
                .ToListAsync(ct));
        }

        if (includeArchive)
        {
            var aq = db.ArchiveDocs.Where(a => a.AmountInIqd != null);
            if (OwnOnly) aq = aq.Where(a => a.CreatedByUserId == current.UserId);
            if (from is not null) aq = aq.Where(a => (a.BookDate ?? a.CreatedAt) >= from);
            if (to is not null) aq = aq.Where(a => (a.BookDate ?? a.CreatedAt) <= to);
            if (entityId is not null) aq = aq.Where(a => a.FromEntityId == entityId || a.ToEntityId == entityId);

            var aList = await aq.Select(a => new
            {
                a.ArchiveNumber, Date = a.BookDate ?? a.CreatedAt,
                a.FromEntityId, a.ToEntityId, a.Amount, a.Currency, a.AmountInIqd,
            }).ToListAsync(ct);

            var ids = aList.SelectMany(a => new[] { a.ToEntityId, a.FromEntityId })
                .Where(x => x is not null).Select(x => x!.Value).Distinct().ToList();
            var names = await db.Entities.Where(e => ids.Contains(e.EntityId))
                .ToDictionaryAsync(e => e.EntityId, e => e.Name, ct);

            rows.AddRange(aList.Select(a =>
            {
                var eid = a.ToEntityId ?? a.FromEntityId;
                var name = eid is not null && names.TryGetValue(eid.Value, out var n) ? n : "—";
                return new FinancialReportRow("أرشيف", a.ArchiveNumber, a.Date, name, a.Amount, a.Currency, a.AmountInIqd);
            }));
        }

        rows = rows.OrderBy(r => r.Date).ToList();
        var total = rows.Sum(r => r.AmountInIqd ?? 0m);
        return new FinancialReportResult(from, to, rows, total, rows.Count);
    }

    public async Task<byte[]> FinancialPdfAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var result = await FinancialAsync(from, to, entityId, source, ct);
        var company = await CompanyNameAsync(ct);
        var model = new FinancialReportModel(
            company, PeriodLabel(from, to),
            result.Rows.Select(r => new FinancialReportLine(
                r.Source, r.Number, r.Date.ToString("yyyy-MM-dd"), r.EntityName,
                Money(r.Amount, r.Currency), Money(r.AmountInIqd, Currency.IQD))).ToList(),
            Money(result.TotalIqd, Currency.IQD), result.Count);
        return FinancialReportPdf.Generate(model);
    }

    public async Task<byte[]> FinancialExcelAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var result = await FinancialAsync(from, to, entityId, source, ct);
        var headers = new[] { "المصدر", "الرقم", "التاريخ", "الجهة", "المبلغ", "العملة", "بالدينار" };
        var rows = result.Rows.Select(r => (IReadOnlyList<string>)new[]
        {
            r.Source, r.Number, r.Date.ToString("yyyy-MM-dd"), r.EntityName,
            r.Amount?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
            CurrencyLabel(r.Currency),
            r.AmountInIqd?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
        }).ToList();
        rows.Add(new[] { "الإجمالي", "", "", "", "", "", result.TotalIqd.ToString("0.##", CultureInfo.InvariantCulture) });
        return ExcelExporter.Create("التقرير المالي", headers, rows);
    }

    public async Task<List<ActivityRow>> ActivityAsync(DateTime? from, DateTime? to, int? userId, CancellationToken ct = default)
    {
        var q = db.AuditLogs.AsQueryable();
        if (from is not null) q = q.Where(a => a.Timestamp >= from);
        if (to is not null) q = q.Where(a => a.Timestamp < to.Value.Date.AddDays(1));
        if (userId is not null) q = q.Where(a => a.UserId == userId);

        var logs = await q.OrderByDescending(a => a.Timestamp).Take(500)
            .Select(a => new { a.Timestamp, a.UserId, a.Action, a.EntityType, a.EntityId, a.Details })
            .ToListAsync(ct);

        var ids = logs.Where(l => l.UserId is not null).Select(l => l.UserId!.Value).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => ids.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.FullName, ct);

        return logs.Select(l => new ActivityRow(
            l.Timestamp, l.UserId,
            l.UserId is not null && names.TryGetValue(l.UserId.Value, out var n) ? n : "—",
            l.Action, l.EntityType, l.EntityId, l.Details)).ToList();
    }

    private async Task<string> CompanyNameAsync(CancellationToken ct)
    {
        if (current.ActiveCompanyId is null) return "كل الشركات";
        return await db.Companies.Where(c => c.CompanyId == current.ActiveCompanyId)
            .Select(c => c.Name).FirstOrDefaultAsync(ct) ?? "—";
    }

    private static string PeriodLabel(DateTime? from, DateTime? to)
    {
        if (from is null && to is null) return "كل الفترات";
        var f = from?.ToString("yyyy-MM-dd") ?? "البداية";
        var t = to?.ToString("yyyy-MM-dd") ?? "النهاية";
        return $"من {f} إلى {t}";
    }

    private static string Money(decimal? amount, Currency? currency)
        => amount is null ? "—" : $"{amount.Value.ToString("#,0.##", CultureInfo.InvariantCulture)} {CurrencyLabel(currency)}";

    private static string CurrencyLabel(Currency? c) => c switch
    {
        Currency.USD => "دولار",
        Currency.IQD => "دينار",
        _ => "",
    };
}
