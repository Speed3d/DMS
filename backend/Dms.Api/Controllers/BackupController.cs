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
        => Map(await backup.RunAsync(BackupType.Manual, ct));

    [HttpGet("schedule")]
    public async Task<ActionResult<BackupScheduleDto>> GetSchedule(CancellationToken ct)
        => MapSchedule(await backup.GetScheduleAsync(ct));

    [HttpPut("schedule")]
    public async Task<ActionResult<BackupScheduleDto>> UpdateSchedule(UpdateBackupScheduleRequest req, CancellationToken ct)
        => MapSchedule(await backup.UpdateScheduleAsync(new UpdateScheduleInput(req.Frequency, req.Enabled, req.Hour), ct));

    [HttpGet("{id:int}/download")]
    public async Task<IActionResult> Download(int id, CancellationToken ct)
    {
        var (bytes, fileName) = await backup.DownloadAsync(id, ct);
        return File(bytes, "application/zip", fileName);
    }

    private static BackupRecordDto Map(BackupRecord r) =>
        new(r.BackupRecordId, r.CreatedAt, r.CreatedByUserId, r.FileName, r.SizeBytes, r.Type, r.Status, r.Note);

    private static BackupScheduleDto MapSchedule(BackupSchedule s) =>
        new(s.Frequency, s.Enabled, s.Hour, s.LastRunAt, s.NextRunAt);
}
