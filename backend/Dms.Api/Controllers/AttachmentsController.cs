using Dms.Infrastructure.Attachments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public sealed class AttachmentsController(IAttachmentService attachments) : ControllerBase
{
    [HttpGet("{id:int}")]
    public async Task<IActionResult> Download(int id, bool inline, CancellationToken ct)
    {
        var (meta, content) = await attachments.GetAsync(id, ct);

        // `inline=true` للعرض داخل البرنامج — بلا اسم ملف حتى لا تصير الاستجابة «تنزيلاً»
        // فيختطفها مديرو التحميل (انظر MimeTypes).
        if (inline) return File(content, MimeTypes.For(meta.FileName));

        return File(content, MimeTypes.For(meta.FileName), meta.FileName);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await attachments.DeleteAsync(id, ct);
        return NoContent();
    }
}
