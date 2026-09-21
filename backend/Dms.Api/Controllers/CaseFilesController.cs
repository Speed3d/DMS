using Dms.Api.Dtos;
using Dms.Infrastructure.CaseFiles;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

/// <summary>
/// **المعاملات** — خيوطُ المراسلات التي تجمع الوارد والصادر (ADR-045).
/// </summary>
/// <remarks>
/// 🔴 **`[Authorize]` وحده بلا `[RequireModule]` — وهذا مقصود.** المعاملة تجمع **نوعين**،
/// و<c>HasModule</c> يفحص <c>(Allowed &amp; module) == module</c> فـ<c>Incoming | Outgoing</c>
/// تعني **«الاثنين معاً»** لا «أيّهما»، والسمة <c>AllowMultiple = false</c> فلا تُكرَّر.
/// واشتراطُ الوارد وحده كان **يحجب مَن يملك الصادر فقط** عن معاملةٍ كلُّ كتبه فيها صادر.
///
/// ⇒ الحارسان داخل <c>CaseFileService</c>: **قراءةٌ تشترط أحد القسمين**، و**كتابةٌ تشترط
/// `CanManageIncoming` مع دورٍ فوق القارئ**. وكلُّ جهةٍ تُقرأ بقسمها وحده، فما لا يُقرأ
/// يدخل في **عدد المحجوب** لا في القائمة.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/case-files")]
public sealed class CaseFilesController(ICaseFileService svc) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<CaseFileListItem>>> List(
        [FromQuery] string? search, CancellationToken ct) =>
        (await svc.ListAsync(search, ct))
        .Select(r => new CaseFileListItem(r.CaseFileId, r.Title, r.VisibleCount, r.HiddenCount, r.CreatedAt))
        .ToList();

    [HttpGet("{id:int}")]
    public async Task<ActionResult<CaseFileDetail>> Get(int id, CancellationToken ct) =>
        Map(await svc.GetAsync(id, ct));

    [HttpPost]
    public async Task<ActionResult<CaseFileDetail>> Create(CaseFileRequest req, CancellationToken ct)
    {
        var file = await svc.CreateAsync(req.Title, req.Notes, ct);
        return await Get(file.CaseFileId, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<CaseFileDetail>> Rename(int id, CaseFileRequest req, CancellationToken ct)
    {
        await svc.RenameAsync(id, req.Title, req.Notes, ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await svc.DeleteAsync(id, ct);
        return NoContent();
    }

    [HttpPost("{id:int}/members")]
    public async Task<ActionResult<CaseFileDetail>> AddMember(
        int id, CaseMemberRequest req, CancellationToken ct)
    {
        await svc.AddMemberAsync(id, req.Kind, req.BookId, ct);
        return await Get(id, ct);
    }

    /// <remarks>
    /// ⚠️ **قد تُطوى المعاملة بخروج آخر كتاب** فتردّ <c>Get</c> بـ404 على عمليةٍ نجحت —
    /// ولذلك <c>204</c> بدلها (نمط <c>DetailAfterMutationAsync</c> في وحدة الوارد).
    /// </remarks>
    [HttpDelete("{id:int}/members/{kind}/{bookId:int}")]
    public async Task<ActionResult<CaseFileDetail>> RemoveMember(
        int id, CaseMemberKind kind, int bookId, CancellationToken ct)
    {
        await svc.RemoveMemberAsync(id, kind, bookId, ct);
        try { return Map(await svc.GetAsync(id, ct)); }
        catch (Dms.Domain.NotFoundException) { return NoContent(); }
    }

    [HttpPost("{id:int}/merge/{sourceId:int}")]
    public async Task<ActionResult<CaseFileDetail>> Merge(int id, int sourceId, CancellationToken ct)
    {
        await svc.MergeAsync(id, sourceId, ct);
        return await Get(id, ct);
    }

    /// <summary>🔑 «يخصّ كتاباً سابقاً» — يُنشئ أو يضمّ أو يدمج بحسب حالة الطرفين.</summary>
    [HttpPost("relate")]
    public async Task<ActionResult<CaseFileDetail>> Relate(RelateRequest req, CancellationToken ct)
    {
        var file = await svc.RelateAsync(req.Kind, req.BookId, req.OtherKind, req.OtherBookId, req.Title, ct);
        return await Get(file.CaseFileId, ct);
    }

    /// <summary>بطاقة «الكتب المرتبطة» لكتابٍ بعينه — `204` إن لم يكن في معاملة.</summary>
    [HttpGet("related/{kind}/{bookId:int}")]
    public async Task<ActionResult<CaseFileDetail>> Related(
        CaseMemberKind kind, int bookId, CancellationToken ct)
    {
        var data = await svc.RelatedAsync(kind, bookId, ct);
        return data is null ? NoContent() : Map(data);
    }

    private static CaseFileDetail Map(CaseFileData d) => new(
        d.File.CaseFileId, d.File.Title, d.File.Notes, d.File.CreatedAt,
        d.Members.Select(m => new CaseMemberDto(
            m.Kind, m.BookId, m.Number, m.Date, m.Subject, m.Status)).ToList(),
        d.HiddenCount);
}
