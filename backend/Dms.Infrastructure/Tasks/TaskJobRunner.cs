using Dms.Domain;
using Dms.Infrastructure.Notifications;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Tasks;

/// <summary>حصيلة دورةٍ واحدة — يقرؤها السجلّ و**يتحقّق منها E2E**.</summary>
public sealed record TaskJobResult(
    int Escalated, int DueSoonReminded, int RecurringCreated, int NotificationsPurged);

public interface ITaskJobRunner
{
    /// <summary>يُشغّل الدورة **مرّةً واحدة** — تستدعيها الخدمة الخلفية ونقطةُ التشغيل اليدوية.</summary>
    Task<TaskJobResult> RunOnceAsync(bool includePurge, CancellationToken ct = default);
}

/// <summary>
/// أعمال المهام الخلفية (ADR-039): التصعيد · تذكير الموعد · توليد المتكررة · التنظيف.
/// </summary>
/// <remarks>
/// 🔴 **هذه أول خدمةٍ خلفية تكتب بيانات في المشروع** — و<c>BackupScheduler</c> يقرأ جدولاً
/// واحداً وينسخ ملفات. وأربعة أخطارٍ هيكلية عولجت صراحةً:
///
/// <list type="number">
/// <item><b>X1 — الخدمة ترى كل الشركات.</b> <c>ICurrentUser</c> مسجَّل <c>Scoped</c> على
/// <c>HttpCurrentUser</c>، وفي نطاقٍ خلفي لا <c>HttpContext</c> ⇒ <c>IsAuthenticated =
/// false</c> ⇒ **<c>_filterByCompany = false</c> فلا فلتر شركة إطلاقاً**. ⇒ كل استعلامٍ هنا
/// **يُجمّع بـ<c>CompanyId</c> صراحةً**، والمستلِمون يُجلَبون بشركة المهمة نفسها.</item>
///
/// <item><b>X2 — الحالة تضيع بإعادة التشغيل.</b> الـAPI **خدمة ويندوز بتعافٍ تلقائي**
/// (ADR-016) تُعاد كثيراً، وحالةٌ في الذاكرة تعني **إعادة إرسال كل التصعيدات** بعد كل
/// إقلاع. ⇒ الحالة في **أعمدة على <c>DmsTask</c>** + <c>DedupKey</c> فريد في الإشعارات.
/// **حارسان لا واحد.**</item>
///
/// <item><b>X3 — تكاثر النُسَخ.</b> «كل ساعة: المتكررة المكتملة ⇐ أنشئ التالية» تعني نسخةً
/// **كل ساعة**. ⇒ الأمّ وحدها متكررة + فحصُ وجودٍ + **فهرس فريد مُرشَّح** في القاعدة.</item>
///
/// <item><b>X4 — النزاع مع الاستعادة.</b> أثناءها تكون القاعدة في <c>single-user</c>.
/// ⇒ **نفس حارس <c>BackupScheduler</c> حرفياً** — أول سطرٍ في الحلقة.</item>
/// </list>
/// </remarks>
public sealed class TaskJobRunner(
    AppDbContext db,
    INumberingService numbering,
    INotificationService notifications,
    IAuditService audit,
    ILogger<TaskJobRunner> logger) : ITaskJobRunner
{
    private const string CounterType = "Task";

    public async Task<TaskJobResult> RunOnceAsync(bool includePurge, CancellationToken ct = default)
    {
        var escalated = await EscalateOverdueAsync(ct);
        var reminded = await RemindDueSoonAsync(ct);
        var created = await GenerateRecurringAsync(ct);
        var purged = includePurge ? await notifications.PurgeOlderThanAsync(90, ct) : 0;

        return new TaskJobResult(escalated, reminded, created, purged);
    }

    // ─────────────────────────── ١) التصعيد ───────────────────────────

    private async Task<int> EscalateOverdueAsync(CancellationToken ct)
    {
        var today = LocalClock.Today;

        // ⚠️ **بلا فلتر شركة** — فالتجميع بـ`CompanyId` أدناه **إلزاميّ** لا تحسين (X1).
        var overdue = await db.DmsTasks
            .Where(t => !t.IsDeleted
                     && t.DueDate < today
                     && TaskWorkflow.ActiveStatuses.Contains(t.Status))
            .ToListAsync(ct);

        if (overdue.Count == 0) return 0;

        var count = 0;

        // 🔴 **التجميع بالشركة صريحٌ** — والمستلِمون يُجلَبون بشركة المهمة، فلا يتسرّب
        //    تصعيدُ شركةٍ إلى مديري أخرى.
        foreach (var group in overdue.GroupBy(t => t.CompanyId))
        {
            var companyId = group.Key;

            // ⚠️ **تُجلب قوائم المديرين والرئاسة مرّةً لكل شركة** لا لكل مهمة — عشرون مهمةً
            //    متأخرة تعني أربعين استعلاماً لولا ذلك.
            List<int>? managers = null;
            List<int>? presidency = null;

            foreach (var task in group)
            {
                var level = TaskEscalation.LevelFor(LocalClock.DaysOverdue(task.DueDate));
                if (!TaskEscalation.ShouldEscalate(level, task.LastEscalationLevel)) continue;

                List<int> recipients;
                switch (level)
                {
                    case 3:
                        presidency ??= await notifications.PresidencyOfCompanyAsync(companyId, ct);
                        recipients = presidency;
                        break;
                    case 2:
                        managers ??= await notifications.ManagersOfCompanyAsync(companyId, ct);
                        recipients = managers;
                        break;
                    default:
                        recipients = await FirstLevelRecipientsAsync(task, ct);
                        break;
                }

                if (recipients.Count > 0)
                {
                    await notifications.SendManyAsync(recipients, new NotificationInput(
                        RecipientUserId: 0,
                        CompanyId: companyId,
                        Title: TaskEscalation.TitleFor(level),
                        Body: $"{task.Title} — متأخرة {LocalClock.DaysOverdue(task.DueDate)} يوماً",
                        Category: NotificationKeys.TaskCategory,
                        EntityType: nameof(DmsTask),
                        EntityId: task.TaskId,
                        Priority: NotificationPriority.High,
                        DedupKey: NotificationKeys.TaskEscalation(task.TaskId, level)), ct);
                }

                // 🔴 **تُضبط الحالة حتى لو لم يوجد مستلِم** — وإلا أُعيدت المحاولة كل ساعة
                //    إلى الأبد على شركةٍ بلا مديرين.
                task.LastEscalationLevel = level;
                task.LastEscalatedAt = DateTime.UtcNow;
                count++;

                audit.Add($"System.TaskEscalation{level}", nameof(DmsTask),
                    task.TaskId.ToString(), $"تصعيد المستوى {level}", companyId);
            }
        }

        if (count > 0) await db.SaveChangesAsync(ct);
        return count;
    }

    /// <summary>مستلِمو المستوى الأول: المسؤول — أو **موظفو القسم** إن كانت مهمة قسم.</summary>
    private async Task<List<int>> FirstLevelRecipientsAsync(DmsTask task, CancellationToken ct)
    {
        if (task.AssignedToUserId is { } uid) return [uid];

        if (task.TaskType == DmsTaskType.Department && task.DepartmentId is { } dep)
            return await notifications.DepartmentMembersAsync(task.CompanyId, dep, ct);

        // مهمةٌ بلا مسؤولٍ ولا قسم — يُنبَّه مُنشئها، فلا يضيع التأخّر بلا أن يعلم به أحد.
        return [task.CreatedByUserId];
    }

    // ─────────────────────────── ٢) تذكير «يقترب موعده» ───────────────────────────

    private async Task<int> RemindDueSoonAsync(CancellationToken ct)
    {
        var tomorrow = LocalClock.Today.AddDays(1);

        var due = await db.DmsTasks
            .Where(t => !t.IsDeleted
                     && t.DueDate == tomorrow
                     && t.DueSoonNotifiedAt == null
                     && TaskWorkflow.ActiveStatuses.Contains(t.Status))
            .ToListAsync(ct);

        if (due.Count == 0) return 0;

        foreach (var task in due)
        {
            var recipients = await FirstLevelRecipientsAsync(task, ct);
            if (recipients.Count > 0)
            {
                await notifications.SendManyAsync(recipients, new NotificationInput(
                    RecipientUserId: 0,
                    CompanyId: task.CompanyId,
                    Title: "⏳ مهمة تستحق غداً",
                    Body: task.Title,
                    Category: NotificationKeys.TaskCategory,
                    EntityType: nameof(DmsTask),
                    EntityId: task.TaskId,
                    Priority: NotificationPriority.High,
                    DedupKey: NotificationKeys.TaskDueSoon(task.TaskId)), ct);
            }

            // ⚠️ **يُضبط دائماً** — نظير التصعيد: بلا ذلك يُعاد التذكير كل ساعة طوال اليوم.
            task.DueSoonNotifiedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        return due.Count;
    }

    // ─────────────────────────── ٣) توليد النسخة التالية ───────────────────────────

    /// <remarks>
    /// ⚠️ **التوليد يُطلقه الإنهاء لا مرورُ الوقت** (قرارُ تصميمٍ يجب أن يُعرف): نسخةٌ جديدة
    /// تُنشأ حين تُكمَل السابقة أو تُلغى — **لا كل أسبوعٍ بغضّ النظر**. فمهمةٌ أسبوعية لم
    /// تُنجَز لا تتراكم اثنتي عشرة نسخةً في الربع، **والقائمة تبقى صادقة**.
    /// </remarks>
    private async Task<int> GenerateRecurringAsync(CancellationToken ct)
    {
        // مهامٌّ منتهية تنتمي إلى سلسلة تكرار: إمّا أمٌّ متكررة، أو نسخةٌ لها أمّ.
        var finished = await db.DmsTasks
            .Where(t => !t.IsDeleted
                     && (t.Status == DmsTaskStatus.Completed || t.Status == DmsTaskStatus.Cancelled)
                     && (t.IsRecurring || t.ParentRecurringTaskId != null))
            .ToListAsync(ct);

        if (finished.Count == 0) return 0;

        var created = 0;

        foreach (var task in finished)
        {
            try
            {
                // رأس السلسلة يحمل النمط والفاصل والنهاية — والنسخ لا تحملها (D3).
                var head = task.IsRecurring
                    ? task
                    : await db.DmsTasks.FirstOrDefaultAsync(
                        t => t.TaskId == task.ParentRecurringTaskId!.Value, ct);

                if (head is null || !head.IsRecurring || head.RecurrencePattern is null) continue;

                var next = TaskRecurrence.NextDueDate(
                    task.DueDate, head.RecurrencePattern.Value,
                    head.RecurrenceInterval ?? 1, head.RecurrenceEndDate);

                if (next is null) continue;   // انتهت السلسلة

                // 🔴 **فحصُ وجودٍ قبل الإنشاء** — والفهرس الفريد المُرشَّح حارسٌ ثانٍ خلفه (X3).
                var exists = await db.DmsTasks.AnyAsync(
                    t => t.ParentRecurringTaskId == head.TaskId && t.DueDate == next.Value, ct);
                if (exists) continue;

                await CreateRecurringInstanceAsync(head, next.Value, ct);
                created++;
            }
            catch (Exception ex)
            {
                // ⚠️ **فشلُ نسخةٍ لا يُسقط البقية** — والسجلّ يقول أيّها فشلت.
                logger.LogError(ex, "تعذّر توليد نسخة متكررة من المهمة {TaskId}", task.TaskId);
            }
        }

        return created;
    }

    /// <remarks>
    /// ⚠️ **كلُّ نسخةٍ في معاملتها** لا كلُّهنّ في واحدة — فشلُ واحدةٍ لا يُسقط البقية.
    /// و**المعاملة مُغلَّفة بـ<c>CreateExecutionStrategy</c>** إلزاماً (<c>EnableRetryOnFailure</c>).
    /// </remarks>
    private async Task CreateRecurringInstanceAsync(DmsTask head, DateTime next, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();

        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            var year = next.Year;
            var serial = await numbering.NextSerialAsync(head.CompanyId, year, CounterType, ct);
            var prefix = await db.Companies.Where(c => c.CompanyId == head.CompanyId)
                .Select(c => c.Prefix).FirstOrDefaultAsync(ct) ?? "TSK";

            var copy = new DmsTask
            {
                CompanyId = head.CompanyId,
                Year = year,
                SerialNo = serial,
                TaskNumber = $"{prefix}-TSK-{year}-{serial:D5}",
                Title = head.Title,
                Description = head.Description,
                TaskType = head.TaskType,
                Priority = head.Priority,
                Status = DmsTaskStatus.New,
                ProgressPercent = 0,
                DueDate = LocalClock.CalendarDate(next),
                DepartmentId = head.DepartmentId,
                AssignedToUserId = head.AssignedToUserId,
                CreatedByUserId = head.CreatedByUserId,

                // 🔴 **بلا ربطٍ بالوثائق عمداً**: كتابُ الشهر الماضي ليس كتاب هذا الشهر،
                //    ونسخُ الربط يجعل اثنتي عشرة مهمةً تشير إلى كتابٍ واحدٍ قديم.
                RelatedIncomingId = null,
                RelatedOutgoingId = null,

                // **النسخة عاديّة لا متكررة** — وإلا أنجبت هي الأخرى (X3).
                IsRecurring = false,
                ParentRecurringTaskId = head.TaskId,

                Notes = head.Notes,
                CreatedAt = DateTime.UtcNow,
            };

            db.DmsTasks.Add(copy);
            await db.SaveChangesAsync(ct);

            db.DmsTaskUpdates.Add(new DmsTaskUpdate
            {
                TaskId = copy.TaskId,
                CompanyId = copy.CompanyId,
                UpdateType = DmsTaskUpdateType.Created,
                Description = $"أُنشئت تلقائياً من مهمة متكررة ({head.TaskNumber})",
                UpdatedByUserId = head.CreatedByUserId,
                UpdatedAt = DateTime.UtcNow,
            });

            // ⚠️ **`System.` بادئةً وفاعلٌ فارغ** — العمليات الخلفية بلا مستخدم، و`AuditService`
            //    يقبل `UserId = null` (تُحقّق منه قبل الاعتماد عليه).
            audit.Add("System.TaskRecurrenceCreated", nameof(DmsTask), copy.TaskId.ToString(),
                $"نسخة من {head.TaskNumber}", copy.CompanyId);

            if (copy.AssignedToUserId is { } uid)
            {
                await notifications.SendAsync(new NotificationInput(
                    RecipientUserId: uid,
                    CompanyId: copy.CompanyId,
                    Title: "مهمة متكررة جديدة",
                    Body: copy.Title,
                    Category: NotificationKeys.TaskCategory,
                    EntityType: nameof(DmsTask),
                    EntityId: copy.TaskId,
                    Priority: NotificationPriority.Normal,
                    DedupKey: NotificationKeys.TaskAssigned(copy.TaskId)), ct);
            }

            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
    }
}
