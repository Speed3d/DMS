using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>اختبارات مصفوفة انتقالات حالة الكتاب الوارد (Hint: تحمي دورة الحياة من الانتقالات العكسية).</summary>
public class IncomingWorkflowTests
{
    [Theory]
    [InlineData(IncomingStatus.New, IncomingStatus.InReview)]
    [InlineData(IncomingStatus.New, IncomingStatus.Closed)]        // كتاب لا يحتاج رداً
    [InlineData(IncomingStatus.InReview, IncomingStatus.Replied)]
    [InlineData(IncomingStatus.InReview, IncomingStatus.Closed)]
    [InlineData(IncomingStatus.Replied, IncomingStatus.Closed)]
    [InlineData(IncomingStatus.Closed, IncomingStatus.Archived)]
    public void AllowsPlannedTransitions(IncomingStatus from, IncomingStatus to)
    {
        Assert.True(IncomingWorkflow.CanTransition(from, to));
        IncomingWorkflow.EnsureTransitionAllowed(from, to);   // لا يرمي
    }

    [Theory]
    [InlineData(IncomingStatus.Archived, IncomingStatus.New)]        // إحياء سجل مؤرشف
    [InlineData(IncomingStatus.Archived, IncomingStatus.InReview)]
    [InlineData(IncomingStatus.Closed, IncomingStatus.InReview)]     // فتح كتاب مغلق
    [InlineData(IncomingStatus.New, IncomingStatus.Archived)]        // أرشفة تتخطى الإغلاق
    [InlineData(IncomingStatus.New, IncomingStatus.Replied)]         // رد بلا مراجعة
    [InlineData(IncomingStatus.Replied, IncomingStatus.InReview)]
    [InlineData(IncomingStatus.InReview, IncomingStatus.New)]
    public void RejectsUnplannedTransitions(IncomingStatus from, IncomingStatus to)
    {
        Assert.False(IncomingWorkflow.CanTransition(from, to));
        Assert.Throws<ValidationException>(() => IncomingWorkflow.EnsureTransitionAllowed(from, to));
    }

    [Theory]
    [InlineData(IncomingStatus.New)]
    [InlineData(IncomingStatus.InReview)]
    [InlineData(IncomingStatus.Replied)]
    [InlineData(IncomingStatus.Closed)]
    [InlineData(IncomingStatus.Archived)]
    public void RejectsSameStatus(IncomingStatus status)
    {
        Assert.False(IncomingWorkflow.CanTransition(status, status));
        Assert.Throws<ValidationException>(() => IncomingWorkflow.EnsureTransitionAllowed(status, status));
    }

    /// <summary>
    /// فكّ الأرشفة يعيد الكتاب إلى «مغلق» **وحدها** — لا إلى أي حالة أخرى.
    /// </summary>
    /// <remarks>
    /// ⚠️ كان هذا الاختبار اسمه `ArchivedIsTerminal` ويفرض أن الأرشفة نهائية بلا رجعة.
    /// عُدّلت القاعدة بقرار المالك (2026-07-28) فصار الفكّ متاحاً للمدير فأعلى بسبب إلزامي.
    /// **لم يُحذف الاختبار بل عُكس**: الحدّ الحقيقي أن الفكّ يعود إلى الحالة السابقة للأرشفة
    /// (مغلق) ولا يفتح مساراً جديداً — فكتابٌ مؤرشف لا يعود «جديداً» ولا «قيد المراجعة».
    /// </remarks>
    [Fact]
    public void ArchivedReturnsToClosedOnly()
    {
        var next = IncomingWorkflow.NextStatuses(IncomingStatus.Archived);
        Assert.Equal([IncomingStatus.Closed], next);

        Assert.True(IncomingWorkflow.CanTransition(IncomingStatus.Archived, IncomingStatus.Closed));
        Assert.False(IncomingWorkflow.CanTransition(IncomingStatus.Archived, IncomingStatus.New));
        Assert.False(IncomingWorkflow.CanTransition(IncomingStatus.Archived, IncomingStatus.InReview));
        Assert.False(IncomingWorkflow.CanTransition(IncomingStatus.Archived, IncomingStatus.Replied));
    }

    [Theory]
    [InlineData(IncomingStatus.New, true)]
    [InlineData(IncomingStatus.InReview, true)]
    [InlineData(IncomingStatus.Replied, false)]
    [InlineData(IncomingStatus.Closed, false)]
    [InlineData(IncomingStatus.Archived, false)]
    public void OperableOnlyWhileInProcess(IncomingStatus status, bool expected)
        => Assert.Equal(expected, IncomingWorkflow.IsOperable(status));

    [Fact]
    public void EveryStatusHasArabicName()
    {
        foreach (var status in Enum.GetValues<IncomingStatus>())
        {
            var name = IncomingWorkflow.ArabicName(status);
            Assert.False(string.IsNullOrWhiteSpace(name));
            Assert.NotEqual(status.ToString(), name);   // مترجَم فعلاً لا مجرد اسم الـ enum
        }
    }

    [Fact]
    public void EveryStatusIsCoveredByTheMatrix()
    {
        // Hint: يضمن أن أي حالة جديدة تُضاف لاحقاً لن تُنسى بلا انتقالات معرّفة.
        foreach (var status in Enum.GetValues<IncomingStatus>())
            Assert.NotNull(IncomingWorkflow.NextStatuses(status));
    }
}
