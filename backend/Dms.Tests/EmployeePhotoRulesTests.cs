using Dms.Domain;
using Xunit;

/// <summary>
/// حرّاس قاعدة صورة الموظف (ADR-035).
///
/// ⚠️ **سبب وجودها:** للصورة **مساران** منذ فتح الرفع لصاحبها — شؤون الموظفين من
/// البطاقة، والموظف من بروفايله. وحدُّ الحجم والصيغ لو نُسخ في الموضعين لافترقا بأول
/// تعديل، فيُقبل في أحدهما ما يُرفض في الآخر **والصورة واحدة**.
/// </summary>
public class EmployeePhotoRulesTests
{
    [Theory]
    [InlineData("photo.jpg", ".jpg")]
    [InlineData("photo.JPG", ".jpg")]
    [InlineData("صورتي.jpeg", ".jpeg")]
    [InlineData("p.PNG", ".png")]
    public void الصيغ_المسموحة_تمرّ_ويُطبَّع_امتدادها(string fileName, string expected)
        => Assert.Equal(expected, EmployeePhotoRules.Validate(fileName, 1024));

    [Theory]
    [InlineData("virus.exe")]
    [InlineData("doc.pdf")]
    [InlineData("anim.gif")]
    [InlineData("bare")]
    public void الصيغ_غير_المسموحة_تُرفض(string fileName)
        => Assert.Throws<ValidationException>(() => EmployeePhotoRules.Validate(fileName, 1024));

    [Fact]
    public void الملف_الفارغ_يُرفض()
        => Assert.Throws<ValidationException>(() => EmployeePhotoRules.Validate("p.png", 0));

    /// <summary>الحدّ **شامل**: خمسة ميغابايت بالضبط تمرّ، وبايتٌ فوقها يُرفض.</summary>
    [Fact]
    public void الحدّ_شاملٌ_لا_حصريّ()
    {
        Assert.Equal(".png", EmployeePhotoRules.Validate("p.png", EmployeePhotoRules.MaxBytes));
        Assert.Throws<ValidationException>(
            () => EmployeePhotoRules.Validate("p.png", EmployeePhotoRules.MaxBytes + 1));
    }

    /// <summary>
    /// 🔴 **مفتاح التخزين ثابتٌ للشخص** — وهو ما يجعل «صورةً واحدة للشخص» صحيحاً فعلاً:
    /// رفعُ الموظف من بروفايله يكتب على المفتاح الذي تقرأ منه بطاقتُه، لا بجانبه.
    /// </summary>
    [Fact]
    public void مفتاح_التخزين_واحدٌ_للبطاقة_مهما_اختلف_الرافع()
    {
        var fromCard = EmployeePhotoRules.BlobKey(7, ".png");
        var fromProfile = EmployeePhotoRules.BlobKey(7, ".png");
        Assert.Equal(fromCard, fromProfile);
        Assert.Equal("emp-7.png", fromCard);
    }

    /// <summary>الرسائل عربيةٌ تُعرض للمستخدم كما هي — لا رموزَ خام.</summary>
    [Fact]
    public void الرسائل_عربيةٌ_مفهومة()
    {
        var big = Assert.Throws<ValidationException>(
            () => EmployeePhotoRules.Validate("p.png", EmployeePhotoRules.MaxBytes + 1));
        Assert.Contains("5 ميغابايت", big.Message);

        var bad = Assert.Throws<ValidationException>(
            () => EmployeePhotoRules.Validate("p.exe", 10));
        Assert.Contains("JPG/PNG", bad.Message);
    }
}
