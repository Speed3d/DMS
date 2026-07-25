using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// ترميز الصلاحيات «لكل شركة» داخل claim واحد (ADR-017).
/// </summary>
/// <remarks>
/// هذه الطبقة هي ما يفصل شركةً عن أخرى في كل طلب، فخطؤها يعني **تسرّب صلاحية بين الشركات**.
/// لذلك تُختبَر حالات الحدّ صراحةً: الشركة الغائبة، والـclaim الفارغ، والقيمة المشوّهة.
/// </remarks>
public class PerCompanyClaimTests
{
    private static string Sample() =>
        PerCompanyClaim.Encode(new Dictionary<int, int> { [1] = 63, [2] = 127 });

    [Fact]
    public void Encode_ThenRead_ReturnsEachCompanyValue()
    {
        var claim = Sample();
        Assert.Equal(63, PerCompanyClaim.Read(claim, 1));
        Assert.Equal(127, PerCompanyClaim.Read(claim, 2));
    }

    [Fact]
    public void Encode_UsesCompactPairFormat()
        => Assert.Equal("1:63,2:127", Sample());

    // ── فشل مغلق: أي غموض يعني «لا صلاحية»، لا «كل الصلاحيات» ──

    [Fact]
    public void Read_CompanyNotInMap_ReturnsNull()
        => Assert.Null(PerCompanyClaim.Read(Sample(), 99));

    [Fact]
    public void Read_NullCompany_ReturnsNull()
        => Assert.Null(PerCompanyClaim.Read(Sample(), null));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Read_MissingClaim_ReturnsNull(string? claim)
        => Assert.Null(PerCompanyClaim.Read(claim, 1));

    [Theory]
    [InlineData("1")]          // بلا فاصل
    [InlineData(":63")]        // بلا شركة
    [InlineData("abc:63")]     // شركة ليست رقماً
    [InlineData("1:xyz")]      // قيمة ليست رقماً
    public void Read_MalformedEntry_ReturnsNull(string claim)
        => Assert.Null(PerCompanyClaim.Read(claim, 1));

    [Fact]
    public void Read_SkipsMalformedEntryAndFindsValidOne()
        => Assert.Equal(5, PerCompanyClaim.Read("bad,2:5", 2));

    [Fact]
    public void Read_DoesNotMatchCompanyByPrefix()
    {
        // Hint: حارس ضد المطابقة النصّية الساذجة — الشركة 1 يجب ألّا تلتقط قيمة الشركة 12.
        var claim = PerCompanyClaim.Encode(new Dictionary<int, int> { [12] = 99 });
        Assert.Null(PerCompanyClaim.Read(claim, 1));
        Assert.Equal(99, PerCompanyClaim.Read(claim, 12));
    }

    [Fact]
    public void Read_ZeroValue_IsPreservedNotTreatedAsMissing()
    {
        // صلاحية «ممنوعة» (0) تختلف عن «غير مذكورة» (null) — كلتاهما تمنع، لكن الخلط بينهما
        // يُخفي خطأً في الترميز.
        var claim = PerCompanyClaim.Encode(new Dictionary<int, int> { [1] = 0 });
        Assert.Equal(0, PerCompanyClaim.Read(claim, 1));
    }

    [Fact]
    public void Encode_EmptyMap_ProducesEmptyClaim()
        => Assert.Equal("", PerCompanyClaim.Encode(new Dictionary<int, int>()));
}
