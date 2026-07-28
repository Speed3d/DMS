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

    /// <summary>حالة تغطية النسخ — عمر آخر نسخة **كاملة** ومدى إلحاح أخذ واحدة جديدة.</summary>
    /// <remarks>
    /// 🔴 **لماذا هذه النقطة موجودة:** النسخ المجدولة صارت «قاعدة فقط» (لأن ٣٦ نسخة كاملة
    /// × 80 غيغا = 2.9 تيرابايت)، فهي **لا تحمي المرفقات**. حمايتها تعتمد على نسخة كاملة
    /// **يدوية** يأخذها المالك — و**أضعف حلقة في المنظومة هي ذاكرته**: لو نُسيت شهرين ثم
    /// تعطّل القرص ضاعت مرفقات شهرين، بينما النسخ اليومية تعمل بانتظام فتُعطي شعوراً زائفاً
    /// بالأمان. هذه النقطة تُحوّل «يدوي منسيّ» إلى «يدوي بتذكير».
    /// </remarks>
    [HttpGet("coverage")]
    public async Task<ActionResult<BackupCoverageDto>> Coverage(CancellationToken ct)
    {
        var records = await backup.ListAsync(ct);
        var lastFull = records
            .Where(r => r.Scope == BackupScope.Full && r.Status == BackupStatus.Success)
            .OrderByDescending(r => r.CreatedAt)
            .FirstOrDefault();

        var now = DateTime.UtcNow;
        var urgency = BackupRetention.ClassifyFullBackupAge(lastFull?.CreatedAt, now);
        var days = lastFull is null ? (int?)null : (int)(now - lastFull.CreatedAt).TotalDays;

        return new BackupCoverageDto(
            lastFull?.CreatedAt,
            days,
            BackupRetention.FullBackupMaxAgeDays,
            urgency.ToString(),
            MessageFor(urgency, days));
    }

    private static string MessageFor(BackupRetention.FullBackupUrgency u, int? days) => u switch
    {
        BackupRetention.FullBackupUrgency.Ok =>
            $"آخر نسخة كاملة قبل {days} يوماً — المرفقات محمية.",
        BackupRetention.FullBackupUrgency.Soon =>
            $"مضى {days} يوماً على آخر نسخة كاملة — يُستحسن أخذ واحدة خلال ٣ أيام.",
        BackupRetention.FullBackupUrgency.Urgent =>
            $"مضى {days} يوماً على آخر نسخة كاملة — تبقّى {BackupRetention.FullBackupMaxAgeDays - days} يوم/أيام.",
        _ => days is null
            ? "⚠️ لم تُؤخذ أي نسخة كاملة قط — المرفقات والأرشيف غير محميين من تعطّل القرص."
            : $"⚠️ مضى {days} يوماً على آخر نسخة كاملة (الحدّ {BackupRetention.FullBackupMaxAgeDays}) — المرفقات في خطر.",
    };

    [HttpPost("run")]
    public async Task<ActionResult<BackupRecordDto>> Run(CancellationToken ct)
        // النسخة اليدوية دائماً كاملة وتصنيفها Manual (لا تُقلَّم إلا عند تجاوز سقف كبير).
        => Map(await backup.RunAsync(BackupType.Manual, BackupScope.Full, RetentionCategory.Manual, ct));

    /// <summary>
    /// **مرآة كاملة** إلى مسار يحدّده المالك (قرص خارجي عادةً): قاعدة + كل الملفات.
    /// </summary>
    /// <remarks>
    /// تُضيف ولا تُكرّر: الموجود بالحجم نفسه يُتخطّى، فالمرة الأولى تنسخ الأرشيف كاملاً
    /// والمرات التالية دقائق. **لا مسار افتراضي** — يُدخله المالك في كل مرة (قراره).
    /// </remarks>
    [HttpPost("mirror")]
    public async Task<ActionResult<MirrorResult>> Mirror(MirrorRequest req, CancellationToken ct)
        => await backup.MirrorAsync(req.TargetPath, ct);

    /// <summary>استعادة من مرآة — تدميرية، تتطلب كلمة التأكيد نفسها.</summary>
    [HttpPost("mirror/restore")]
    public async Task<ActionResult<MirrorRestoreResult>> RestoreMirror(MirrorRestoreRequest req, CancellationToken ct)
        => await backup.RestoreFromMirrorAsync(req.SourcePath, req.Confirmation, ct);

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
