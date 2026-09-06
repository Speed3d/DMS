using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Dms.Api.Auth;

/// <summary>
/// حارس الأقسام التي **تُمنح صراحةً ولا يبلغها القارئ** — الموظفون · الرواتب · المهام.
/// **فحصٌ مزدوج**: القسم المطلوب **و** دورٌ فوق «القارئ» (ADR-025 · ADR-037).
/// </summary>
/// <remarks>
/// <para>
/// 🔄 **كان اسمه <c>RequireHrModuleAttribute</c> فعُمِّم** (ADR-037، بقرار المالك): القاعدة
/// التي يفرضها ليست «قاعدةَ الموارد البشرية» بل قاعدةَ **كل قسمٍ خارج <see cref="AppModule.All"/>**.
/// ونسخةٌ ثالثة منه لأجل المهام كانت تعني **ثلاثة أماكن تُنسى** عند أول تعديلٍ على القاعدة.
/// </para>
/// <para>
/// لماذا لا تكفي <c>[RequireModule(...)]</c> وحدها؟ لأن القسم علَمٌ يُمنح، و**القارئ** قد
/// يُمنَحه سهواً — فيصير مَن دوره اطّلاعٌ محضٌ قارئاً لرواتب زملائه. الحدّ الثاني هنا يجعل
/// ذلك قاعدةً في الكود لا عُرفاً في شاشة المستخدمين، و<c>UserService.ResolveModules</c>
/// يجرّد الأقسام الثلاثة من القارئ أصلاً — فهذا حزامٌ ثانٍ على من مُنحها قبل القاعدة أو
/// بطلب HTTP مباشر.
/// </para>
/// <para>
/// 🔄 **وكان الحدّ «المدير فأعلى» (ADR-023) فصار «فوق القارئ» (ADR-025)** بقرار المالك
/// 2026-08-05: محاسبٌ أو كاتب شؤون موظفين بدور «موظف» يحتاج الوحدة يومياً، وحصرُها في
/// المدير كان يدفع إلى منح الدور الأعلى للالتفاف — **وهو أسوأ من فتح القسم**، لأن الدور
/// يفتح أشياء أخرى كثيرة معه. **والمهام تتبع القاعدة نفسها**: الموظف يُنشئ مهامّه ويحدّثها.
/// </para>
/// <para>
/// ⚠️ **والقسم المطلوب صريحٌ في كل نقطة**: <c>[RequireGrantedModule(AppModule.Payroll)]</c>
/// على وحدات تحكّم الرواتب و<c>Employees</c> على الموظفين و<c>Tasks</c> على المهام. لولا
/// الوسيط لكان فتحُ أحد الأقسام يفتح البقيّة — وهو بالضبط ما جاء الفصلُ ليمنعه.
/// </para>
/// <para>
/// ⚠️ **وتمرير قسمين معاً يعني «أيّهما»** لا «كلاهما» — لنقطةٍ تخدم القسمين مثل
/// <c>/hr/summary</c>. **ولا يُستعمل هذا للتوسّع**: النقطة التي تقبل أيّهما يجب أن
/// **تُخفي عن كلٍّ ما لا يخصّه** في جسم الردّ، وإلا صار «أيّهما» باباً خلفياً يُبطل الفصل.
/// </para>
/// </remarks>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class RequireGrantedModuleAttribute(params AppModule[] modules)
    : Attribute, IAuthorizationFilter
{
    /// <summary>الأقسام المقبولة — **أيٌّ منها يكفي**.</summary>
    /// <remarks>
    /// ⚠️ **الافتراض يبقى الموظفين والرواتب** ولا تُضمّ إليه المهام: مواضعُ الاستعمال بلا
    /// وسيطٍ كلُّها نقاط HR (مثل <c>/hr/summary</c>)، وضمُّ المهام إليه يجعل مَن يملك المهام
    /// وحدها يمرّ من حارسٍ لم يُقصد له.
    /// </remarks>
    public AppModule[] Modules { get; } =
        modules.Length > 0 ? modules : [AppModule.Employees, AppModule.Payroll];

    private static string ArabicName(AppModule m) => m switch
    {
        AppModule.Payroll => "الرواتب",
        AppModule.Tasks => "المهام",
        _ => "الموظفين",
    };

    private string ArabicNames => string.Join(" أو ", Modules.Select(ArabicName));

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var current = context.HttpContext.RequestServices.GetRequiredService<ICurrentUser>();

        if (current.Role is not { } role || !RoleHierarchy.IsEmployeeOrAbove(role))
            throw new ForbiddenException($"قسم {ArabicNames} غير متاح لدور القارئ.");

        if (!Modules.Any(current.HasModule))
            throw new ForbiddenException($"لا تملك صلاحية الوصول لقسم {ArabicNames}.");
    }
}
