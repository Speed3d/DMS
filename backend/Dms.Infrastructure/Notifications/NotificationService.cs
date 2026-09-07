using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Notifications;

public sealed record NotificationInput(
    int RecipientUserId, int CompanyId,
    string Title, string Body, string Category,
    string? EntityType = null, int? EntityId = null,
    NotificationPriority Priority = NotificationPriority.Normal,
    string? DedupKey = null);

public interface INotificationService
{
    /// <summary>يُنشئ إشعاراً — **ويتخطّى المكرّر بصمت** إن كان له <c>DedupKey</c>.</summary>
    Task<Notification?> SendAsync(NotificationInput input, CancellationToken ct = default);

    /// <summary>دفعةً واحدة لعدّة مستلِمين — **ويستبعد الفاعل نفسه**.</summary>
    Task<int> SendManyAsync(
        IEnumerable<int> recipientIds, NotificationInput template, CancellationToken ct = default);

    Task<(List<Notification> Items, int Total)> GetAsync(
        int page, int pageSize, bool unreadOnly, CancellationToken ct = default);

    Task<int> GetUnreadCountAsync(CancellationToken ct = default);
    Task MarkAsReadAsync(long id, CancellationToken ct = default);
    Task<int> MarkAllAsReadAsync(CancellationToken ct = default);

    /// <summary>ينظّف ما مضى عليه أكثر من <paramref name="days"/> — تستعمله الدفعة ٦.</summary>
    Task<int> PurgeOlderThanAsync(int days, CancellationToken ct = default);

    // ── مَن يُشعَر: قوائمُ جاهزة تستعملها الوحدات ──
    Task<List<int>> ManagersOfCompanyAsync(int companyId, CancellationToken ct = default);
    Task<List<int>> PresidencyOfCompanyAsync(int companyId, CancellationToken ct = default);
    Task<List<int>> DepartmentMembersAsync(int companyId, int departmentId, CancellationToken ct = default);
}

/// <summary>
/// نظام الإشعارات (ADR-038) — كيانٌ عامّ يخدم كل الوحدات، لا المهام وحدها.
/// </summary>
/// <remarks>
/// 🔐 **ثلاث قواعد أمنية غير قابلة للتفاوض:**
/// <list type="number">
/// <item><b>الإشعار ملكُ صاحبه</b> — كل قراءةٍ مقيّدةٌ بـ<c>RecipientUserId == current.UserId</c>،
/// **ولا يُستثنى سوبر أدمن ولا رئيس**. الرقابة لها سجلّ التدقيق، وقراءةُ إشعارات الغير
/// اطّلاعٌ على ما وصل شخصاً بعينه.</item>
/// <item><b>الوسمُ بالمقروء على إشعار غيرك ⇒ 404 لا 403</b> — فلا يُفشى وجودُه.</item>
/// <item><b>لا يُشعَر الفاعلُ بفعل نفسه</b> — مَن حدّث النسبة لا يصله «حُدّثت النسبة».</item>
/// </list>
/// </remarks>
public sealed class NotificationService(AppDbContext db, ICurrentUser current) : INotificationService
{
    public async Task<Notification?> SendAsync(NotificationInput input, CancellationToken ct = default)
    {
        // 🔴 **لا يُشعَر الفاعلُ بفعل نفسه** — والحارس هنا لا في كل مُستدعٍ: نسيانُه في
        //    موضعٍ واحد يعني إشعاراً يصل صاحبَه بما فعله للتوّ، وهو أوّل ما يجعل المستخدم
        //    يتجاهل الجرس.
        if (current.UserId is { } me && input.RecipientUserId == me) return null;

        if (!string.IsNullOrWhiteSpace(input.DedupKey))
        {
            var exists = await db.Notifications.IgnoreQueryFilters().AnyAsync(
                n => n.RecipientUserId == input.RecipientUserId && n.DedupKey == input.DedupKey, ct);
            if (exists) return null;   // تكرارٌ يُتخطّى **بصمت** لا يُرمى
        }

        var row = new Notification
        {
            CompanyId = input.CompanyId,
            RecipientUserId = input.RecipientUserId,
            Title = Trim(input.Title, 200)!,
            Body = Trim(input.Body, 1000)!,
            Category = Trim(input.Category, 50)!,
            EntityType = Trim(input.EntityType, 100),
            EntityId = input.EntityId,
            Priority = input.Priority,
            CreatedByUserId = current.UserId,
            CreatedAt = DateTime.UtcNow,
            DedupKey = Trim(input.DedupKey, 200),
        };

        db.Notifications.Add(row);
        return row;
    }

