using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس bitmask الأقسام. مكتوبة لأن قسمَي الموظفين والرواتب انضمّا إلى منظومةٍ فيها
/// **ثلاثة مواضع صامتة** تفترض «كل الأقسام»، ولأن نسيان قسمٍ في مصفوفة <c>Individual</c>
/// يُسقطه بلا أي خطأ — فلا يُحفظ ولا يظهر مربّعه أبداً.
/// </summary>
public class AppModuleTests
{
    [Fact]
    public void All_ExcludesBothHrModules_SoNoNewAssignmentGetsThemSilently()
    {
        // 🔐 **الحارس الأهمّ، وأهميته ازدادت بـADR-025 لا العكس:** `All` هي الافتراض في
        //    `UserCompany.Modules` وفي مسار التوافق الخلفي بـ`UserService.ResolveModules`.
        //    وبعد فتح الوحدة لدور «موظف» لم يعد حدُّ الدور يحمي، فالحارس الباقي هو أن
        //    القسمين **لا يُمنحان تلقائياً**.
        Assert.False(AppModule.All.HasFlag(AppModule.Employees));
        Assert.False(AppModule.All.HasFlag(AppModule.Payroll));
        Assert.Equal(127, (int)AppModule.All);
    }

    [Fact]
    public void AllWithHr_IncludesEverything_ForExemptRoles()
    {
        Assert.True(AppModule.AllWithHr.HasFlag(AppModule.Employees));
        Assert.True(AppModule.AllWithHr.HasFlag(AppModule.Payroll));
        Assert.Equal(511, (int)AppModule.AllWithHr);
    }

    [Fact]
    public void EmployeesKeepsBit128_SoOldGrantsSurviveTheSplit()
    {
        // 🔴 القيمة محفوظة عمداً: كل من مُنح `HR = 128` قبل ADR-025 يبقى مالكاً لقسم
        //    الموظفين بلا تعديل بيانات. والرواتب بتٌّ **جديد** تمنحه المهاجرة صراحةً.
        Assert.Equal(128, (int)AppModule.Employees);
        Assert.Equal(256, (int)AppModule.Payroll);
    }

    [Fact]
    public void BothModules_AreRegisteredInIndividual_SoTheySurviveTheApiRoundTrip()
    {
        var names = AppModule.AllWithHr.ToNames();
        Assert.Contains("Employees", names);
        Assert.Contains("Payroll", names);
        Assert.Equal(AppModule.Employees, AppModuleExtensions.FromNames(new[] { "Employees" }));
        Assert.Equal(AppModule.Payroll, AppModuleExtensions.FromNames(new[] { "Payroll" }));
    }

    [Fact]
    public void AllNineModules_RoundTripThroughNames()
    {
        var names = AppModule.AllWithHr.ToNames();
        Assert.Equal(9, names.Count);
        Assert.Equal(AppModule.AllWithHr, AppModuleExtensions.FromNames(names));
    }

    [Fact]
    public void UnknownNames_AreIgnored_NotThrown()
    {
        Assert.Equal(AppModule.Outgoing, AppModuleExtensions.FromNames(new[] { "Outgoing", "HR", "" }));
    }

    [Fact]
    public void StrippingBothHrModules_LeavesOtherModulesIntact()
    {
        // ما يفعله `ResolveModules` للقارئ.
        var stripped = AppModule.AllWithHr & ~(AppModule.Employees | AppModule.Payroll);
        Assert.Equal(AppModule.All, stripped);
        Assert.True(stripped.HasFlag(AppModule.Incoming));
    }

    [Fact]
    public void OneModule_DoesNotImplyTheOther()
    {
        // 🔐 جوهر الفصل: مَن يملك الموظفين لا يملك الرواتب، والعكس.
        Assert.False(AppModule.Employees.HasFlag(AppModule.Payroll));
        Assert.False(AppModule.Payroll.HasFlag(AppModule.Employees));

        var employeesOnly = AppModule.Outgoing | AppModule.Employees;
        Assert.True(employeesOnly.HasFlag(AppModule.Employees));
        Assert.False(employeesOnly.HasFlag(AppModule.Payroll));
    }

    [Theory]
    [InlineData(UserRole.SuperAdmin, true)]
    [InlineData(UserRole.President, true)]
    [InlineData(UserRole.Manager, true)]
    [InlineData(UserRole.Employee, true)]   // 🔄 كان false قبل ADR-025
    [InlineData(UserRole.Reader, false)]
    public void HrModules_AreOpenToEveryRoleAboveReader(UserRole role, bool allowed)
    {
        // القاعدة التي تفرضها [RequireHrModule] — قرار المالك 2026-08-05 ناسخاً ADR-023.
        // محاسبٌ أو كاتب شؤون موظفين بدور «موظف» يحتاج الوحدة يومياً، وحصرُها في المدير
        // كان يدفع إلى منح الدور الأعلى للالتفاف — وهو أوسع أثراً من فتح القسم.
        Assert.Equal(allowed, RoleHierarchy.IsEmployeeOrAbove(role));
    }

    [Fact]
    public void ReaderStaysBlocked_EvenThoughTheModuleOpenedUp()
    {
        // 🔐 القارئ دورُه اطّلاعٌ لا معالجة، والرواتب أحسّ بيانات في النظام.
        Assert.False(RoleHierarchy.IsEmployeeOrAbove(UserRole.Reader));
    }
}
