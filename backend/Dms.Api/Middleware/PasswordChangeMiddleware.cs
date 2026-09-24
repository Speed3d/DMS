using System.Text.Json;
using Dms.Domain;
using Dms.Infrastructure.Auth;

namespace Dms.Api.Middleware;

/// <summary>
/// يحجب كلَّ ما عدا تغييرَ الكلمة عن رمزٍ يحمل «يجب تغيير كلمة المرور المؤقتة» (G19).
/// </summary>
/// <remarks>
/// ⚠️ **بعد المصادقة** ليقرأ العلامة من الرمز — فلا يلمس القاعدة في كل طلب.
/// ⚠️ **403 لا 401**: 401 يجعل العميل يجدّد رمزه في حلقة، والتجديد يعيد العلامة نفسها
/// ما دامت الكلمة لم تُغيَّر. والجسم يحمل <c>mustChangePassword</c> فتعرف الواجهة السبب.
/// والقاعدة كلُّها في <see cref="PasswordChangeGate"/>.
/// </remarks>
public sealed class PasswordChangeMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext ctx)
    {
        if (ctx.User.Identity?.IsAuthenticated == true
            && ctx.User.FindFirst(DmsClaims.MustChangePassword)?.Value == "1"
            && !PasswordChangeGate.IsAllowedBeforeChange(ctx.Request.Path.Value))
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            ctx.Response.ContentType = "application/json; charset=utf-8";
            await ctx.Response.WriteAsync(JsonSerializer.Serialize(new
            {
                error = "يجب تغيير كلمة المرور المؤقتة قبل استعمال النظام.",
                mustChangePassword = true,
            }));
            return;
        }

        await next(ctx);
    }
}
