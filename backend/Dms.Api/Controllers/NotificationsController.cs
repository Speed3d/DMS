using Dms.Api.Dtos;
using Dms.Infrastructure.Notifications;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Dms.Api.Controllers;

/// <summary>
/// الإشعارات (ADR-038).
/// </summary>
/// <remarks>
/// ⚠️ **بلا <c>[RequireModule]</c> ولا <c>[RequireGrantedModule]</c> — وهذا مقصود:**
/// الإشعارات **عابرةٌ للأقسام**، فقد يصل الموظفَ إشعارٌ عن مهمة وآخرُ عن كتابٍ وارد. واشتراطُ
/// قسمٍ بعينه يعني أن مَن فقد ذلك القسم **يفقد إشعاراته القديمة كلها** — وهي واقعاتٌ وقعت له.
///
/// 🔐 **والحارس الوحيد أن كل نقطةٍ تعمل على <c>RecipientUserId == current.UserId</c>**، ولا
/// تقبل معرّف مستلِمٍ من العميل — نظير حارس البروفايل الشخصي (ADR-033) حرفياً.
/// </remarks>
[ApiController]
[Route("api/notifications")]
[Authorize]
public sealed class NotificationsController(INotificationService notifications) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<NotificationListResponse>> List(
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
        [FromQuery] bool unreadOnly = false, CancellationToken ct = default)
    {
        var size = Math.Clamp(pageSize, 1, 100);
        var (items, total) = await notifications.GetAsync(Math.Max(page, 1), size, unreadOnly, ct);

        return new NotificationListResponse(
            items.Select(n => new NotificationResponse(
                n.NotificationId, n.Title, n.Body, n.Category,
                n.EntityType, n.EntityId, n.Priority,
                n.IsRead, n.ReadAt, n.CreatedAt)).ToList(),
            total, Math.Max(page, 1), size);
    }

    /// <summary>عدد غير المقروء — **شارة الجرس**، وتُستقصى كل دقيقة.</summary>
    [HttpGet("unread-count")]
    public async Task<ActionResult<int>> UnreadCount(CancellationToken ct)
        => await notifications.GetUnreadCountAsync(ct);

    [HttpPost("{id:long}/read")]
    public async Task<IActionResult> MarkRead(long id, CancellationToken ct)
    {
        await notifications.MarkAsReadAsync(id, ct);
        return NoContent();
    }

    [HttpPost("read-all")]
    public async Task<ActionResult<int>> MarkAllRead(CancellationToken ct)
        => await notifications.MarkAllAsReadAsync(ct);
}