    /// <inheritdoc/>
    /// <remarks>
    /// ⚠️ **يقرأ المفاتيح الموجودة دفعةً واحدة** لا واحداً لكل مستلِم — عشرون مديراً تعني
    /// عشرين استعلاماً لولا ذلك، والخدمة الخلفية تمرّ على كل المهام المتأخرة.
    /// </remarks>
    public async Task<int> SendManyAsync(
        IEnumerable<int> recipientIds, NotificationInput template, CancellationToken ct = default)
    {
        var ids = recipientIds.Distinct().ToList();
        if (current.UserId is { } me) ids.Remove(me);
        if (ids.Count == 0) return 0;

        var already = new HashSet<int>();
        if (!string.IsNullOrWhiteSpace(template.DedupKey))
        {
            already = (await db.Notifications.IgnoreQueryFilters()
                .Where(n => ids.Contains(n.RecipientUserId) && n.DedupKey == template.DedupKey)
                .Select(n => n.RecipientUserId)
                .ToListAsync(ct)).ToHashSet();
        }

        var added = 0;
        foreach (var id in ids)
        {
            if (already.Contains(id)) continue;

            db.Notifications.Add(new Notification
            {
                CompanyId = template.CompanyId,
                RecipientUserId = id,
                Title = Trim(template.Title, 200)!,
                Body = Trim(template.Body, 1000)!,
                Category = Trim(template.Category, 50)!,
                EntityType = Trim(template.EntityType, 100),
                EntityId = template.EntityId,
                Priority = template.Priority,
                CreatedByUserId = current.UserId,
                CreatedAt = DateTime.UtcNow,
                DedupKey = Trim(template.DedupKey, 200),
            });
            added++;
        }

        return added;
    }

    // ─────────────────────────── القراءة — ملكُ صاحبه ───────────────────────────

    /// <summary>إشعاراتي أنا — **ولا سبيل لقراءة إشعارات غيري من أي مسار**.</summary>
    private IQueryable<Notification> Mine()
    {
        var me = current.UserId ?? -1;

        // 🔴 **`IgnoreQueryFilters` عمداً مع شرطٍ أضيق**: الفلتر العام على الشركة يمنع
        //    المستخدم من رؤية إشعاراته في شركةٍ بدّلها للتوّ — وهو **إخفاءٌ خاطئ**: الإشعار
        //    وصله هو، لا شركته. والحدّ الحقيقي `RecipientUserId == me` وهو **أضيق** من
        //    فلتر الشركة لا أوسع.
        return db.Notifications.IgnoreQueryFilters().Where(n => n.RecipientUserId == me);
    }

