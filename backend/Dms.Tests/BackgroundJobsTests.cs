using Dms.Domain;
using Dms.Infrastructure.Jobs;
using Dms.Infrastructure.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;

namespace Dms.Tests;

/// <summary>
/// حرّاس **محرّك العمليات الخلفية** — النسخ والاستعادة والمرآة وحذف الشركة تجري خارج الطلب
/// لأن Cloudflare يقطع كلَّ طلبٍ لا يردّ خلال ~100 ثانية.
/// </summary>
/// <remarks>
/// ⚠️ **ما يُحرس هنا هو ما يجعل النقل آمناً لا ما يجعله يعمل**: القفل الحصريّ (لا عمليتان
/// ثقيلتان معاً) · وأن الفشل **يُقال بسببه** · وأن القفل **يُحرَّر** بعد كل نهاية · وأن التنفيذ
/// يحمل **هوية من بدأه** لا هويةً فارغة (وإلا سُجّل التدقيق بلا فاعل وسقط فلتر الشركة).
/// </remarks>
public class BackgroundJobsTests
{
    private static (BackgroundJobs jobs, ServiceProvider sp) Create()
    {
        var services = new ServiceCollection();
        services.AddScoped<CurrentUserOverride>();
        services.AddScoped<ICurrentUser>(p => p.GetRequiredService<CurrentUserOverride>().User ?? new SystemUser());
        var sp = services.BuildServiceProvider();
        var jobs = new BackgroundJobs(sp.GetRequiredService<IServiceScopeFactory>(),
            new FakeLifetime(), NullLogger<BackgroundJobs>.Instance);
        return (jobs, sp);
    }

    private static CurrentUserSnapshot User(int id, int? company = 7) => new()
    {
        IsAuthenticated = true, UserId = id, Role = UserRole.SuperAdmin, IsSuperAdmin = true,
        ActiveCompanyId = company, AllowedModules = AppModule.AllWithHr,
    };

    private static async Task<JobInfo> WaitAsync(IBackgroundJobs jobs, Guid id)
    {
        for (var i = 0; i < 200; i++)
        {
            var j = jobs.Get(id)!;
            if (j.State != JobState.Running) return j;
            await Task.Delay(10);
        }
        throw new TimeoutException("لم تنتهِ العملية");
    }

    [Fact]
    public async Task Start_ReturnsImmediately_ThenSucceedsWithResultAndMessage()
    {
        var (jobs, _) = Create();
        var gate = new TaskCompletionSource();

        var job = jobs.Start("backup", "نسخة", User(1), async (_, p, _) =>
        {
            await gate.Task;
            p.Succeed("تمت");
            return 42;
        });

        // يعود **قبل** أن تنتهي العملية — وهو كلّ الغرض.
        Assert.Equal(JobState.Running, job.State);
        gate.SetResult();

        var done = await WaitAsync(jobs, job.Id);
        Assert.Equal(JobState.Succeeded, done.State);
        Assert.Equal(42, done.Result);
        Assert.Equal("تمت", done.Message);
        Assert.Equal(100, done.Percent);
        Assert.NotNull(done.FinishedAt);
    }

    [Fact]
    public async Task SecondHeavyJob_WhileFirstRuns_IsRefusedWithItsTitle()
    {
        var (jobs, _) = Create();
        var gate = new TaskCompletionSource();
        var first = jobs.Start("restore", "استعادة نسخة احتياطية", User(1), async (_, _, _) => { await gate.Task; return null; });

        var ex = Assert.Throws<ConflictException>(() =>
            jobs.Start("backup", "نسخة", User(1), (_, _, _) => Task.FromResult<object?>(null)));
        Assert.Contains("استعادة نسخة احتياطية", ex.Message);
        Assert.Same(first, jobs.Current);

        gate.SetResult();
        await WaitAsync(jobs, first.Id);
    }

    [Fact]
    public async Task LockIsReleased_AfterSuccess_AndAfterFailure()
    {
        var (jobs, _) = Create();

        var ok = jobs.Start("a", "أ", User(1), (_, _, _) => Task.FromResult<object?>(null));
        await WaitAsync(jobs, ok.Id);

        var bad = jobs.Start("b", "ب", User(1), (_, _, _) => throw new InvalidOperationException("x"));
        await WaitAsync(jobs, bad.Id);

        // لو بقي القفل محجوزاً لرُفضت هذه — وهو بعينه «زرٌّ لا يعمل بعد أوّل فشل».
        var again = jobs.Start("c", "ج", User(1), (_, _, _) => Task.FromResult<object?>(null));
        Assert.Equal(JobState.Succeeded, (await WaitAsync(jobs, again.Id)).State);
        Assert.Null(jobs.Current);
    }

