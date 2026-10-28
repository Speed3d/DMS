using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// اختبارات قواعد الترقيم الرسمي للصادر، ملء الفجوات، والترقيم اليدوي (ADR-064).
/// </summary>
/// <remarks>
/// ⚠️ **تنادي القاعدة الحقيقية في <c>Dms.Domain</c>** — كانت النسخة الأولى تعيد كتابة المنطق داخل الاختبار
/// فتمرّ مهما تغيّر الكود. والمسار مع القاعدة (القفل · الفهرس · الحذف) يحرسه <c>e2e/numbering-e2e.ps1</c>.
/// </remarks>
public class OutgoingNumberingTests
{
    [Fact]
    public void AuditLabels_TranslatesCounterRollback_And_Counter()
    {
        Assert.Equal("تراجع عداد الترقيم", AuditLabels.Action("CounterRollback"));
        Assert.Equal("عداد الترقيم", AuditLabels.Entity("Counter"));
    }

    [Theory]
    [InlineData(1, 10, OutgoingSerialRules.AvailableGap)]
    [InlineData(10, 10, OutgoingSerialRules.AvailableGap)]
    [InlineData(11, 10, OutgoingSerialRules.AvailableNext)]
    [InlineData(12, 10, OutgoingSerialRules.AvailableAboveCounter)]
    [InlineData(1, 0, OutgoingSerialRules.AvailableNext)]
    [InlineData(25, 0, OutgoingSerialRules.AvailableAboveCounter)]
    public void ClassifyFree_SortsGapNextAndJump(int serial, int counter, string expected) =>
        Assert.Equal(expected, OutgoingSerialRules.ClassifyFree(serial, counter));

    [Fact]
    public void CounterAfterDelete_LastBook_FallsToHighestRemaining()
    {
        Assert.Equal(11, OutgoingSerialRules.CounterAfterDelete(12, 12, 11));
        // 🔴 فجوةٌ تحت المحذوف (حُذف 11 قبله): لا يُعطى 11 ثم يصطدم بلا شيء — يقف عند أعلى حيّ
        Assert.Equal(10, OutgoingSerialRules.CounterAfterDelete(12, 12, 10));
    }

    [Fact]
    public void CounterAfterDelete_OnlyBook_ReturnsZero() =>
        Assert.Equal(0, OutgoingSerialRules.CounterAfterDelete(1, 1, null));

    [Fact]
    public void CounterAfterDelete_NotLast_LeavesCounter() =>
        Assert.Null(OutgoingSerialRules.CounterAfterDelete(12, 5, 12));

    // ── حكم الختم الخامّ بعد إعادة استعمال الرقم ──

    private static LegacyQrVerdict.Candidate C(string content, string date = "2026-10-20", string entity = "وزارة النفط") =>
        new(content, date, entity);

    [Fact]
    public void LegacyQr_ExactLiveContent_IsGenuine() =>
        Assert.True(LegacyQrVerdict.IsGenuine("NEW", "2026-10-20", "وزارة النفط", C("NEW"), []));

    [Fact]
    public void LegacyQr_NoLiveBook_IsWithdrawn() =>
        Assert.False(LegacyQrVerdict.IsGenuine("OLD", "2026-10-20", "وزارة النفط", null, [C("OLD")]));

    [Fact]
    public void LegacyQr_DeletedBookContent_IsWithdrawn_EvenWhenNumberReused() =>
        // 🔴 الثغرة نفسها: رقمٌ واحد لكتابين — الختم للمحذوف
        Assert.False(LegacyQrVerdict.IsGenuine("OLD", "2026-10-20", "وزارة النفط", C("NEW"), [C("OLD")]));

    [Fact]
    public void LegacyQr_SameDaySameEntityReissue_IsWithdrawn() =>
        // محتوى لا يطابق أحداً حرفياً، والتاريخ والجهة لا يفرّقان بين الحيّ والمحذوف ⟵ الحذر
        Assert.False(LegacyQrVerdict.IsGenuine("UNKNOWN", "2026-10-20", "وزارة النفط", C("NEW"), [C("OLD2")]));

    [Fact]
    public void LegacyQr_OlderVersionOfLiveBook_MatchingDateAndEntity_IsGenuine() =>
        // نسخةٌ قبل «التعديل بعد الاعتماد» ولا محذوفَ بالرقم: السلوك السابق كما هو
        Assert.True(LegacyQrVerdict.IsGenuine("V1", "2026-10-20", "وزارة النفط", C("V2"), []));

    [Fact]
    public void LegacyQr_DifferentDate_IsWithdrawn() =>
        Assert.False(LegacyQrVerdict.IsGenuine("X", "2026-10-01", "وزارة النفط", C("NEW", "2026-10-20"), [C("OLD", "2026-10-01", "جهة أخرى")]));
}
