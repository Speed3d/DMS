using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>سجلّ حركة الصادر وصورة السوبر أدمن (ADR-056).</summary>
public class OutgoingMovementTests
{
    private static OutgoingFields Base() => new(
        EntityId: 1, TemplateId: 1, Date: new DateTime(2026, 9, 25), HeaderPhrase: "إلى",
        SignatoryName: "المدير", SignatoryTitle: "المدير العام", Subject: "طلب", BodyHtml: "<p>نص</p>",
        Amount: 100m, Currency: Currency.IQD, ExchangeRate: null);

    [Fact]
    public void NothingChanged_IsSaidPlainly()
    {
        var changed = OutgoingChanges.Describe(Base(), Base());
        Assert.Empty(changed);
        Assert.Equal("تعديل المسودّة بلا تغييرٍ في المحتوى", OutgoingChanges.Summary("تعديل المسودّة", changed));
    }

    [Fact]
    public void ChangedFields_AreNamed_InAFixedOrder()
    {
        var after = Base() with { Amount = 250m, Subject = "طلب معدّل", BodyHtml = "<p>نصٌّ آخر</p>" };
        var changed = OutgoingChanges.Describe(Base(), after);
        Assert.Equal(["الموضوع", "المتن", "المبلغ"], changed);
        Assert.Equal("تعديل المسودّة: الموضوع · المتن · المبلغ", OutgoingChanges.Summary("تعديل المسودّة", changed));
    }

    [Fact]
    public void Currency_Or_Rate_Is_AnAmountChange()
    {
        Assert.Equal(["المبلغ"], OutgoingChanges.Describe(Base(), Base() with { Currency = Currency.USD }));
        Assert.Equal(["المبلغ"], OutgoingChanges.Describe(Base(), Base() with { ExchangeRate = 1500m }));
    }

    [Fact]
    public void WhitespaceOnly_IsNotAChange()
    {
        // 🔑 مسافةٌ زائدة ليست تعديلاً يستحقّ سطراً — والخادم يقصّ النصوص أصلاً.
        Assert.Empty(OutgoingChanges.Describe(Base(), Base() with { Subject = " طلب ", HeaderPhrase = "إلى " }));
    }

    [Fact]
    public void Signatory_And_Entity_And_Template_And_Date()
    {
        var after = Base() with { SignatoryTitle = "المعاون", EntityId = 2, TemplateId = 3, Date = new DateTime(2026, 9, 26) };
        Assert.Equal(["الجهة", "التاريخ", "الموقّع", "القالب"], OutgoingChanges.Describe(Base(), after));
    }

    [Fact]
    public void TimeOfDay_IsNotADateChange()
    {
        // التاريخ يومٌ لا لحظة (`LocalClock`) — فالساعة لا تُعدّ تغييراً.
        Assert.Empty(OutgoingChanges.Describe(Base(), Base() with { Date = new DateTime(2026, 9, 25, 13, 0, 0) }));
    }

    [Theory]
    [InlineData(true, false, true)]    // صاحبُ بطاقة — على البطاقة (ADR-035)
    [InlineData(false, true, true)]    // السوبر أدمن بلا بطاقة — على حسابه (ADR-056)
    [InlineData(true, true, true)]     // سوبر أدمن له بطاقة — على البطاقة (صورةٌ واحدة للشخص)
    [InlineData(false, false, false)]  // غيرُهما بلا بطاقة — لا صورة (قرار المالك: للسوبر أدمن وحده)
    public void WhoChangesOwnPhoto(bool hasCard, bool isSuperAdmin, bool expected) =>
        Assert.Equal(expected, EmployeePhotoRules.CanChangeOwn(hasCard, isSuperAdmin));

    [Fact]
    public void UserPhotoKey_NeverCollidesWithEmployeeKey()
    {
        Assert.Equal("user-7.png", EmployeePhotoRules.UserBlobKey(7, ".png"));
        Assert.NotEqual(EmployeePhotoRules.BlobKey(7, ".png"), EmployeePhotoRules.UserBlobKey(7, ".png"));
    }
}
