using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس bitmask الأقسام. مكتوبة لأن قسم HR انضمّ إلى منظومةٍ فيها **ثلاثة مواضع صامتة**
/// تفترض «كل الأقسام»، ولأن نسيان قسمٍ في مصفوفة <c>Individual</c> يُسقطه بلا أي خطأ.
/// </summary>
public class AppModuleTests
{
    [Fact]
    public void All_ExcludesHr_SoNoNewAssignmentGetsPayrollSilently()
    {
        // 🔐 الحارس الأهم: `All` هي الافتراض في `UserCompany.Modules` وفي مسار التوافق الخلفي
        //    بـ`UserService.ResolveModules`. ضمُّ HR إليها يمنح كل مستخدم جديد رؤيةَ الرواتب.
        Assert.False(AppModule.All.HasFlag(AppModule.HR));
        Assert.Equal(127, (int)AppModule.All);
    }

    [Fact]
    public void AllWithHr_IncludesEverything_ForExemptRoles()
    {
        Assert.True(AppModule.AllWithHr.HasFlag(AppModule.HR));
        Assert.Equal(255, (int)AppModule.AllWithHr);
    }

    [Fact]
    public void Hr_IsRegisteredInIndividual_SoItSurvivesTheApiRoundTrip()
    {
        // قسمٌ غائب عن `Individual` يُسقَط صامتاً هنا — فلا يُحفظ ولا يظهر مربّعه أبداً.
        Assert.Contains("HR", AppModule.AllWithHr.ToNames());
        Assert.Equal(AppModule.HR, AppModuleExtensions.FromNames(new[] { "HR" }));
    }

    [Fact]
    public void AllEightModules_RoundTripThroughNames()
    {
        var names = AppModule.AllWithHr.ToNames();
        Assert.Equal(8, names.Count);
        Assert.Equal(AppModule.AllWithHr, AppModuleExtensions.FromNames(names));
    }

    [Fact]
    public void UnknownNames_AreIgnored_NotThrown()
    {
        Assert.Equal(AppModule.Outgoing, AppModuleExtensions.FromNames(new[] { "Outgoing", "Payroll", "" }));
    }

    [Fact]
    public void StrippingHr_LeavesOtherModulesIntact()
    {
        // ما يفعله `ResolveModules` لمن هو دون المدير.
        var stripped = AppModule.AllWithHr & ~AppModule.HR;
        Assert.Equal(AppModule.All, stripped);
        Assert.True(stripped.HasFlag(AppModule.Incoming));
    }

    [Theory]
    [InlineData(UserRole.SuperAdmin, true)]
    [InlineData(UserRole.President, true)]
    [InlineData(UserRole.Manager, true)]
    [InlineData(UserRole.Employee, false)]
    [InlineData(UserRole.Reader, false)]
    public void HrIsManagerAndAbove_Only(UserRole role, bool allowed)
    {
        // القاعدة التي تفرضها [RequireHrModule] — قرار المالك 2026-08-03.
        Assert.Equal(allowed, RoleHierarchy.IsManagerOrAbove(role));
    }
}
