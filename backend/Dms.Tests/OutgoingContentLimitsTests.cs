using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>حدود حجم محتوى الصادر (الدفعة ١ — 0.11.1): كان المتن بلا سقفٍ إطلاقاً.</summary>
public class OutgoingContentLimitsTests
{
    [Fact]
    public void NormalBook_Passes()
        => Assert.Null(OutgoingContentLimits.Violation("<p>نص</p>", "[{\"insert\":\"نص\\n\"}]", "تصحيح العنوان"));

    [Fact]
    public void NullsPass_BecauseRequiredIsAnotherRule()
        => Assert.Null(OutgoingContentLimits.Violation(null, null, null));

    [Fact]
    public void ExactlyAtTheLimit_Passes()
        => Assert.Null(OutgoingContentLimits.Violation(
            new string('a', OutgoingContentLimits.MaxBodyHtmlChars),
            new string('a', OutgoingContentLimits.MaxBodyJsonChars),
            new string('a', OutgoingContentLimits.MaxChangeNoteChars)));

    [Fact]
    public void OneCharOverHtml_IsRejected()
        => Assert.NotNull(OutgoingContentLimits.Violation(new string('a', OutgoingContentLimits.MaxBodyHtmlChars + 1), null));

    [Fact]
    public void OneCharOverJson_IsRejected()
        => Assert.NotNull(OutgoingContentLimits.Violation("<p>نص</p>", new string('a', OutgoingContentLimits.MaxBodyJsonChars + 1)));

    [Fact]
    public void LongChangeNote_IsRejected_ButSurroundingSpacesDoNotCount()
    {
        Assert.NotNull(OutgoingContentLimits.Violation("<p>x</p>", null, new string('a', OutgoingContentLimits.MaxChangeNoteChars + 1)));
        Assert.Null(OutgoingContentLimits.Violation("<p>x</p>", null, "  " + new string('a', OutgoingContentLimits.MaxChangeNoteChars) + "  "));
    }

    [Fact]
    public void LimitsLeaveRoomForRealInvoices()
    {
        // فاتورة المالك (74 صفّاً) ≈ 30 ألف حرف HTML — والحدّ أكبر منها بأكثر من مئة ضعف.
        Assert.True(OutgoingContentLimits.MaxBodyHtmlChars > 100 * 30_000);
        Assert.True(OutgoingContentLimits.MaxBodyJsonChars >= OutgoingContentLimits.MaxBodyHtmlChars);
    }
}
