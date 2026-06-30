using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Services;

public interface INumberingService
{
    /// <summary>
    /// يحجز التسلسل التالي لـ (شركة + سنة + نوع) بأمان تزامني (UPDLOCK).
    /// يجب استدعاؤه داخل Transaction مفتوحة من قِبل العملية.
    /// </summary>
    Task<int> NextSerialAsync(int companyId, int year, string type, CancellationToken ct = default);
}

public sealed class NumberingService(AppDbContext db) : INumberingService
{
    public async Task<int> NextSerialAsync(int companyId, int year, string type, CancellationToken ct = default)
    {
        // قفل صفّي على عدّاد (الشركة/السنة/النوع) لتسلسل آمن دون تكرار.
        var counter = await db.Counters
            .FromSql(
                $@"SELECT * FROM [Counters] WITH (UPDLOCK, HOLDLOCK)
                   WHERE [CompanyId] = {companyId} AND [Year] = {year} AND [Type] = {type}")
            .FirstOrDefaultAsync(ct);

        if (counter is null)
        {
            counter = new Counter { CompanyId = companyId, Year = year, Type = type, LastNumber = 1 };
            db.Counters.Add(counter);
        }
        else
        {
            counter.LastNumber += 1;
        }

        await db.SaveChangesAsync(ct);
        return counter.LastNumber;
    }
}