    public async Task<(List<Notification> Items, int Total)> GetAsync(
        int page, int pageSize, bool unreadOnly, CancellationToken ct = default)
    {
        RequireAuthenticated();

        var q = Mine();
        if (unreadOnly) q = q.Where(n => !n.IsRead);

        var total = await q.CountAsync(ct);
        var items = await q
            .OrderByDescending(n => n.CreatedAt)
            .ThenByDescending(n => n.NotificationId)
            .Skip((Math.Max(page, 1) - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task<int> GetUnreadCountAsync(CancellationToken ct = default)
    {
        RequireAuthenticated();
        return await Mine().CountAsync(n => !n.IsRead, ct);
    }

    public async Task MarkAsReadAsync(long id, CancellationToken ct = default)
    {
        RequireAuthenticated();

        // 🔐 **404 لا 403**: إشعارٌ لغيرك **لا يُفشى وجودُه** — و403 تقول «موجودٌ ولا تملكه».
        var row = await Mine().FirstOrDefaultAsync(n => n.NotificationId == id, ct)
                  ?? throw new NotFoundException("الإشعار غير موجود.");

        if (row.IsRead) return;   // وسمُ المقروء ليس خطأً — يُقبَل صامتاً

        row.IsRead = true;
        row.ReadAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task<int> MarkAllAsReadAsync(CancellationToken ct = default)
    {
        RequireAuthenticated();

        var now = DateTime.UtcNow;
        var rows = await Mine().Where(n => !n.IsRead).ToListAsync(ct);
        foreach (var r in rows)
        {
            r.IsRead = true;
            r.ReadAt = now;
        }

        if (rows.Count > 0) await db.SaveChangesAsync(ct);
        return rows.Count;
    }

    /// <inheritdoc/>
    /// <remarks>
    /// ⚠️ **حذفٌ فعليّ — استثناءٌ صريح من قاعدة المشروع** (ADR-038): الإشعار إخطارٌ بحدث لا
    /// سجلُّ الحدث، والسجلّ في <c>DmsTaskUpdate</c> و<c>AuditLog</c> وكلاهما باقٍ.
    /// 🔴 **ويتخطّى الفلاتر عمداً** — التنظيف عمليةُ صيانةٍ على مستوى النظام لا قراءةُ مستخدم.
    /// </remarks>
    public async Task<int> PurgeOlderThanAsync(int days, CancellationToken ct = default)
    {
        if (days < 1) throw new ValidationException("مدّة الاحتفاظ يجب أن تكون يوماً فأكثر.");

        var cutoff = DateTime.UtcNow.AddDays(-days);
        return await db.Notifications.IgnoreQueryFilters()
            .Where(n => n.CreatedAt < cutoff)
            .ExecuteDeleteAsync(ct);
    }

    // ─────────────────────────── مَن يُشعَر ───────────────────────────

    /// <summary>كل مديري الشركة فأعلى — **مستوى التصعيد الثاني** (قرار المالك).</summary>
    /// <remarks>
    /// ⚠️ **«كل مدير» لا «مديرُ الموظف»**: النموذج بلا علاقة «موظف ← مديره»، واختراعُها لأجل
    /// التصعيد كان يعني حقلاً يُملأ يدوياً ويتقادم — **وتصعيدٌ إلى مديرٍ خطأ أسوأ من تصعيدٍ
    /// إلى الجميع**.
    /// </remarks>
    public async Task<List<int>> ManagersOfCompanyAsync(int companyId, CancellationToken ct = default)
        => await db.Users.IgnoreQueryFilters()
            .Where(u => u.IsActive
                     && (u.Role == UserRole.Manager || u.Role == UserRole.President)
                     && u.AssignedCompanies.Any(c => c.CompanyId == companyId))
            .Select(u => u.UserId)
            .ToListAsync(ct);

    /// <summary>رئيس الشركة — **وإلا السوبر أدمن احتياطاً**، فلا يضيع التصعيد الأخير.</summary>
    public async Task<List<int>> PresidencyOfCompanyAsync(int companyId, CancellationToken ct = default)
    {
        var presidents = await db.Users.IgnoreQueryFilters()
            .Where(u => u.IsActive && u.Role == UserRole.President
                     && u.AssignedCompanies.Any(c => c.CompanyId == companyId))
            .Select(u => u.UserId)
            .ToListAsync(ct);

        if (presidents.Count > 0) return presidents;

        // 🔴 **الاحتياط ليس تجميلاً**: شركةٌ بلا رئيسٍ مُسنَد تجعل المستوى الثالث يذهب إلى
        //    **لا أحد** — فتبقى مهمةٌ متأخرةٌ أسبوعاً بلا أن يعلم بها أحد فوق المدير.
        return await db.Users.IgnoreQueryFilters()
            .Where(u => u.IsActive && u.Role == UserRole.SuperAdmin)
            .Select(u => u.UserId)
            .ToListAsync(ct);
    }

    public async Task<List<int>> DepartmentMembersAsync(
        int companyId, int departmentId, CancellationToken ct = default)
        => await db.UserCompanies
            .Where(uc => uc.CompanyId == companyId && uc.DepartmentId == departmentId)
            .Select(uc => uc.UserId)
            .Distinct()
            .ToListAsync(ct);

    // ─────────────────────────── مساعدات ───────────────────────────

    private void RequireAuthenticated()
    {
        if (current.UserId is null) throw new ForbiddenException("غير مصرّح.");
    }

    private static string? Trim(string? s, int max)
        => s is null ? null : (s.Length <= max ? s : s[..max]);
}
