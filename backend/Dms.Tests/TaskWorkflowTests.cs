using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس دورة حياة المهمة — المصفوفة المغلقة وقاعدة التأخّر (ADR-037).
/// </summary>
public class TaskWorkflowTests
{
    [Theory]
    [InlineData(DmsTaskStatus.New, DmsTaskStatus.InProgress)]
    [InlineData(DmsTaskStatus.New, DmsTaskStatus.Cancelled)]
    [InlineData(DmsTaskStatus.InProgress, DmsTaskStatus.OnHold)]
    [InlineData(DmsTaskStatus.InProgress, DmsTaskStatus.Completed)]
    [InlineData(DmsTaskStatus.OnHold, DmsTaskStatus.InProgress)]
    [InlineData(DmsTaskStatus.Completed, DmsTaskStatus.Reopened)]
    [InlineData(DmsTaskStatus.Reopened, DmsTaskStatus.InProgress)]
    public void AllowedTransitions_Pass(DmsTaskStatus from, DmsTaskStatus to)
    {
        Assert.True(TaskWorkflow.CanTransition(from, to));
        TaskWorkflow.EnsureTransitionAllowed(from, to);   // لا يرمي
    }

    [Theory]
    [InlineData(DmsTaskStatus.New, DmsTaskStatus.Completed)]        // لا قفزَ فوق التنفيذ
    [InlineData(DmsTaskStatus.New, DmsTaskStatus.OnHold)]           // لا تعليقَ لما لم يبدأ
    [InlineData(DmsTaskStatus.OnHold, DmsTaskStatus.Completed)]     // تُستأنف أولاً
    [InlineData(DmsTaskStatus.Completed, DmsTaskStatus.InProgress)] // تُعاد فتحاً لا استئنافاً
    [InlineData(DmsTaskStatus.Reopened, DmsTaskStatus.Completed)]   // تمرّ بالتنفيذ ثانيةً
    public void ForbiddenTransitions_AreRejected(DmsTaskStatus from, DmsTaskStatus to)
    {
        Assert.False(TaskWorkflow.CanTransition(from, to));
        Assert.Throws<ValidationException>(() => TaskWorkflow.EnsureTransitionAllowed(from, to));
    }

    [Fact]
    public void Cancelled_IsTerminal_WithNoWayBack()
    {
        // 🔴 الإلغاء عدولٌ عن العمل لا تعليقٌ له — وإعادةُ فتحه تعني أنه لم يُلغَ أصلاً.
        Assert.Empty(TaskWorkflow.NextStatuses(DmsTaskStatus.Cancelled));

        foreach (var to in Enum.GetValues<DmsTaskStatus>())
            Assert.False(TaskWorkflow.CanTransition(DmsTaskStatus.Cancelled, to));
    }

    [Fact]
    public void Completed_ReopensOnly_NotStraightBackToWork()
    {
        var next = TaskWorkflow.NextStatuses(DmsTaskStatus.Completed);
        Assert.Single(next);
        Assert.Equal(DmsTaskStatus.Reopened, next[0]);
    }

    [Fact]
    public void StayingOnTheSameStatus_IsNotATransition()
    {
        foreach (var s in Enum.GetValues<DmsTaskStatus>())
        {
            Assert.False(TaskWorkflow.CanTransition(s, s));
            Assert.Throws<ValidationException>(() => TaskWorkflow.EnsureTransitionAllowed(s, s));
        }
    }

    [Theory]
    [InlineData(DmsTaskStatus.New, true)]
    [InlineData(DmsTaskStatus.InProgress, true)]
    [InlineData(DmsTaskStatus.OnHold, true)]
    [InlineData(DmsTaskStatus.Reopened, true)]
    [InlineData(DmsTaskStatus.Completed, false)]
    [InlineData(DmsTaskStatus.Cancelled, false)]
    public void IsActive_DrivesEscalationAndOverdue(DmsTaskStatus status, bool expected)
        => Assert.Equal(expected, TaskWorkflow.IsActive(status));

    [Fact]
    public void TaskDueToday_IsNotOverdue_BecauseTheDayIsNotOverYet()
    {
        // 🔴 جوهر قرار «الموعد يومٌ لا لحظة»: مهمةٌ موعدها اليوم ليست متأخّرة اليوم — ولولاه
        //    لصارت حمراء الساعة 3:00 فجراً من يومها نفسه (فرقُ توقيت بغداد عن UTC).
        Assert.False(TaskWorkflow.IsOverdue(DmsTaskStatus.InProgress, LocalClock.Today));
        Assert.False(TaskWorkflow.IsOverdue(DmsTaskStatus.InProgress, LocalClock.Today.AddHours(23)));
    }

    [Fact]
    public void TaskDueYesterday_IsOverdue_UnlessItIsDone()
    {
        var yesterday = LocalClock.Today.AddDays(-1);

        Assert.True(TaskWorkflow.IsOverdue(DmsTaskStatus.InProgress, yesterday));

        // ومكتملةٌ بعد موعدها ليست «متأخرة» — تصعيدُها إزعاجٌ بلا معلومة.
        Assert.False(TaskWorkflow.IsOverdue(DmsTaskStatus.Completed, yesterday));
        Assert.False(TaskWorkflow.IsOverdue(DmsTaskStatus.Cancelled, yesterday));
    }

    [Fact]
    public void EveryStatusAndPriority_HasAnArabicName()
    {
        // نظير حارس `AuditLabels`: اسمٌ إنجليزيّ يتسرّب إلى رسالة خطأ أو سجلّ يقرؤه المالك.
        foreach (var s in Enum.GetValues<DmsTaskStatus>())
            Assert.NotEqual(s.ToString(), TaskWorkflow.ArabicName(s));

        foreach (var p in Enum.GetValues<DmsTaskPriority>())
            Assert.NotEqual(p.ToString(), TaskWorkflow.ArabicName(p));

        foreach (var t in Enum.GetValues<DmsTaskType>())
            Assert.NotEqual(t.ToString(), TaskWorkflow.ArabicName(t));
    }
}
