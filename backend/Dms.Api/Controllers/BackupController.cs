using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Backup;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin")] // النسخ الاحتياطي للسوبر أدمن فقط
[RequireModule(AppModule.Backup)]
[Route("api/[controller]")]
public sealed class BackupController(IBackupService backup) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<BackupRecordDto>>> List(CancellationToken ct)
        => (await backup.ListAsync(ct)).Select(Map).ToList();

    [HttpPost("run")]
    public async Task<ActionResult<BackupRecordDto>> Run(CancellationToken ct)
        // النسخة اليدوية دائماً كاملة وتصنيفها Manual (لا تُقلَّم إلا عند تجاوز سقف كبير).
        => Map(await backup.RunAsync(BackupType.Manual, BackupScope.Full, RetentionCategory.Manual, ct));

    /// <summary>استعادة نسخة احتياطية — عملية تدميرية تتطلب كلمة تأكيد في الجسم.</summary>
    [HttpPost("{id:int}/restore")]
    public async Task<IActionResult> Restore(int id, RestoreBackupRequest req, CancellationToken ct)
    {
        await backup.RestoreAsync(id, req.Confirmation, ct);
        return Ok(new { message = "تمت الاستعادة بنجاح. أُنشئت نسخة أمان تلقائية قبل الاستبدال." });
    }

    [HttpGet("schedule")]
    public async Task<ActionResult<BackupScheduleDto>> GetSchedule(CancellationToken ct)
        => MapSchedule(await backup.GetScheduleAsync(ct));

    [HttpPut("schedule")]
    public async Task<ActionResult<BackupScheduleDto>> UpdateSchedule(UpdateBackupScheduleRequest req, CancellationToken ct)
        => MapSchedule(await backup.UpdateScheduleAsync(new UpdateScheduleInput(req.Frequency, req.Enabled, req.Hour), ct));

    /// <summary>حذف نسخة احتياطية (السجلّ + الملف). يُمنع حذف آخر نسخة ناجحة.</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await backup.DeleteAsync(id, ct);
        return NoContent();
    }

    [HttpGet("{id:int}/download")]
    public async Task<IActionResult> Download(int id, CancellationToken ct)
    {
        var (bytes, _) = await backup.DownloadAsync(id, ct);
        // بلا اسم ملف عمداً: الشاشة تجلب البايتات بـXHR وتحفظها باسم النسخة من بياناتها،
        // وترويسةُ «تنزيل» تجعل مديري التحميل يختطفون الطلب فلا يصل ردّ (نفس علّة ADR-019).
        return File(bytes, "application/zip");
    }

    private static BackupRecordDto Map(BackupRecord r) =>
        new(r.BackupRecordId, r.CreatedAt, r.CreatedByUserId, r.FileName, r.SizeBytes, r.Type, r.Scope, r.Category, r.Status, r.Note);

    private static BackupScheduleDto MapSchedule(BackupSchedule s) =>
        new(s.Frequency, s.Enabled, s.Hour, s.LastRunAt, s.NextRunAt);
}
