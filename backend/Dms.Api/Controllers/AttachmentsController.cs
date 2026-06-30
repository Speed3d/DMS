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
    public async Task<IActionResult> Download(int id, CancellationToken ct)
    {
        var (meta, content) = await attachments.GetAsync(id, ct);
        return File(content, ContentTypeFor(meta.FileType), meta.FileName);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await attachments.DeleteAsync(id, ct);
        return NoContent();
    }

    private static string ContentTypeFor(string ext) => ext.ToLowerInvariant() switch
    {
        "pdf" => "application/pdf",
        "png" => "image/png",
        "jpg" or "jpeg" => "image/jpeg",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        _ => "application/octet-stream",
    };
}
