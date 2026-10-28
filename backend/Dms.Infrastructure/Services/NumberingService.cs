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

    /// <summary>
    /// يقرأ قيمة العداد الحالية دون تعديلها أو قفلها.
    /// </summary>
    Task<int> GetCurrentCounterAsync(int companyId, int year, string type, CancellationToken ct = default);

    /// <summary>
    /// يحجز أو يضبط تسلسلاً يدوياً لـ (شركة + سنة + نوع) بأمان تزامني (UPDLOCK).
    /// إذا كان التسلسل اليدوي أكبر من العداد الحالي، يُرفع العداد إلى هذا الرقم.
    /// إذا كان أصغر أو مساوياً، يبقى العداد كما هو دون تغيير.
    /// يعيد <c>false</c> إن كان التسلسل لكتابٍ حيّ — والفحص **بعد القفل** فلا يأخذه اثنان معاً.
    /// </summary>
    Task<bool> TryRegisterManualSerialAsync(int companyId, int year, string type, int manualSerial, CancellationToken ct = default);

    /// <summary>
    /// يتراجع بالعداد خطوة للوراء عند حذف كتاب معتمد إذا كان رقمه هو آخر تسلسل في العداد (ADR-064).
    /// </summary>
    Task<bool> DecrementIfLastAsync(int companyId, int year, string type, int serial, CancellationToken ct = default);
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

        // 🛡️ حارس التخطي: إذا كان الرقم الناتج مستخدماً بالفعل لكتاب فعال (حُجز يدوياً مثلاً)، نزيد العداد حتى نجد تسلسلاً متاحاً
        if (type == "Outgoing")
        {
            while (await db.OutgoingBooks.IgnoreQueryFilters()
                .AnyAsync(b => b.CompanyId == companyId && b.Year == year && !b.IsDeleted && b.Status == BookStatus.Final && b.SerialNo == counter.LastNumber, ct))
            {
                counter.LastNumber += 1;
            }
        }

        await db.SaveChangesAsync(ct);
        return counter.LastNumber;
    }

    public async Task<int> GetCurrentCounterAsync(int companyId, int year, string type, CancellationToken ct = default)
    {
        var counter = await db.Counters.AsNoTracking()
            .FirstOrDefaultAsync(c => c.CompanyId == companyId && c.Year == year && c.Type == type, ct);
        return counter?.LastNumber ?? 0;
    }

    public async Task<bool> TryRegisterManualSerialAsync(int companyId, int year, string type, int manualSerial, CancellationToken ct = default)
    {
        if (manualSerial <= 0)
            throw new ValidationException("رقم التسلسل يجب أن يكون رقماً موجباً أكبر من الصفر.");

        var counter = await db.Counters
            .FromSql(
                $@"SELECT * FROM [Counters] WITH (UPDLOCK, HOLDLOCK)
                   WHERE [CompanyId] = {companyId} AND [Year] = {year} AND [Type] = {type}")
            .FirstOrDefaultAsync(ct);

        // 🔴 **الفحص بعد القفل لا قبله**: معتمِدان بالرقم نفسه في اللحظة نفسها — الثاني ينتظر القفل ثم يرى كتاب الأول.
        if (type == "Outgoing" && await db.OutgoingBooks.IgnoreQueryFilters()
                .AnyAsync(b => b.CompanyId == companyId && b.Year == year && !b.IsDeleted && b.Status == BookStatus.Final && b.SerialNo == manualSerial, ct))
            return false;

        if (counter is null)
        {
            counter = new Counter { CompanyId = companyId, Year = year, Type = type, LastNumber = manualSerial };
            db.Counters.Add(counter);
        }
        else if (manualSerial > counter.LastNumber)
        {
            counter.LastNumber = manualSerial;
        }

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DecrementIfLastAsync(int companyId, int year, string type, int serial, CancellationToken ct = default)
    {
        var counter = await db.Counters
            .FromSql(
                $@"SELECT * FROM [Counters] WITH (UPDLOCK, HOLDLOCK)
                   WHERE [CompanyId] = {companyId} AND [Year] = {year} AND [Type] = {type}")
            .FirstOrDefaultAsync(ct);

        if (counter is null || counter.LastNumber != serial) return false;

        int? maxRemaining = type switch
        {
            "Outgoing" => await db.OutgoingBooks.IgnoreQueryFilters()
                .Where(b => b.CompanyId == companyId && b.Year == year && !b.IsDeleted && b.Status == BookStatus.Final && b.SerialNo != serial)
                .MaxAsync(b => b.SerialNo, ct),
            "Incoming" => await db.IncomingBooks.IgnoreQueryFilters()
                .Where(b => b.CompanyId == companyId && b.Year == year && !b.IsDeleted && b.SerialNo != serial)
                .MaxAsync(b => (int?)b.SerialNo, ct),
            _ => counter.LastNumber - 1,
        };

        var next = OutgoingSerialRules.CounterAfterDelete(counter.LastNumber, serial, maxRemaining);
        if (next is null) return false;

        counter.LastNumber = next.Value;
        await db.SaveChangesAsync(ct);
        return true;
    }
}
