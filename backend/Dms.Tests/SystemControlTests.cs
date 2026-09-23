using Dms.Domain;
using Dms.Infrastructure.Services;

namespace Dms.Tests;

/// <summary>
/// حرّاس حالة إيقاف النظام في الملفّ (ADR-050). أهمُّها أن **الإيقاف يبقى بعد إعادة التشغيل**
/// — فالتحديث نفسه إعادةُ تشغيل، ولو ضاعت الحالة لعاد النظام مفتوحاً قبل أن يفحصه المالك.
/// </summary>
public sealed class SystemControlTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "dms-sysctl-" + Guid.NewGuid().ToString("N"));
    private string FilePath => Path.Combine(_dir, "system-control.json");

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { /* ملفّات مؤقتة */ }
    }

    [Fact]
    public void NoFile_MeansOpen()
    {
        var s = new SystemControl(FilePath);
        Assert.False(s.Lockdown.Active);
        Assert.False(s.Announcement.Visible);
    }

    [Fact]
    public void Lockdown_SurvivesRestart()
    {
        new SystemControl(FilePath).SetLockdown(true, "تحديث", 1, "المالك");

        var reborn = new SystemControl(FilePath); // «إعادة تشغيل الخدمة»
        Assert.True(reborn.Lockdown.Active);
        Assert.Equal("تحديث", reborn.Lockdown.Message);
        Assert.Equal("المالك", reborn.Lockdown.ByName);
        Assert.NotNull(reborn.Lockdown.SinceUtc);
    }

    [Fact]
    public void Lockdown_RequiresMessage_ButUnlockDoesNot()
    {
        var s = new SystemControl(FilePath);
        Assert.Throws<ValidationException>(() => s.SetLockdown(true, "  ", 1, null));
        Assert.False(s.Lockdown.Active);
        s.SetLockdown(false, null, 1, null); // لا يرمي
    }

    [Fact]
    public void EditingMessage_WhileLocked_KeepsSince()
    {
        var s = new SystemControl(FilePath);
        var first = s.SetLockdown(true, "أ", 1, null);
        var second = s.SetLockdown(true, "ب", 1, null);
        Assert.Equal(first.SinceUtc, second.SinceUtc);
        Assert.Equal("ب", second.Message);
    }

    // 🔴 يفشل مغلقاً: لا نعرف أكان موقوفاً، فنفترض أنه كذلك. والسوبر أدمن يدخل دائماً فيُصلحه.
    [Fact]
    public void CorruptFile_FailsClosed()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(FilePath, "{ هذا ليس JSON");
        var s = new SystemControl(FilePath);
        Assert.True(s.Lockdown.Active);
        Assert.Equal(SystemAccess.DefaultLockdownMessage, s.Lockdown.Message);

        // وحفظٌ من الإعدادات يُصلحه.
        s.SetLockdown(false, null, 1, null);
        Assert.False(new SystemControl(FilePath).Lockdown.Active);
    }

    [Fact]
    public void HidingAnnouncement_KeepsText()
    {
        var s = new SystemControl(FilePath);
        s.SetAnnouncement(true, "سيتوقّف النظام بعد 10 دقائق", AnnouncementKind.Warning);
        var hidden = s.SetAnnouncement(false, null, AnnouncementKind.Warning);
        Assert.False(hidden.Visible);
        Assert.Equal("سيتوقّف النظام بعد 10 دقائق", hidden.Text);
        Assert.Throws<ValidationException>(() => s.SetAnnouncement(true, "", AnnouncementKind.Info));
    }

    [Fact]
    public void SavedTexts_SeparateLists_NoDuplicates_Removable()
    {
        var s = new SystemControl(FilePath);
        s.AddSavedText(SavedTextKind.Lockdown, "تحديث");
        s.AddSavedText(SavedTextKind.Lockdown, "تحديث");
        s.AddSavedText(SavedTextKind.Announcement, "اجتماع");

        var reborn = new SystemControl(FilePath);
        Assert.Equal(["تحديث"], reborn.SavedTexts(SavedTextKind.Lockdown));
        Assert.Equal(["اجتماع"], reborn.SavedTexts(SavedTextKind.Announcement));

        Assert.True(reborn.RemoveSavedText(SavedTextKind.Lockdown, "تحديث"));
        Assert.False(reborn.RemoveSavedText(SavedTextKind.Lockdown, "تحديث"));
        Assert.Empty(reborn.SavedTexts(SavedTextKind.Lockdown));
    }

    [Fact]
    public void SavedTexts_HaveACap()
    {
        var s = new SystemControl(FilePath);
        for (var i = 0; i < SystemAccess.MaxSavedTexts; i++) s.AddSavedText(SavedTextKind.Announcement, $"نص {i}");
        Assert.Throws<ValidationException>(() => s.AddSavedText(SavedTextKind.Announcement, "زائد"));
    }

    // أمر الطوارئ على السيرفر يكتب الملفّ من عمليةٍ أخرى — والخدمة العاملة تلتقطه.
    [Fact]
    public void ExternalWrite_IsPickedUp_AndReportedOnce()
    {
        var service = new SystemControl(FilePath);
        Assert.Null(service.ReloadIfChangedExternally());

        new SystemControl(FilePath).SetLockdown(true, "طوارئ", null, "وحدة تحكّم السيرفر");
        var change = service.ReloadIfChangedExternally();

        Assert.NotNull(change);
        Assert.False(change!.Before.Active);
        Assert.True(change.After.Active);
        Assert.True(service.Lockdown.Active);
        Assert.Null(service.ReloadIfChangedExternally());
    }

    // ما تكتبه الخدمة نفسها ليس «تغيّراً خارجياً» — وإلا دُوِّن في التدقيق مرّتين.
    [Fact]
    public void OwnWrite_IsNotReportedAsExternal()
    {
        var s = new SystemControl(FilePath);
        s.SetLockdown(true, "تحديث", 1, null);
        Assert.Null(s.ReloadIfChangedExternally());
    }

    [Fact]
    public void Path_ConfiguredWins_ElseBesideStorage()
    {
        var storage = Path.Combine(_dir, "data", "storage");
        Assert.Equal(Path.Combine(_dir, "data", "system-control.json"), SystemControlPath.Resolve(null, storage));
        Assert.Equal(Path.Combine(_dir, "data", "system-control.json"), SystemControlPath.Resolve("  ", storage + Path.DirectorySeparatorChar));

        var custom = Path.Combine(_dir, "x.json");
        Assert.Equal(custom, SystemControlPath.Resolve(custom, storage));
    }
}
