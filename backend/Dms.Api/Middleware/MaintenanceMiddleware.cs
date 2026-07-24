using System.Text.Json;
using Dms.Infrastructure.Services;

namespace Dms.Api.Middleware;

/// <summary>
/// يرفض الطلبات الجديدة بـ 503 أثناء وضع الصيانة (مثل استعادة نسخة احتياطية).
/// Hint: الطلب الذي بدأ الاستعادة يكون قد اجتاز هذا الـ middleware قبل تفعيل الوضع، فلا يتأثر.
///       نسمح باستثناء واحد: نقطة حالة الصيانة، ليعرف العميل متى عاد النظام.
/// </summary>
public sealed class MaintenanceMiddleware(RequestDelegate next, IMaintenanceState maintenance)
{
    public async Task Invoke(HttpContext ctx)
    {
        // مسار مسموح دائماً ليستعلم العميل عن حالة الصيانة (بلا مصادقة).
        var path = ctx.Request.Path.Value ?? "";
        var isStatusProbe = path.Equals("/api/system/status", StringComparison.OrdinalIgnoreCase);

        if (maintenance.IsActive && !isStatusProbe)
        {
            ctx.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            ctx.Response.ContentType = "application/json; charset=utf-8";
            ctx.Response.Headers.RetryAfter = "30";
            var body = JsonSerializer.Serialize(new
            {
                error = maintenance.Reason ?? "النظام قيد الصيانة مؤقتاً. أعد المحاولة بعد قليل.",
                maintenance = true,
            });
            await ctx.Response.WriteAsync(body);
            return;
        }

        await next(ctx);
    }
}
