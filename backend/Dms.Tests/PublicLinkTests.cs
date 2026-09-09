using Dms.Documents.Security;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس رمز الرابط العامّ (ADR-043) — الرمز المطبوع في الـQR على كل كتابٍ معتمد.
/// </summary>
/// <remarks>
/// 🔴 **ما يحرسه هذا الملف هو الفرق بين ورقةٍ تُثبت صحّتها وورقةٍ يُزوَّر رمزُها.**
/// </remarks>
public class PublicLinkTests
{
    private static string Key() => QrSigner.GenerateKeyPair().PrivateKeyBase64;

    [Fact]
    public void Token_IsStable_ForSameBook()
    {
        // 🔴 **الثبات شرطُ صحّة الورق المطبوع**: الرمز يُخبَز في الـPDF لحظة الاعتماد،
        //    فلو تغيّر لاحقاً لَبطُلت كلُّ ورقةٍ خرجت من المطبعة.
        var key = Key();
        Assert.Equal(PublicLink.CreateToken(42, key), PublicLink.CreateToken(42, key));
    }

    [Fact]
    public void Token_IsShortEnough_ToScanFromPaper()
    {
        // ⚠️ **الطول ليس تفصيلاً تجميلياً**: الرمز يُطبع بعرض 70 وحدة، وكلُّ حرفٍ زائد
        //    يزيد كثافة الـQR فيتعثّر مسحُه من ورقة. 22 حرفاً ⇒ رابطٌ ~52 حرفاً.
        Assert.Equal(22, PublicLink.CreateToken(1, Key()).Length);
        Assert.Equal(22, PublicLink.CreateToken(int.MaxValue, Key()).Length);
    }

    [Fact]
    public void Token_RoundTrips_ToTheSameBookId()
    {
        var key = Key();
        foreach (var id in new[] { 1, 2, 999, 123456, int.MaxValue })
        {
            Assert.True(PublicLink.TryParse(PublicLink.CreateToken(id, key), key, out var parsed));
            Assert.Equal(id, parsed);
        }
    }

    [Fact]
    public void DifferentBooks_GetDifferentTokens()
    {
        var key = Key();
        var tokens = new[] { 1, 2, 3, 4, 5 }.Select(id => PublicLink.CreateToken(id, key)).ToList();
        Assert.Equal(tokens.Count, tokens.Distinct().Count());
    }

    [Fact]
    public void TamperedToken_IsRejected()
    {
        // 🔴 **بصمةٌ لا تُخمَّن**: لو قُبل رمزٌ مبدَّل لأمكن التنقّل بين الكتب بالتجربة.
        //
        // ⚠️ **ويُبدَّل بايتٌ لا حرف** — وهذا درسٌ من تذبذبٍ وقع فعلاً: 16 بايتاً تُرمَّز في
        //    22 حرفاً، أي **132 بتاً لـ128 بتاً من المعنى**؛ فالحرف الأخير يحمل بتَّين
        //    معنويَّين وأربعةَ حشوٍ، **وتبديلُه قد لا يغيّر البايتات إطلاقاً** فيُقبل الرمز
        //    بحقّ ويُخفق الحارس بلا عيبٍ في الكود. **الحارس الذي يعتمد على الترميز يكذب
        //    أحياناً — والبايتات لا تكذب.**
        var key = Key();
        var token = PublicLink.CreateToken(7, key);
        var raw = Decode(token);

        for (var i = 0; i < raw.Length; i++)
        {
            var copy = (byte[])raw.Clone();
            copy[i] ^= 0x01;

            Assert.False(PublicLink.TryParse(Encode(copy), key, out _),
                $"رمزٌ مبدَّلٌ في البايت {i} قُبِل — والبصمة لا تحرس");
        }
    }

    private static byte[] Decode(string s)
    {
        var b64 = s.Replace('-', '+').Replace('_', '/');
        b64 += (b64.Length % 4) switch { 2 => "==", 3 => "=", _ => "" };
        return Convert.FromBase64String(b64);
    }

    private static string Encode(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    [Fact]
    public void TokenFromAnotherKey_IsRejected()
    {
        // مفتاحٌ آخر = شركةٌ أخرى أو سيرفرٌ آخر — ولا يُقبل رمزُه هنا.
        var token = PublicLink.CreateToken(7, Key());
        Assert.False(PublicLink.TryParse(token, Key(), out _));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not-a-token")]
    [InlineData("!!!غير-صالح!!!")]
    [InlineData("QUJD")]                       // قصيرٌ جداً
    [InlineData("QUJDREVGR0hJSktMTU5PUFFSUw")] // طولٌ صحيح وبصمةٌ خاطئة
    public void GarbageToken_FailsGracefully(string? token)
    {
        // ⚠️ **لا يرمي إطلاقاً** — النقطة عامّة، واستثناءٌ غير ملتقَط فيها صفحةُ خطأ للعالم.
        Assert.False(PublicLink.TryParse(token, Key(), out var id));
        Assert.Equal(0, id);
    }

    [Fact]
    public void ZeroOrNegativeId_IsRefused()
    {
        var key = Key();
        Assert.Throws<ArgumentOutOfRangeException>(() => PublicLink.CreateToken(0, key));
        Assert.Throws<ArgumentOutOfRangeException>(() => PublicLink.CreateToken(-1, key));
    }
}
