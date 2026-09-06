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

        // ⚠️ **1023 لا 511 منذ ADR-037**: ضُمّ `Tasks = 512`. والاسم لم يعد دقيقاً ولم يُغيَّر
        //    عمداً — معناه «كلُّ قسمٍ يُمنح صراحةً»، مجموعاً للأدوار المعفاة.
        Assert.True(AppModule.AllWithHr.HasFlag(AppModule.Tasks));
        Assert.Equal(1023, (int)AppModule.AllWithHr);
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
    public void AllTenModules_RoundTripThroughNames()
    {
        // 🔴 **العدد مقصودٌ لا تجميليّ**: قسمٌ غائب عن `AppModuleExtensions.Individual` يُسقَط
        //    **صامتاً** ذهاباً وإياباً، فلا يظهر مربّعه في شاشة المستخدمين ولا تُحفظ صلاحيته
        //    أبداً — وهو نمط «ميزة بلا مدخل» الذي كلّف المشروع ثلاث فجوات.
        var names = AppModule.AllWithHr.ToNames();
        Assert.Equal(10, names.Count);
        Assert.Contains("Tasks", names);
        Assert.Equal(AppModule.AllWithHr, AppModuleExtensions.FromNames(names));
    }

    [Fact]
    public void UnknownNames_AreIgnored_NotThrown()
    {
        Assert.Equal(AppModule.Outgoing, AppModuleExtensions.FromNames(new[] { "Outgoing", "HR", "" }));
    }

    [Fact]
    public void StrippingSensitiveModules_LeavesOtherModulesIntact()
    {
        // ما يفعله `ResolveModules` للقارئ — و**الأقسام الحسّاسة صارت ثلاثة** بعد ADR-037:
        // المهام محجوبةٌ عن القارئ بقرار المالك كالموظفين والرواتب.
        var sensitive = AppModule.Employees | AppModule.Payroll | AppModule.Tasks;
        var stripped = AppModule.AllWithHr & ~sensitive;

        Assert.Equal(AppModule.All, stripped);
        Assert.True(stripped.HasFlag(AppModule.Incoming));
    }

    [Fact]
    public void Tasks_StaysOutOfAll_SoItIsNeverGrantedSilently()
    {
        // 🔴 **الحارس الوحيد الباقي بعد سقوط حدّ الدور**: `All` هي الافتراض في ثلاثة مواضع
        //    صامتة (تهيئة `UserCompany.Modules` · `ResolveModules` بلا تحديد · المهاجرة على
        //    الصفوف القائمة). قسمٌ داخلها = قسمٌ يناله كلُّ مستخدمٍ جديد بلا أن يمنحه أحد.
        Assert.False(AppModule.All.HasFlag(AppModule.Tasks));
        Assert.Equal(512, (int)AppModule.Tasks);

        // ولا يُشتقّ أحدهما من الآخر — نظير الفصل بين الموظفين والرواتب.
        Assert.False(AppModule.Tasks.HasFlag(AppModule.Payroll));
        Assert.False(AppModule.Payroll.HasFlag(AppModule.Tasks));
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
