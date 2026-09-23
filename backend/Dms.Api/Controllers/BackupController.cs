using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Backup;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin")] // النسخ الاحتياطي للسوبر أدمن فقط
[RequireModule(AppModule.Backup)]
[Route("api/[controller]")]
public sealed class BackupController(IBackupService backup, IBackgroundJobs jobs, ICurrentUser current) : ControllerBase
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

    // ════════ العمليات الطويلة — تبدأ هنا وتجري في الخلفية (حدّ Cloudflare ~100 ثانية) ════════
    //
    // 🔴 **كلُّها تردّ 202 فوراً برقم العملية**، والشاشة تسأل `GET /api/system/jobs/{id}`.
    //    كانت تجري **داخل الطلب** فلا تردّ إلا بعد انتهائها — وخلف النفق يُقطع الطلب بعد
    //    ~100 ثانية بالخطأ 524 والعملية ما زالت تعمل، فيظنّها المالك فشلت ويُعيدها.
    // ⚠️ **والفحوص قبل البدء لا بعده**: كلمة تأكيدٍ خاطئة أو مسارٌ مرفوض يعود 400 **فوراً**
    //    كما كان تماماً — لا فشلاً في شاشة المتابعة بعد ثوانٍ.

    [HttpPost("run")]
    public ActionResult<JobResponse> Run()
    {
        // النسخة اليدوية دائماً كاملة وتصنيفها Manual (لا تُقلَّم إلا عند تجاوز سقف كبير).
        var job = jobs.Start("backup", "نسخة احتياطية كاملة", current, async (sp, progress, ct) =>
        {
            var rec = await sp.GetRequiredService<IBackupService>()
                .RunAsync(BackupType.Manual, BackupScope.Full, RetentionCategory.Manual, ct, progress);
            // ⚠️ **نسخةٌ فاشلة فشلٌ لا نجاح** — سجلُّها محفوظ في القائمة، والعملية تقول «فشلت».
            if (rec.Status != BackupStatus.Success)
                throw new ConflictException("انتهت النسخة بالفشل: " + (rec.Note ?? "سببٌ غير معروف"));
            progress.Succeed($"تمت النسخة الاحتياطية ({SizeText(rec.SizeBytes)}).");
            return Map(rec);
        });
        return Accepted(JobResponse.From(job));
    }

    private static string SizeText(long b) =>
        b >= 1L << 30 ? $"{b / (double)(1L << 30):0.0} GB"
        : b >= 1L << 20 ? $"{b / (double)(1L << 20):0.0} MB"
        : $"{b / 1024.0:0} KB";

    /// <summary>
    /// **مرآة كاملة** إلى مسار يحدّده المالك (قرص خارجي عادةً): قاعدة + كل الملفات.
    /// </summary>
    /// <remarks>
    /// تُضيف ولا تُكرّر: الموجود بالحجم نفسه يُتخطّى، فالمرة الأولى تنسخ الأرشيف كاملاً
    /// والمرات التالية دقائق. **لا مسار افتراضي** — يُدخله المالك في كل مرة (قراره).
    /// </remarks>
    [HttpPost("mirror")]
    public ActionResult<JobResponse> Mirror(MirrorRequest req)
    {
        backup.ValidateMirrorTarget(req.TargetPath);
        var target = req.TargetPath;
        var job = jobs.Start("mirror", "مرآة كاملة إلى قرص خارجي", current, async (sp, progress, ct) =>
        {
            var r = await sp.GetRequiredService<IBackupService>().MirrorAsync(target, ct, progress);
            progress.Succeed($"المرآة اكتملت في {r.TargetPath} — نُسخ {r.Copied} ملفاً، وتُخطّي {r.Skipped} موجوداً سلفاً."
                + (r.DatabaseOk ? "" : $" ⚠️ لكن قاعدة البيانات لم تُنسخ: {r.Note}"));
            return r;
        });
        return Accepted(JobResponse.From(job));
    }

    /// <summary>استعادة من مرآة — تدميرية، تتطلب كلمة التأكيد نفسها.</summary>
    [HttpPost("mirror/restore")]
    public ActionResult<JobResponse> RestoreMirror(MirrorRestoreRequest req)
    {
        backup.EnsureMirrorRestorable(req.SourcePath, req.Confirmation);
        var (source, confirmation) = (req.SourcePath, req.Confirmation);
        var job = jobs.Start("mirror-restore", "استعادة من مرآة", current, async (sp, progress, ct) =>
        {
            var r = await sp.GetRequiredService<IBackupService>()
                .RestoreFromMirrorAsync(source, confirmation, ct, progress);
            progress.Succeed(r.Message);
            return r;
        });
        return Accepted(JobResponse.From(job));
    }

    /// <summary>استعادة نسخة احتياطية — عملية تدميرية تتطلب كلمة تأكيد في الجسم.</summary>
    [HttpPost("{id:int}/restore")]
    public async Task<ActionResult<JobResponse>> Restore(int id, RestoreBackupRequest req, CancellationToken ct)
    {
        await backup.EnsureRestorableAsync(id, req.Confirmation, ct);
        var confirmation = req.Confirmation;
        var job = jobs.Start("restore", "استعادة نسخة احتياطية", current, async (sp, progress, stop) =>
        {
            // رسالة النجاح (ومعها فجوة المرفقات إن وُجدت) تكتبها الخدمة نفسها.
            await sp.GetRequiredService<IBackupService>().RestoreAsync(id, confirmation, stop, progress);
            return null;
        });
        return Accepted(JobResponse.From(job));
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
        // 🔴 **تدفّقٌ من القرص لا مصفوفةٌ في الذاكرة**: كان الملف يُقرأ كلُّه قبل أوّل بايت
        //    (فيقطعه Cloudflare بعد ~100 ثانية) ويفشل تماماً فوق 2 غيغابايت.
        var (path, _) = await backup.GetFileAsync(id, ct);
        // بلا اسم ملف عمداً: الشاشة تجلب البايتات بـXHR وتحفظها باسم النسخة من بياناتها،
        // وترويسةُ «تنزيل» تجعل مديري التحميل يختطفون الطلب فلا يصل ردّ (نفس علّة ADR-019).
        return PhysicalFile(path, "application/zip");
    }

    private static BackupRecordDto Map(BackupRecord r) =>
        new(r.BackupRecordId, r.CreatedAt, r.CreatedByUserId, r.FileName, r.SizeBytes, r.Type, r.Scope, r.Category, r.Status, r.Note);

    private static BackupScheduleDto MapSchedule(BackupSchedule s) =>
        new(s.Frequency, s.Enabled, s.Hour, s.LastRunAt, s.NextRunAt);
}
