using System.Text.Json;
using Dms.Domain;
using Dms.Infrastructure.Services;

namespace Dms.Api.Middleware;

/// <summary>
/// يحجب النظام عن كل المستخدمين **عدا السوبر أدمن** حين يُوقفه المالك للصيانة أو التحديث (ADR-050).
/// </summary>
/// <remarks>
/// ⚠️ **بعد المصادقة لا قبلها** — يحتاج أن يعرف مَن الطالب. والتحقّق من الـJWT لا يلمس القاعدة.
/// ⚠️ **ومنفصلٌ عن <see cref="MaintenanceMiddleware"/>** الذي يسبق المصادقة ويحجب **الجميع**
/// أثناء الاستعادة: هناك القاعدة نفسها غير متاحة، وهنا النظام سليمٌ والمالك يفحصه.
/// والقاعدة كلُّها في <see cref="SystemAccess.ShouldBlock"/>.
/// </remarks>
public sealed class LockdownMiddleware(RequestDelegate next, ISystemControl system)
{
    public async Task Invoke(HttpContext ctx)
    {
        var lockdown = system.Lockdown;
        if (lockdown.Active)
        {
            var user = ctx.User;
            var authenticated = user.Identity?.IsAuthenticated == true;
            var hasBearer = ctx.Request.Headers.Authorization.ToString()
                .StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase);

            if (SystemAccess.ShouldBlock(true, ctx.Request.Path.Value, authenticated,
                    authenticated && user.IsInRole(nameof(UserRole.SuperAdmin)), hasBearer))
            {
                ctx.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                ctx.Response.ContentType = "application/json; charset=utf-8";
                ctx.Response.Headers.RetryAfter = "30";
                await ctx.Response.WriteAsync(JsonSerializer.Serialize(
                    Body(lockdown.Message ?? SystemAccess.DefaultLockdownMessage)));
                return;
            }
        }

        await next(ctx);
    }

    /// <summary>
    /// جسم ردّ الإيقاف — <c>maintenance</c> ليعامله العميل انتظاراً كالاستعادة،
    /// و<c>lockdown</c> ليميّز أنه إيقافٌ يدويّ.
    /// </summary>
    public static object Body(string message) => new { error = message, maintenance = true, lockdown = true };
}
