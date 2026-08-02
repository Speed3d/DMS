using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Dms.Api.Auth;

/// <summary>
/// حارس وحدة الموظفين والرواتب — **فحصٌ مزدوج**: قسم <see cref="AppModule.HR"/> **و**
/// دورٌ مديرٌ فأعلى (ADR-023).
/// </summary>
/// <remarks>
/// لماذا لا تكفي <c>[RequireModule(AppModule.HR)]</c> وحدها؟ لأن القسم علَمٌ يُمنح، ودورٌ
/// أدنى قد يُمنَحه سهواً — فيصير كل موظف قارئاً لرواتب زملائه. قرار المالك (2026-08-03) أن
/// الوحدة **للمدير فأعلى** بلا استثناء، والحدّ الثاني هنا يجعل ذلك قاعدةً في الكود لا عُرفاً
/// في شاشة المستخدمين. و<c>UserService.ResolveModules</c> يجرّد HR ممّن دون المدير أصلاً،
/// فهذا حزامٌ ثانٍ على من مُنحها قبل القاعدة أو بطلب HTTP مباشر.
/// </remarks>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class RequireHrModuleAttribute : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var current = context.HttpContext.RequestServices.GetRequiredService<ICurrentUser>();

        if (current.Role is not { } role || !RoleHierarchy.IsManagerOrAbove(role))
            throw new ForbiddenException("قسم الموظفين والرواتب متاح للمدير فأعلى فقط.");

        if (!current.HasModule(AppModule.HR))
            throw new ForbiddenException("لا تملك صلاحية الوصول لقسم الموظفين والرواتب.");
    }
}
