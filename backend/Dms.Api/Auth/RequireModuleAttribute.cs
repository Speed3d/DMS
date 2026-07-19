using Dms.Domain;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Dms.Api.Auth;

/// <summary>
/// يتطلّب أن يملك المستخدم الحالي صلاحية الوصول للقسم المحدّد (طبقة تقييد فوق [Authorize]).
/// السوبر أدمن ورئيس الشركة معفيان (AllowedModules = All). يرمي 403 عربية عند الحجب.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class RequireModuleAttribute(AppModule module) : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var current = context.HttpContext.RequestServices.GetRequiredService<ICurrentUser>();
        if (!current.HasModule(module))
            throw new ForbiddenException("لا تملك صلاحية الوصول لهذا القسم.");
    }
}
