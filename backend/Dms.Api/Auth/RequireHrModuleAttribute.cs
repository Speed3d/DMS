using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Dms.Api.Auth;

/// <summary>
/// حارس وحدتَي الموظفين والرواتب — **فحصٌ مزدوج**: القسم المطلوب **و** دورٌ فوق «القارئ»
/// (ADR-025).
/// </summary>
/// <remarks>
/// <para>
/// لماذا لا تكفي <c>[RequireModule(...)]</c> وحدها؟ لأن القسم علَمٌ يُمنح، و**القارئ** قد
/// يُمنَحه سهواً — فيصير مَن دوره اطّلاعٌ محضٌ قارئاً لرواتب زملائه. الحدّ الثاني هنا يجعل
/// ذلك قاعدةً في الكود لا عُرفاً في شاشة المستخدمين، و<c>UserService.ResolveModules</c>
/// يجرّد القسمين من القارئ أصلاً — فهذا حزامٌ ثانٍ على من مُنحهما قبل القاعدة أو بطلب
/// HTTP مباشر.
/// </para>
/// <para>
/// 🔄 **كان الحدّ «المدير فأعلى» (ADR-023) فصار «فوق القارئ» (ADR-025)** بقرار المالك
/// 2026-08-05: محاسبٌ أو كاتب شؤون موظفين بدور «موظف» يحتاج الوحدة يومياً، وحصرُها في
/// المدير كان يدفع إلى منح الدور الأعلى للالتفاف — **وهو أسوأ من فتح القسم**، لأن الدور
/// يفتح أشياء أخرى كثيرة معه.
/// </para>
/// <para>
/// ⚠️ **والقسم المطلوب صريحٌ في كل نقطة**: <c>[RequireHrModule(AppModule.Payroll)]</c> على
/// وحدات تحكّم الرواتب و<c>Employees</c> على الموظفين. لولا الوسيط لكان فتحُ أحد القسمين
/// يفتح الآخر — وهو بالضبط ما جاء الفصلُ ليمنعه.
/// </para>
/// <para>
/// ⚠️ **وتمرير قسمين معاً يعني «أيّهما»** لا «كلاهما» — لنقطةٍ تخدم القسمين مثل
/// <c>/hr/summary</c>. **ولا يُستعمل هذا للتوسّع**: النقطة التي تقبل أيّهما يجب أن
/// **تُخفي عن كلٍّ ما لا يخصّه** في جسم الردّ، وإلا صار «أيّهما» باباً خلفياً يُبطل الفصل.
/// </para>
/// </remarks>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class RequireHrModuleAttribute(params AppModule[] modules)
    : Attribute, IAuthorizationFilter
{
    /// <summary>الأقسام المقبولة — **أيٌّ منها يكفي**.</summary>
    public AppModule[] Modules { get; } =
        modules.Length > 0 ? modules : [AppModule.Employees, AppModule.Payroll];

    private static string ArabicName(AppModule m) =>
        m == AppModule.Payroll ? "الرواتب" : "الموظفين";

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
