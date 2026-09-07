using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// حرّاس المشاركة في المهام (ADR-037، بقرار المالك 2026-09-06).
/// </summary>
public class TaskParticipationTests
{
    [Fact]
    public void AParticipantIsEitherAUserOrADepartment()
    {
        TaskParticipation.EnsureValid(userId: 5, departmentId: null);   // لا يرمي
        TaskParticipation.EnsureValid(userId: null, departmentId: 3);   // لا يرمي
    }

    [Fact]
    public void NeitherIsRejected_BecauseAnEmptyRowLooksLikeAGrant()
    {
        // 🔴 **صفٌّ بلا الاثنين هو الخطر الحقيقي**: لا يمنح رؤيةً لأحد، لكنه يظهر في
        //    القائمة كمشاركٍ فارغ **فيظنّ المالك أنه أضاف من لم يُضِف** — ويحسب أن فلاناً
        //    يتابع المهمة وهو لا يراها.
        var ex = Assert.Throws<ValidationException>(
            () => TaskParticipation.EnsureValid(null, null));
        Assert.Contains("مستخدماً أو قسماً", ex.Message);
    }

    [Fact]
    public void BothTogetherIsRejected_BecauseItMeansNothing()
    {
        // «سنان بصفته من قسم المالية» ليس معنًى ثالثاً — هو إمّا سنان وإمّا القسم.
        var ex = Assert.Throws<ValidationException>(
            () => TaskParticipation.EnsureValid(5, 3));
        Assert.Contains("لا الاثنان معاً", ex.Message);
    }

    [Fact]
    public void HandoverDescription_SaysWhatHappenedToThePrevious()
    {
        // 🔴 **الفرق يُقرأ في السجلّ لا يُستنتج**: مَن يقرأ «أُسندت من فلان إلى فلان» بعد
        //    شهرٍ لا يعرف أبقي الأولُ يراها أم نُزعت رؤيته — وهو فرقٌ يغيّر مَن كان يستطيع
        //    متابعتها، ويُسأل عنه أحياناً بعد فوات الأوان.
        var kept = TaskParticipation.DescribeHandover("أحمد", "سنان", keptAsParticipant: true);
        var dropped = TaskParticipation.DescribeHandover("أحمد", "سنان", keptAsParticipant: false);

        Assert.NotEqual(kept, dropped);
        Assert.Contains("بقي", kept);
        Assert.Contains("نُزعت", dropped);

        // وكلاهما يذكر الاسمين — فلا يُقرأ السطر بلا طرفيه.
        foreach (var s in new[] { kept, dropped })
        {
            Assert.Contains("أحمد", s);
            Assert.Contains("سنان", s);
        }
    }

    [Fact]
    public void AddedDescription_CarriesTheNoteWhenThereIsOne()
    {
        Assert.Equal("أُضيف إلى المهمة: سنان", TaskParticipation.DescribeAdded("سنان", null));
        Assert.Equal("أُضيف إلى المهمة: سنان", TaskParticipation.DescribeAdded("سنان", "   "));
        Assert.Equal("أُضيف إلى المهمة: سنان — للمتابعة المالية",
            TaskParticipation.DescribeAdded("سنان", "  للمتابعة المالية  "));
    }

    [Fact]
    public void RemovedDescription_IsUnambiguous()
        => Assert.Equal("أُزيل من المهمة: قسم المالية",
            TaskParticipation.DescribeRemoved("قسم المالية"));
}
