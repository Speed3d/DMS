using System.Collections.Concurrent;
using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Jobs;

/// <summary>حالة العملية الخلفية.</summary>
public enum JobState
{
    Running = 0,
    Succeeded = 1,
    Failed = 2,
}

/// <summary>مُبلّغ التقدّم — تناديه العملية لتقول أين وصلت.</summary>
public interface IJobProgress
{
    /// <param name="stage">وصفٌ عربيّ للمرحلة الجارية (يُعرض كما هو).</param>
    /// <param name="percent">نسبةٌ من 0 إلى 100، أو <c>null</c> إن لم تُعرف.</param>
    void Report(string stage, int? percent = null);

    /// <summary>رسالة النجاح التي تُعرض للمالك عند الانتهاء.</summary>
    void Succeed(string message);
}

/// <summary>لقطةٌ من حالة عمليةٍ خلفية — تُقرأ بالسؤال الدوريّ.</summary>
public sealed class JobInfo
{
    public Guid Id { get; init; }
    public string Kind { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public int? StartedByUserId { get; init; }
    public DateTime StartedAt { get; init; }

    /// <remarks>
    /// ⚠️ **حقلٌ `volatile`**: تكتبه العملية في خيطها ويقرؤه طلبُ المتابعة في خيطٍ آخر —
    /// **وهو آخرُ ما يُكتب** عند الانتهاء (بعد تحرير القفل)، فمن يراه منتهياً يجد القفل حرّاً.
    /// </remarks>
    public JobState State { get => _state; internal set => _state = value; }
    private volatile JobState _state = JobState.Running;
    public string? Stage { get; internal set; }
    public int? Percent { get; internal set; }

    /// <summary>رسالة النهاية — نجاحاً أو فشلاً.</summary>
    public string? Message { get; internal set; }

    /// <summary>حصيلة العملية (سجلّ النسخة · نتيجة المرآة …) — تُسلسَل كما هي.</summary>
    public object? Result { get; internal set; }

    public DateTime? FinishedAt { get; internal set; }
}

/// <summary>
/// العمليات الطويلة **خارج الطلب** — نسخٌ واستعادةٌ ومرآةٌ وحذفُ شركة.
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **لماذا وُجدت؟** خلف Cloudflare **يُقطع كلُّ طلبٍ لا يبدأ ردُّه خلال ~100 ثانية** (الخطأ
/// 524). وكانت هذه العمليات تجري **داخل الطلب** ولا تردّ إلا بعد انتهائها — فيرى المالك
/// «فشلاً» والعملية ربما ما زالت تعمل، فيُعيدها فتعمل مرّتين معاً. **والاستعادة أخطرها**:
/// انقطاعُها في منتصفها قد يترك القاعدة في حالةٍ تحتاج تدخّلاً يدوياً.
/// </para>
/// <para>
/// ✅ **الآن**: الزرّ يبدأ العملية ويعود **فوراً** برقمها، والشاشة تسأل عن تقدّمها. والعملية
/// **لا تُلغى بانقطاع الطلب** — بل بإيقاف الخدمة وحده.
/// </para>
/// <para>
/// 🔐 **عمليةٌ ثقيلةٌ واحدة في كلّ وقت** — نسختان متزامنتان على القرص نفسه تُبطئان كلتيهما،
/// ونسخةٌ أثناء استعادةٍ تنازعها القاعدة. **والنسخة المجدولة تحترم القفل نفسه.**
/// </para>
/// <para>
/// ⚠️ **الحالة في الذاكرة لا في القاعدة — عمداً**: الاستعادة **تستبدل القاعدة نفسها**، فسجلُّ
/// العملية فيها كان سيُمحى أثناءها. والثمن معلَن: إعادةُ تشغيل الخادم تمحو السجلّ، فتقول
/// الشاشة «انقطعت العملية» بدل أن تبقى معلّقة.
/// </para>
/// </remarks>
public interface IBackgroundJobs
{
    /// <summary>يبدأ عمليةً ثقيلة ويعود فوراً — أو يرمي <see cref="ConflictException"/> إن كانت أخرى جارية.</summary>
    /// <param name="startedBy">المستخدم الحالي — تُؤخذ منه لقطةٌ يحملها التنفيذ.</param>
    /// <param name="work">
    /// التنفيذ: يُعطى مزوّد خدماتٍ **من نطاقٍ جديد** (المستخدم فيه هو اللقطة) ومُبلّغَ التقدّم
    /// ورمزَ إيقاف الخدمة. ويعيد حصيلةً تُعرض.
    /// </param>
    JobInfo Start(string kind, string title, ICurrentUser startedBy,
        Func<IServiceProvider, IJobProgress, CancellationToken, Task<object?>> work);

    JobInfo? Get(Guid id);

    /// <summary>العملية الثقيلة الجارية الآن — لتستأنف الشاشة متابعتها بعد إعادة التحميل.</summary>
    JobInfo? Current { get; }

    /// <summary>
    /// حجزُ القفل الحصريّ لعملٍ **يجري في مكانه** (النسخة المجدولة) — <c>null</c> إن كان مشغولاً.
    /// </summary>
    IDisposable? TryBeginExclusive(string title);
}

public sealed class BackgroundJobs(
    IServiceScopeFactory scopes,
    IHostApplicationLifetime lifetime,
    ILogger<BackgroundJobs> logger) : IBackgroundJobs
{
    /// <summary>مدّة بقاء العملية المنتهية في الذاكرة — تكفي لتقرأ الشاشة نتيجتها.</summary>
    private static readonly TimeSpan Retention = TimeSpan.FromHours(24);

    private readonly ConcurrentDictionary<Guid, JobInfo> _jobs = new();
    private readonly SemaphoreSlim _exclusive = new(1, 1);
    private volatile JobInfo? _current;
    private volatile string? _inlineTitle;

    public JobInfo? Current => _current;

    public JobInfo? Get(Guid id) => _jobs.TryGetValue(id, out var j) ? j : null;

    public IDisposable? TryBeginExclusive(string title)
    {
        if (!_exclusive.Wait(0)) return null;
        _inlineTitle = title;
        return new Lease(() => { _inlineTitle = null; _exclusive.Release(); });
    }

    public JobInfo Start(string kind, string title, ICurrentUser startedBy,
        Func<IServiceProvider, IJobProgress, CancellationToken, Task<object?>> work)
    {
        if (!_exclusive.Wait(0))
        {
            var busy = _current?.Title ?? _inlineTitle ?? "عملية أخرى";
            throw new ConflictException($"«{busy}» جاريةٌ الآن — انتظر حتى تنتهي ثم أعد المحاولة.");
        }

        try
        {
            Prune();
            var snapshot = CurrentUserSnapshot.From(startedBy);
            var job = new JobInfo
            {
                Id = Guid.NewGuid(),
                Kind = kind,
                Title = title,
                StartedByUserId = snapshot.UserId,
                StartedAt = DateTime.UtcNow,
                Stage = "في الانتظار",
            };
            _jobs[job.Id] = job;
            _current = job;

            // 🔴 **لا يرث التنفيذُ سياقَ الطلب**: `HttpContextAccessor` يحمل الطلب في AsyncLocal،
            //    وبلا هذا يرى التنفيذ طلباً انتهى وأُعيد تدويره لطلبٍ آخر.
            using (ExecutionContext.SuppressFlow())
            {
                _ = Task.Run(() => RunAsync(job, snapshot, work));
            }
            return job;
        }
        catch
        {
            // ⚠️ فشلٌ **قبل** أن يبدأ التنفيذ لا يجوز أن يترك القفل محجوزاً للأبد.
            _current = null;
            _exclusive.Release();
            throw;
        }
    }

    private async Task RunAsync(JobInfo job, CurrentUserSnapshot snapshot,
        Func<IServiceProvider, IJobProgress, CancellationToken, Task<object?>> work)
    {
        var final = JobState.Failed;
        try
        {
            using var scope = scopes.CreateScope();
            // ⚠️ **قبل حلّ أيّ خدمة** — `AppDbContext` يبني فلتر الشركة من المستخدم في مُنشئه.
            scope.ServiceProvider.GetRequiredService<CurrentUserOverride>().User = snapshot;

            job.Result = await work(scope.ServiceProvider, new Progress(job), lifetime.ApplicationStopping);
            job.Stage = "اكتملت";
            job.Percent = 100;
            final = JobState.Succeeded;
        }
        catch (Exception ex)
        {
            job.Message = ex switch
            {
                DomainException d => d.Message,
                OperationCanceledException => "أُوقفت العملية لأن الخادم يُغلَق — أعد تشغيلها بعد عودته.",
                _ => "حدث خطأ غير متوقّع: " + ex.Message,
            };
            if (ex is not DomainException)
                logger.LogError(ex, "فشلت العملية الخلفية {Kind} ({Id})", job.Kind, job.Id);
        }
        finally
        {
            job.FinishedAt = DateTime.UtcNow;
            _current = null;
            _exclusive.Release();

            // 🔴 **الحالة النهائية تُعلَن آخراً — بعد تحرير القفل لا قبله.** كانت تُكتب أوّلاً
            //    فكانت بين اللحظتين نافذةٌ: من يرى «انتهت» ويبدأ عمليةً فوراً **يُرفض بأن
            //    المنتهية ما زالت جارية**. كشفها حارسُ الوحدة متذبذباً (مرّةً في ~12 تشغيلاً
            //    للمجموعة كاملة) لا المراجعة — وهو عيبُ ترتيبٍ لا عيبُ اختبار.
            job.State = final;
        }
    }

    private void Prune()
    {
        var cutoff = DateTime.UtcNow - Retention;
        foreach (var (id, j) in _jobs)
            if (j.FinishedAt is { } f && f < cutoff) _jobs.TryRemove(id, out _);
    }

    private sealed class Progress(JobInfo job) : IJobProgress
    {
        public void Report(string stage, int? percent = null)
        {
            job.Stage = stage;
            job.Percent = percent is null ? null : Math.Clamp(percent.Value, 0, 100);
        }

        public void Succeed(string message) => job.Message = message;
    }

    private sealed class Lease(Action release) : IDisposable
    {
        private int _done;
        public void Dispose() { if (Interlocked.Exchange(ref _done, 1) == 0) release(); }
    }
}
