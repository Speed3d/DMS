using System.Text.Json;
using Dms.Domain;

namespace Dms.Api.Middleware;

/// <summary>يترجم استثناءات المجال إلى استجابات JSON بأكواد HTTP مناسبة.</summary>
public sealed class ExceptionMiddleware(RequestDelegate next, ILogger<ExceptionMiddleware> logger, IHostEnvironment env)
{
    public async Task Invoke(HttpContext ctx)
    {
        try
        {
            await next(ctx);
        }
        catch (Exception ex)
        {
            var status = ex switch
            {
                ValidationException => StatusCodes.Status400BadRequest,
                NotFoundException => StatusCodes.Status404NotFound,
                ForbiddenException => StatusCodes.Status403Forbidden,
                ConflictException => StatusCodes.Status409Conflict,
                ServiceUnavailableException => StatusCodes.Status503ServiceUnavailable,
                _ => StatusCodes.Status500InternalServerError,
            };

            if (status == StatusCodes.Status500InternalServerError)
                logger.LogError(ex, "خطأ غير متوقّع");

            var message = ex is DomainException ? ex.Message : "حدث خطأ غير متوقّع في الخادم.";
            ctx.Response.StatusCode = status;
            ctx.Response.ContentType = "application/json; charset=utf-8";

            object payload = status switch
            {
                StatusCodes.Status500InternalServerError when env.IsDevelopment()
                    => new { error = message, detail = ex.Message, type = ex.GetType().Name, stack = ex.ToString() },
                // ⏸️ الشكل نفسه الذي يردّ به `LockdownMiddleware` — فيعرفه العميل صيانةً لا خطأً (ADR-050).
                StatusCodes.Status503ServiceUnavailable => LockdownMiddleware.Body(message),
                _ => new { error = message },
            };
            if (status == StatusCodes.Status503ServiceUnavailable)
                ctx.Response.Headers.RetryAfter = "30";

            await ctx.Response.WriteAsync(JsonSerializer.Serialize(payload));
        }
    }
}
