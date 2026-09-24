using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Services;

/// <summary>
/// ينفّذ إنشاءً **مرّةً واحدة لكل مفتاح** — فإن وصل الطلب نفسه ثانيةً أعاد ما أُنشئ أوّلاً (ADR-051).
/// </summary>
/// <remarks>
/// <b>الترتيب:</b> حجزُ المفتاح (صفٌّ بلا نتيجة) ⇐ الإنشاء ⇐ تسجيلُ النتيجة. فإن فشل الإنشاء
/// أُلغي الحجز فيُعاد الطلب لاحقاً.
///
/// 🔴 <b>والحجز أوّلاً لا الفحص:</b> «ابحث عن المفتاح، فإن لم تجده أنشئ» يمرّر طلبين متزامنين
/// معاً — والفهرس الفريد على (<c>UserId</c>, <c>Key</c>) هو الذي يمنع الثاني فعلاً.
///
/// ⚠️ <b>والحجز والإلغاء والتسجيل خارج متتبّع التغييرات</b> (<c>ExecuteUpdate/Delete</c> وفصلُ
/// الصفّ بعد إدراجه): الخدمة التي تُنشئ تحفظ بسياقها، وإنشاءٌ فاشل قد يترك في المتتبّع ما لا
/// نريد أن يُحفظ مع إلغاء الحجز.
/// </remarks>
public interface IIdempotencyService
{
    /// <summary>
    /// يُنشئ بـ<paramref name="create"/> ويعيد معرّفه — أو يعيد معرّف ما أُنشئ سابقاً بالمفتاح نفسه.
    /// </summary>
    /// <param name="key">ترويسة <c>Idempotency-Key</c> — غيابُها يعني إنشاءً عادياً بلا حماية.</param>
    /// <param name="entityType">نوع ما يُنشأ — مفتاحٌ واحد لا يخدم نوعين.</param>
    Task<int> ExecuteAsync(string? key, string entityType, Func<Task<int>> create, CancellationToken ct);
}

public sealed class IdempotencyService(AppDbContext db, ICurrentUser current) : IIdempotencyService
{
    public async Task<int> ExecuteAsync(string? key, string entityType, Func<Task<int>> create, CancellationToken ct)
    {
        var k = IdempotencyKey.Normalize(key);
        // بلا مفتاح أو بلا مستخدمٍ وشركة ⇒ إنشاءٌ عاديّ كما كان.
        if (k is null || current.UserId is not { } userId || current.ActiveCompanyId is not { } companyId)
            return await create();

        var reservation = await ReserveAsync(k, entityType, userId, companyId, ct);
        if (reservation.ExistingEntityId is { } existing) return existing;

        int id;
        try
        {
            id = await create();
        }
        catch
        {
            // فشلُ الإنشاء (خطأ تحقّق أو غيره) ⇒ أُلغي الحجز، فيُعاد الطلب بعد التصحيح.
            await db.ClientRequests.IgnoreQueryFilters()
                .Where(x => x.ClientRequestId == reservation.RowId)
                .ExecuteDeleteAsync(CancellationToken.None);
            throw;
        }

        await db.ClientRequests.IgnoreQueryFilters()
            .Where(x => x.ClientRequestId == reservation.RowId)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.EntityId, id), CancellationToken.None);
        return id;
    }

    private readonly record struct Reservation(long RowId, int? ExistingEntityId);

    private async Task<Reservation> ReserveAsync(string key, string entityType, int userId, int companyId, CancellationToken ct)
    {
        // محاولتان: الثانية بعد إزالة حجزٍ منقطع.
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var row = new ClientRequest
            {
                UserId = userId,
                CompanyId = companyId,
                Key = key,
                EntityType = entityType,
                CreatedAt = DateTime.UtcNow,
            };
            db.ClientRequests.Add(row);
            try
            {
                await db.SaveChangesAsync(ct);
                return new Reservation(row.ClientRequestId, null);
            }
            catch (DbUpdateException)
            {
                // المفتاح محجوزٌ من قبل — نقرأ ما هو.
            }
            finally
            {
                db.Entry(row).State = EntityState.Detached;
            }

            // ⚠️ `IgnoreQueryFilters`: المفتاح للمستخدم نفسه، ونراه ولو اختلفت الشركة الفعّالة —
            //    وإلا أُنشئ الكتاب مرّةً ثانية في شركةٍ أخرى بالمفتاح نفسه.
            var existing = await db.ClientRequests.IgnoreQueryFilters().AsNoTracking()
                .FirstOrDefaultAsync(x => x.UserId == userId && x.Key == key, ct)
                ?? throw new ConflictException("تعذّر حجز الطلب. أعد المحاولة.");

            if (existing.EntityType != entityType)
                throw new ValidationException("مفتاح منع التكرار استُعمل لنوعٍ آخر.");
            if (existing.CompanyId != companyId)
                throw new ConflictException("هذا الطلب أُرسل من شركةٍ أخرى — بدّل إليها لإكماله.");

            if (existing.EntityId is { } done) return new Reservation(existing.ClientRequestId, done);

            if (DateTime.UtcNow - existing.CreatedAt < IdempotencyKey.StaleReservation)
                throw new ConflictException("الطلب نفسه قيد المعالجة الآن. انتظر لحظة ثم أعد المحاولة.");

            // حجزٌ منقطع (سقط الخادم في منتصف الإنشاء) ⇒ يُزال ويُعاد.
            await db.ClientRequests.IgnoreQueryFilters()
                .Where(x => x.ClientRequestId == existing.ClientRequestId && x.EntityId == null)
                .ExecuteDeleteAsync(ct);
        }
        throw new ConflictException("تعذّر حجز الطلب. أعد المحاولة.");
    }
}
