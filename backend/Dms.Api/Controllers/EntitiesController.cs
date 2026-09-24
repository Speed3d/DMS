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
[Route("api/[controller]")]
public sealed class EntitiesController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<EntityResponse>>> List(CancellationToken ct)
        => await db.Entities.OrderBy(e => e.Name)
            .Select(e => new EntityResponse(e.EntityId, e.CompanyId, e.Name, e.Kind, e.Notes)).ToListAsync(ct);

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager,Employee")]
    public async Task<ActionResult<EntityResponse>> Create(
        EntityRequest req,
        [FromHeader(Name = IdempotencyKey.HeaderName)] string? idempotencyKey,
        [FromServices] IIdempotencyService idempotency,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم الجهة مطلوب.");
        var companyId = current.ActiveCompanyId ?? req.CompanyId ?? throw new ValidationException("حدّد الشركة.");

        // ⚠️ **الجهة الجديدة تُنشأ قبل الكتاب** — فانقطاعٌ بينهما ثم إعادةُ إرسال المسوّدة كانت
        //    تُنشئ الجهة مرّتين (لا فحصَ للتكرار هنا). والمفتاح يعيد الأولى (ADR-051).
        var id = await idempotency.ExecuteAsync(idempotencyKey, nameof(Entity), async () =>
        {
            var e = new Entity { CompanyId = companyId, Name = req.Name.Trim(), Kind = req.Kind, Notes = req.Notes };
            db.Entities.Add(e);
            audit.Add("Create", nameof(Entity), null, e.Name, companyId);
            await db.SaveChangesAsync(ct);
            return e.EntityId;
        }, ct);

        var saved = await db.Entities.AsNoTracking().FirstAsync(x => x.EntityId == id, ct);
        return new EntityResponse(saved.EntityId, saved.CompanyId, saved.Name, saved.Kind, saved.Notes);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<EntityResponse>> Update(int id, EntityRequest req, CancellationToken ct)
    {
        var e = await db.Entities.FirstOrDefaultAsync(x => x.EntityId == id, ct)
                ?? throw new NotFoundException("الجهة غير موجودة.");
        e.Name = req.Name.Trim();
        e.Kind = req.Kind;
        e.Notes = req.Notes;
        audit.Add("Update", nameof(Entity), id.ToString(), null, e.CompanyId);
        await db.SaveChangesAsync(ct);
        return new EntityResponse(e.EntityId, e.CompanyId, e.Name, e.Kind, e.Notes);
    }

    /// <summary>
    /// حذف جهة — مسموح فقط إن لم تكن مستخدَمة في أي سجلّ.
    /// Hint: الجهة مرتبطة بكتب رسمية (صادر/وارد/أرشيف)؛ حذفها مع وجودها يُفقِد اسم الجهة من سجلات
    ///       لا يجوز المساس بها. نرفض بـ 409 ورسالة تُبيّن أين تُستخدم بدل خطأ قاعدة بيانات غامض.
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var e = await db.Entities.FirstOrDefaultAsync(x => x.EntityId == id, ct)
                ?? throw new NotFoundException("الجهة غير موجودة.");

        // الفحص يشمل المحذوف ناعماً أيضاً (IgnoreQueryFilters) — السجل يبقى ويجب أن يبقى اسم جهته.
        //
        // 🔴 **لكنّ الرسالة كانت تكذب** (بلاغ المالك 2026-09-21): كتابٌ حذفه المستخدم بنفسه
        //    يبقى يمنع حذف الجهة، والرسالة تقول «1 صادر» **وهو لا يرى كتاباً واحداً في
        //    الشاشة**. فيبدو النظام معطوباً وهو يعمل بقاعدةٍ لم يُخبره بها.
        // 🔑 **رسالةٌ تقول «لا» بلا سببٍ مفهوم تدفع المستخدم إلى البحث عن مخرجٍ آخر** —
        //    وقد فعل: ذهب إلى زرّ تصفير القاعدة. ⇒ **يُفصل الحيّ عن المحذوف صراحةً.**
        var liveOutgoing = await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id && !b.IsDeleted, ct);
        var deadOutgoing = await db.OutgoingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id && b.IsDeleted, ct);
        var liveIncoming = await db.IncomingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id && !b.IsDeleted, ct);
        var deadIncoming = await db.IncomingBooks.IgnoreQueryFilters().CountAsync(b => b.EntityId == id && b.IsDeleted, ct);
        var liveArchive = await db.ArchiveDocs.IgnoreQueryFilters()
            .CountAsync(a => (a.FromEntityId == id || a.ToEntityId == id) && !a.IsDeleted, ct);
        var deadArchive = await db.ArchiveDocs.IgnoreQueryFilters()
            .CountAsync(a => (a.FromEntityId == id || a.ToEntityId == id) && a.IsDeleted, ct);

        var live = liveOutgoing + liveIncoming + liveArchive;
        var dead = deadOutgoing + deadIncoming + deadArchive;

        if (live + dead > 0)
        {
            var used = new List<string>();
            if (liveOutgoing > 0) used.Add($"{liveOutgoing} صادر");
            if (liveIncoming > 0) used.Add($"{liveIncoming} وارد");
            if (liveArchive > 0) used.Add($"{liveArchive} أرشيف");

            var deleted = new List<string>();
            if (deadOutgoing > 0) deleted.Add($"{deadOutgoing} صادر");
            if (deadIncoming > 0) deleted.Add($"{deadIncoming} وارد");
            if (deadArchive > 0) deleted.Add($"{deadArchive} أرشيف");

            var msg = $"لا يمكن حذف الجهة «{e.Name}»";
            if (live > 0) msg += $" لأنها مستخدَمة في: {string.Join(" · ", used)}";
            if (dead > 0)
            {
                msg += live > 0 ? "، و" : " لأنها مستخدَمة في ";
                msg += $"{string.Join(" · ", deleted)} **محذوف** — والمحذوف يبقى في السجلّ ويحتفظ باسم جهته";
            }
            msg += ".";
            if (live == 0 && dead > 0)
                msg += " لإزالتها نهائياً احذف الشركة كلَّها بعد تعطيلها (الإعدادات ← الشركات).";

            throw new ConflictException(msg);
        }

        db.Entities.Remove(e);
        audit.Add("Delete", nameof(Entity), id.ToString(), e.Name, e.CompanyId);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}
