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

/// <summary>
/// عددُ غير المقروء في شركةٍ **غير الفعّالة** — سطرٌ في ذيل قائمة الإشعارات (ADR-046).
/// </summary>
public sealed record CompanyUnread(int CompanyId, string CompanyName, int Unread);

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

    /// <summary>
    /// غيرُ المقروء في شركاتي **الأخرى** — يسدّ ثغرة الفقد الصامت بعد فلترة الشركة (ADR-046).
    /// </summary>
    Task<List<CompanyUnread>> OtherCompaniesUnreadAsync(CancellationToken ct = default);

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

    /// <summary>إشعاراتي أنا **في شركتي الفعّالة** — ولا سبيل لقراءة إشعارات غيري من أي مسار.</summary>
    /// <remarks>
    /// 🔴 **حدّان لا واحد (ADR-046 — نقضُ ADR-038 بقرار المالك):** الفلتر العام على الشركة
    /// **نافذٌ عمداً** (لا <c>IgnoreQueryFilters</c>)، وفوقه الحدُّ الشخصيّ
    /// <c>RecipientUserId == me</c>. فالإشعار **تابعٌ للشركة كالصادر والوارد والأرشيف**،
    /// ومَن بدّل شركته لا يرى إشعارات الأخرى.
    ///
    /// ⚠️ **ولماذا نُقض القرار السابق؟** كان يقول «الإشعار وصله هو لا شركته»، فيعرضه في كل
    /// الشركات. **والتشغيل أثبت أنه أسوأ**: الإشعار يُعرض ثم **لا يُفتح بالنقر** — لأن
    /// <c>GET /tasks/{id}</c> يمرّ بـ<c>Query()</c> المفلترة بالشركة **فيردّ 404**.
    /// 🔑 **ومدخلٌ يقود إلى لا شيء أسوأ من غيابه** (قاعدة `coding-standards.md`).
    ///
    /// 🔴 **وثغرةُ الفقد الصامت مسدودةٌ لا مُهمَلة**: ما يُحجب هنا يُعلَن **بالعدد واسم
    /// الشركة** في <see cref="OtherCompaniesUnreadAsync"/> — فالحجبُ بلا إعلانٍ كان يعني
    /// إشعاراً لا يعلم به صاحبُه **ثم يُحذف بعد 90 يوماً**.
    ///
    /// ⚠️ **والقُمع واحد**: القائمة والشارة والوسمُ بالمقروء (مفرداً وجُملةً) كلُّها تمرّ من
    /// هنا — فلا يبقى مسارٌ يرى غير ما تراه الشاشة.
    /// </remarks>
    private IQueryable<Notification> Mine()
    {
        var me = current.UserId ?? -1;
        return db.Notifications.Where(n => n.RecipientUserId == me);
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

    /// <summary>غيرُ المقروء في شركاتي الأخرى — بالعدد واسم الشركة (ADR-046).</summary>
    /// <remarks>
    /// 🔴 **`IgnoreQueryFilters` هنا مقصودٌ ومحروسٌ بثلاثة قيود معاً** — وهو التجاوز الوحيد
    /// في الملفّ، وغرضُه **الإعلان عن وجودِ إشعارات لا عرضُها**:
    /// <list type="number">
    /// <item><c>RecipientUserId == me</c> — إشعاراتي أنا لا غيري.</item>
    /// <item><c>CompanyId != active</c> — الشركة الفعّالة لها <see cref="GetAsync"/>.</item>
    /// <item>🔐 <c>AllowedCompanyIds</c> — **شركاتي المُسنَدة اليوم وحدها**.</item>
    /// </list>
    ///
    /// ⚠️ **ولماذا القيد الثالث؟** إشعارٌ قديم في شركةٍ **فُكّ إسنادي عنها** كان سيُعلن
    /// اسمَها في شاشتي — أي **يكشف علاقةً انتهت**، ويَعِد بتبديلٍ إليها **يرفضه الخادم**
    /// أصلاً (`ActiveCompanyId` يفحص المسموح). فالقيد يمنع كشفاً ووعداً كاذباً معاً.
    ///
    /// 🔐 **والمُفصَح عددٌ واسمُ شركةٍ يعرفها صاحبُها — بلا عنوانٍ ولا متن ولا معرّف كيان.**
    /// وهو نظير قاعدة «المحجوب بالعدد فقط» في المعاملات (ADR-045).
    ///
    /// ⚠️ **وبلا شركةٍ فعّالة لا معنى لـ«الأخرى»** — فيعود فارغاً للسوبر أدمن غير المُسنَد
    /// (وهو يرى إشعاراته كلَّها أصلاً لأن الفلتر العام مُعطَّل عنه).
    /// </remarks>
    public async Task<List<CompanyUnread>> OtherCompaniesUnreadAsync(CancellationToken ct = default)
    {
        RequireAuthenticated();

        if (current.ActiveCompanyId is not { } active) return [];

        var allowed = current.AllowedCompanyIds.Where(c => c != active).ToList();
        if (allowed.Count == 0) return [];

        var me = current.UserId ?? -1;

        var counts = await db.Notifications.IgnoreQueryFilters()
            .Where(n => n.RecipientUserId == me && !n.IsRead && allowed.Contains(n.CompanyId))
            .GroupBy(n => n.CompanyId)
            .Select(g => new { CompanyId = g.Key, Unread = g.Count() })
            .ToListAsync(ct);

        if (counts.Count == 0) return [];

        // ⚠️ **الأسماء باستعلامٍ ثانٍ** (نمط ADR-034): `Company` مفلترةٌ بالشركة الفعّالة،
        //    فربطٌ داخليّ عليها **يمحو الصفَّ لا الاسم** — فيختفي السطر كلُّه صامتاً.
        var ids = counts.Select(c => c.CompanyId).ToList();
        var names = await db.Companies.IgnoreQueryFilters()
            .Where(c => ids.Contains(c.CompanyId))
            .ToDictionaryAsync(c => c.CompanyId, c => c.Name, ct);

        return counts
            .Select(c => new CompanyUnread(
                c.CompanyId, names.TryGetValue(c.CompanyId, out var n) ? n : "—", c.Unread))
            .OrderByDescending(c => c.Unread)
            .ThenBy(c => c.CompanyName)
            .ToList();
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