    [Fact]
    public async Task DomainFailure_KeepsItsArabicMessage()
    {
        var (jobs, _) = Create();
        var job = jobs.Start("backup", "نسخة", User(1),
            (_, _, _) => throw new ConflictException("انتهت النسخة بالفشل: القرص ممتلئ"));

        var done = await WaitAsync(jobs, job.Id);
        Assert.Equal(JobState.Failed, done.State);
        Assert.Equal("انتهت النسخة بالفشل: القرص ممتلئ", done.Message);
    }

    [Fact]
    public async Task UnexpectedFailure_IsReportedNotSwallowed()
    {
        var (jobs, _) = Create();
        var job = jobs.Start("backup", "نسخة", User(1),
            (_, _, _) => throw new IOException("Access denied"));

        var done = await WaitAsync(jobs, job.Id);
        Assert.Equal(JobState.Failed, done.State);
        Assert.Contains("Access denied", done.Message);
    }

    [Fact]
    public async Task Work_RunsAsTheUserWhoStartedIt_NotAnEmptyIdentity()
    {
        var (jobs, _) = Create();
        ICurrentUser? seen = null;

        var job = jobs.Start("delete-company", "حذف", User(5, company: 3), (sp, _, _) =>
        {
            seen = sp.GetRequiredService<ICurrentUser>();
            return Task.FromResult<object?>(null);
        });
        await WaitAsync(jobs, job.Id);

        Assert.NotNull(seen);
        Assert.True(seen!.IsAuthenticated);
        Assert.Equal(5, seen.UserId);
        Assert.Equal(3, seen.ActiveCompanyId);
        Assert.Equal(5, job.StartedByUserId);
    }

    [Fact]
    public async Task Snapshot_IsTakenAtStart_LaterChangesDoNotLeakIn()
    {
        var (jobs, _) = Create();
        var source = new MutableUser { UserId = 1 };
        var gate = new TaskCompletionSource();
        int? seenId = null;

        var job = jobs.Start("backup", "نسخة", source, async (sp, _, _) =>
        {
            await gate.Task;
            seenId = sp.GetRequiredService<ICurrentUser>().UserId;
            return null;
        });
        source.UserId = 99;
        gate.SetResult();
        await WaitAsync(jobs, job.Id);

        Assert.Equal(1, seenId);
    }

    [Fact]
    public async Task InlineLease_BlocksJobs_UntilDisposed()
    {
        var (jobs, _) = Create();

        var lease = jobs.TryBeginExclusive("نسخة احتياطية مجدولة");
        Assert.NotNull(lease);
        Assert.Null(jobs.TryBeginExclusive("أخرى"));

        var ex = Assert.Throws<ConflictException>(() =>
            jobs.Start("backup", "نسخة", User(1), (_, _, _) => Task.FromResult<object?>(null)));
        Assert.Contains("نسخة احتياطية مجدولة", ex.Message);

        lease!.Dispose();
        lease.Dispose(); // تحريرٌ مزدوج لا يُفسد العدّاد

        var job = jobs.Start("backup", "نسخة", User(1), (_, _, _) => Task.FromResult<object?>(null));
        await WaitAsync(jobs, job.Id);
        Assert.NotNull(jobs.TryBeginExclusive("بعد"));
    }

    [Fact]
    public async Task Progress_IsReportedAndClamped()
    {
        var (jobs, _) = Create();
        var gate = new TaskCompletionSource();
        var reported = new TaskCompletionSource();

        var job = jobs.Start("mirror", "مرآة", User(1), async (_, p, _) =>
        {
            p.Report("نسخ الملفات (3 من 10)", 130);
            reported.SetResult();
            await gate.Task;
            return null;
        });
        await reported.Task;

        Assert.Equal("نسخ الملفات (3 من 10)", jobs.Get(job.Id)!.Stage);
        Assert.Equal(100, jobs.Get(job.Id)!.Percent);

        gate.SetResult();
        await WaitAsync(jobs, job.Id);
    }

    [Fact]
    public void UnknownJob_IsNull()
    {
        var (jobs, _) = Create();
        Assert.Null(jobs.Get(Guid.NewGuid()));
        Assert.Null(jobs.Current);
    }

    private sealed class FakeLifetime : IHostApplicationLifetime
    {
        public CancellationToken ApplicationStarted => CancellationToken.None;
        public CancellationToken ApplicationStopping => CancellationToken.None;
        public CancellationToken ApplicationStopped => CancellationToken.None;
        public void StopApplication() { }
    }

    private sealed class MutableUser : ICurrentUser
    {
        public bool IsAuthenticated => true;
        public int? UserId { get; set; }
        public UserRole? Role => UserRole.SuperAdmin;
        public int? ActiveCompanyId => null;
        public bool IsSuperAdmin => true;
        public bool CanApprove => true;
        public bool CanManageIncoming => true;
        public bool CanViewAllIncoming => true;
        public bool CanManageEmployees => true;
        public bool CanManagePayroll => true;
        public bool CanAmendPaidPayroll => true;
        public bool CanManageTasks => true;
        public int? DepartmentId => null;
        public List<int> AllowedCompanyIds => new();
        public AppModule AllowedModules => AppModule.AllWithHr;
    }
}
