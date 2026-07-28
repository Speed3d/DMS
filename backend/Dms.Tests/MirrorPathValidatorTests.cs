using Dms.Domain;

namespace Dms.Tests;

/// <summary>
/// 🔐 حارس مسار المرآة — المالك يُدخله بنفسه والخادم يكتب فيه بصلاحياته هو،
/// فكل ثغرة هنا تعني كتابة عشوائية على قرص السيرفر.
/// </summary>
public class MirrorPathValidatorTests
{
    private const string Storage = @"D:\DMS\backend\Dms.Api\App_Data\storage";
    private const string Backups = @"D:\DMS\backend\Dms.Api\App_Data\backups";

    private static string Run(string? p) => MirrorPathValidator.Validate(p, Storage, Backups);

    [Theory]
    [InlineData(@"E:\DMS-Backup")]
    [InlineData(@"F:\نسخ\DMS")]
    [InlineData(@"D:\Mirror")]
    public void AcceptsProperAbsolutePaths(string p) => Assert.Equal(Path.GetFullPath(p), Run(p));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void RejectsEmpty(string? p) => Assert.Throws<ValidationException>(() => Run(p));

    [Theory]
    [InlineData(@"backup")]
    [InlineData(@"..\..\backup")]
    [InlineData(@"\backup")]
    public void RejectsRelativePaths(string p)
    {
        // المسار النسبي يُحلّ إلى مجلد عمل الخدمة — موضع لا يقصده أحد.
        Assert.Throws<ValidationException>(() => Run(p));
    }

    [Theory]
    [InlineData(@"C:\Windows\Temp\backup")]
    [InlineData(@"C:\Program Files\DMS")]
    [InlineData(@"C:\ProgramData\backup")]
    public void RejectsSystemFolders(string p)
    {
        // خطأ مطبعي واحد في مجلد نظام قد يُتلف النظام لا النسخة.
        Assert.Throws<ValidationException>(() => Run(p));
    }

    [Fact]
    public void RejectsPathInsideStorage()
    {
        // ⚠️ الأخطر: مرآة داخل مجلد التخزين تنسخ نفسها كل مرة — نموّ لا نهائي يملأ القرص.
        Assert.Throws<ValidationException>(() => Run(Path.Combine(Storage, "mirror")));
        Assert.Throws<ValidationException>(() => Run(Storage));
    }

    [Fact]
    public void RejectsPathContainingStorage()
    {
        // والعكس كذلك: مرآةٌ في مجلدٍ **يحتوي** التخزين تُنتج التكرار نفسه.
        Assert.Throws<ValidationException>(() => Run(@"D:\DMS\backend\Dms.Api\App_Data"));
    }

    [Fact]
    public void RejectsPathInsideManagedBackups()
    {
        // يخلط المرآة بالنسخ المُدارة فتُقلّمها سياسة الاحتفاظ وتحذف نسخة المالك.
        Assert.Throws<ValidationException>(() => Run(Path.Combine(Backups, "mirror")));
    }

    [Fact]
    public void SiblingFolderWithSharedPrefixIsAllowed()
    {
        // `...\storage2` ليس داخل `...\storage` — المقارنة بالفاصل تمنع هذا الخلط.
        var sibling = Storage + "2";
        Assert.Equal(Path.GetFullPath(sibling), Run(sibling));
    }
}
