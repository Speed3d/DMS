using Dms.Domain;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Notifications;
using Dms.Infrastructure.Outgoing;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.CaseFiles;

/// <summary>نوع الكتاب داخل المعاملة — الوارد أو الصادر (v1 بلا الأضابير الورقية).</summary>
public enum CaseMemberKind { Incoming = 0, Outgoing = 1 }

/// <summary>عضوٌ في معاملة، كما يُعرض.</summary>
public sealed record CaseMemberData(
    CaseMemberKind Kind, int BookId, string? Number, DateTime Date, string Subject, string Status);

/// <summary>معاملةٌ بأعضائها المرئيّين وعددِ المحجوب عنهم.</summary>
public sealed record CaseFileData(
    CaseFile File, IReadOnlyList<CaseMemberData> Members, int HiddenCount);

/// <summary>سطرٌ في قائمة المعاملات.</summary>
public sealed record CaseFileRow(
    int CaseFileId, string Title, int VisibleCount, int HiddenCount, DateTime CreatedAt);

public interface ICaseFileService
{
    Task<List<CaseFileRow>> ListAsync(string? search, CancellationToken ct = default);
    Task<CaseFileData> GetAsync(int id, CancellationToken ct = default);
    Task<CaseFile> CreateAsync(string title, string? notes, CancellationToken ct = default);
    Task<CaseFile> RenameAsync(int id, string title, string? notes, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);

    Task AddMemberAsync(int caseFileId, CaseMemberKind kind, int bookId, CancellationToken ct = default);
    Task RemoveMemberAsync(int caseFileId, CaseMemberKind kind, int bookId, CancellationToken ct = default);
    Task MergeAsync(int targetId, int sourceId, CancellationToken ct = default);

    /// <summary>الكتب المرتبطة بكتابٍ بعينه — بطاقة «الكتب المرتبطة» في شاشتَي التفاصيل.</summary>
    Task<CaseFileData?> RelatedAsync(CaseMemberKind kind, int bookId, CancellationToken ct = default);

    /// <summary>🔑 زرّ «يخصّ كتاباً سابقاً»: يُنشئ معاملةً أو يضمّ إليها أو يدمج.</summary>
    Task<CaseFile> RelateAsync(
        CaseMemberKind kind, int bookId, CaseMemberKind otherKind, int otherBookId,
        string? title, CancellationToken ct = default);
}

/// <summary>
/// وحدة المعاملات (ADR-045) — **تنادي قاعدتَي الرؤية ولا تنسخهما**.
/// </summary>
/// <remarks>
/// 🔴 **مبدأ هذا الملفّ كلّه:** أعضاءُ المعاملة يُقرأون من <c>IIncomingService.Query()</c> و
/// <c>IOutgoingService.Query()</c> نفسيهما. ونسخُ شرطِ رؤيةٍ هنا كان يعني أن المعاملة تتباعد
/// عنهما عند أول تعديل — وهو بعينه ما كلّف المستودع عيبين حقيقيين (الوارد ثم ADR-030).
/// </remarks>
public sealed class CaseFileService(
    AppDbContext db,
    ICurrentUser current,
    IIncomingService incoming,
    IOutgoingService outgoing,
    IAuditService audit,
    INotificationService notifications) : ICaseFileService
{
    // ─────────────────────────── الحرّاس ───────────────────────────

    /// <summary>القراءة تشترط **أحد القسمين** — لا كليهما.</summary>
    /// <remarks>
    /// 🔴 **ولهذا لا `[RequireModule]` على وحدة التحكّم**: <c>HasModule</c> يفحص
    /// <c>(Allowed &amp; module) == module</c>، فـ<c>Incoming | Outgoing</c> تعني **«الاثنين معاً»**.
    /// واشتراطُ الوارد وحده كان **يحجب مَن يملك الصادر فقط** عن معاملةٍ كلُّ كتبه فيها صادر.
    /// </remarks>
    private void RequireReadAccess()
    {
        if (!current.HasModule(AppModule.Incoming) && !current.HasModule(AppModule.Outgoing))
            throw new ForbiddenException("لا تملك صلاحية الوصول للمعاملات.");
    }

    /// <summary>الكتابة: **العلَم مع الدور** — والقارئ محجوبٌ مهما مُنح.</summary>
    /// <remarks>
    /// 🔴 **بهذه الصيغة لا بـ`if (!CanManageIncoming)`**: `HttpCurrentUser` يقرأ العلَم من
    /// خريطة الشركة **بلا إعفاءٍ بالدور** (خلافاً لأعلام الموظفين والرواتب والمهام)، والسوبر
    /// أدمن قد يكون **بلا إسناد لأي شركة** فلا يحمل توكنه الخريطة أصلاً ⇒ **يُقفَل خارج ميزته**.
    /// وهو عطلٌ وقع فعلاً في وحدة الرواتب (`/me` أعاد `canManageHR=false` لحساب الأدمن).
    ///
    /// 🔐 **والقارئ يُحجب صراحةً**: `UserService.ResolveLinksAsync` يصفّر له الأعلام الحسّاسة
    /// الأربعة **ولا يمسّ `CanManageIncoming`** — فهو **يستطيع حملَه فعلاً** في القاعدة.
    /// وهذا نصُّ اللغم المكتوب هناك: «أيُّ فحصٍ قادمٍ يسأل عن العلَم وحده يمنح القارئَ إدارةً».
    /// </remarks>
    private void RequireWriteAccess()
    {
        RequireReadAccess();

        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if (role is UserRole.Reader)
            throw new ForbiddenException("القارئ لا يملك صلاحية تعديل المعاملات.");

        if (role is UserRole.Employee && !current.CanManageIncoming)
            throw new ForbiddenException("تحتاج صلاحية «إدارة الوارد» لتعديل المعاملات.");
    }

    // ─────────────────────── الأعضاء والرؤية ───────────────────────

    /// <summary>معرّفات الكتب المرئية في معاملة — **من `Query()` وبحارس القسم**.</summary>
    /// <remarks>
    /// ⚠️ **فحصُ القسم هنا ضروريّ**: `OutgoingService.Query()` **لا يفحص القسم بنفسه** —
    /// حارسُه سمةٌ على وحدة التحكّم، فاستدعاؤه من خدمةٍ أخرى **يتجاوزه**. وهو الفحص المزدوج
    /// نفسه في `ArchiveService.LensAsync` («بدونه يصير الأرشيف باباً خلفياً»).
    /// </remarks>
    private async Task<List<CaseMemberData>> VisibleMembersAsync(int caseFileId, CancellationToken ct)
    {
        var items = new List<CaseMemberData>();

        if (current.HasModule(AppModule.Incoming))
        {
            items.AddRange(await incoming.Query()
                .Where(b => b.CaseFileId == caseFileId)
                .OrderBy(b => b.ReceivedDate)
                .Select(b => new CaseMemberData(
                    CaseMemberKind.Incoming, b.IncomingId, b.IncomingNumber,
                    b.ReceivedDate, b.Subject, b.Status.ToString()))
                .ToListAsync(ct));
        }

        if (current.HasModule(AppModule.Outgoing))
        {
            items.AddRange(await outgoing.Query()
                .Where(b => b.CaseFileId == caseFileId)
                .OrderBy(b => b.Date)
                .Select(b => new CaseMemberData(
                    CaseMemberKind.Outgoing, b.OutgoingId, b.Number,
                    b.Date, b.Subject, b.Status.ToString()))
                .ToListAsync(ct));
        }

        return items.OrderBy(m => m.Date).ToList();
    }

    /// <summary>عدد كتب المعاملة **كلِّها في الشركة** — أساسُ عدّ المحجوب.</summary>
    /// <remarks>
    /// 🔑 **ولا `IgnoreQueryFilters` هنا إطلاقاً**: الفلتر العام على `db.IncomingBooks` يحمل
    /// **الشركة والحذف الناعم**، وحدُّ القسم داخل `Query()` فوقه. فالفرق بين العدّين هو
    /// المحجوب بحدّ القسم بالضبط — **طرحٌ بسيط بلا تجاوزٍ واحد للعزل**.
    /// </remarks>
    private async Task<int> TotalMembersAsync(int caseFileId, CancellationToken ct) =>
        await db.IncomingBooks.CountAsync(b => b.CaseFileId == caseFileId, ct)
        + await db.OutgoingBooks.CountAsync(b => b.CaseFileId == caseFileId, ct);

    // ─────────────────────────── القراءة ───────────────────────────

    public async Task<List<CaseFileRow>> ListAsync(string? search, CancellationToken ct = default)
    {
        RequireReadAccess();

        var q = db.CaseFiles.AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(c => c.Title.Contains(search));

        var files = await q.OrderByDescending(c => c.CreatedAt).ToListAsync(ct);

        var rows = new List<CaseFileRow>();
        foreach (var f in files)
        {
            var visible = await VisibleMembersAsync(f.CaseFileId, ct);
            var total = await TotalMembersAsync(f.CaseFileId, ct);

            // 🔐 **معاملةٌ لا يرى منها الطالب كتاباً واحداً لا تُعرض إطلاقاً** — وإلا صارت
            //    الشاشة **دليلاً بعناوين كلّ ما تعمل عليه الشركة**، وعنوانُ المعاملة إفصاح.
            // ⚠️ **والفارغة تُعرض** (نظير `GetAsync`): لا كتابَ فيها تُخفيه، وهي حالةٌ عابرة
            //    (تُطوى تلقائياً بخروج آخر كتاب) — وإخفاؤها كان يُخفيها عن مُنشئها فور إنشائها.
            if (total > 0 && visible.Count == 0) continue;

            rows.Add(new CaseFileRow(f.CaseFileId, f.Title, visible.Count, total - visible.Count, f.CreatedAt));
        }
        return rows;
    }

    public async Task<CaseFileData> GetAsync(int id, CancellationToken ct = default)
    {
        RequireReadAccess();

        var file = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == id, ct)
                   ?? throw new NotFoundException("المعاملة غير موجودة.");

        var visible = await VisibleMembersAsync(id, ct);
        var total = await TotalMembersAsync(id, ct);

        // 🔐 **وجودُ المعاملة نفسه ليس معلومةً تُكشف** لمن لا يرى فيها شيئاً (سابقة ADR-038).
        //
        // 🔴 **والفارغة ليست «كلُّها محجوبة»** — وخلطُهما عيبٌ كشفه `case-files-e2e`:
        //    معاملةٌ أُنشئت لتوّها بلا كتب كانت تردّ **404 على مُنشئها نفسه**، فينكسر
        //    `POST /case-files` الذي يُنهي بـ`Get`. والفرق حقيقيّ: **ما لا كتابَ فيه أصلاً
        //    لا يُخفي شيئاً**، وإنما يُخفى ما فيه كتبٌ كلُّها خارج صلاحية الناظر.
        if (total > 0 && visible.Count == 0)
            throw new NotFoundException("المعاملة غير موجودة.");

        return new CaseFileData(file, visible, total - visible.Count);
    }

    public async Task<CaseFileData?> RelatedAsync(CaseMemberKind kind, int bookId, CancellationToken ct = default)
    {
        RequireReadAccess();

        var caseFileId = await CaseFileIdOfVisibleBookAsync(kind, bookId, ct);
        if (caseFileId is null) return null;

        var file = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == caseFileId, ct);
        if (file is null) return null;

        var visible = (await VisibleMembersAsync(file.CaseFileId, ct))
            // الكتابُ نفسه ليس «مرتبطاً بنفسه».
            .Where(m => !(m.Kind == kind && m.BookId == bookId))
            .ToList();

        var total = await TotalMembersAsync(file.CaseFileId, ct) - 1;
        return new CaseFileData(file, visible, Math.Max(0, total - visible.Count));
    }

    // ─────────────────────────── الكتابة ───────────────────────────

    public async Task<CaseFile> CreateAsync(string title, string? notes, CancellationToken ct = default)
    {
        RequireWriteAccess();

        var companyId = current.ActiveCompanyId
            ?? throw new ValidationException("تعذّر تحديد الشركة. حدّد الشركة الفعّالة.");

        var file = new CaseFile
        {
            CompanyId = companyId,
            Title = CaseFileRules.EnsureTitle(title),
            Notes = notes,
            CreatedByUserId = current.UserId!.Value,
            CreatedAt = DateTime.UtcNow,
        };
        db.CaseFiles.Add(file);

        audit.Add("Create", nameof(CaseFile), null, $"إنشاء معاملة: {file.Title}", companyId);
        await db.SaveChangesAsync(ct);
        return file;
    }

    public async Task<CaseFile> RenameAsync(int id, string title, string? notes, CancellationToken ct = default)
    {
        RequireWriteAccess();
        await GetAsync(id, ct);   // يفرض الرؤية قبل التعديل

        var file = await db.CaseFiles.FirstAsync(c => c.CaseFileId == id, ct);
        file.Title = CaseFileRules.EnsureTitle(title);
        file.Notes = notes;
        file.UpdatedAt = DateTime.UtcNow;

        audit.Add("Update", nameof(CaseFile), id.ToString(), $"تعديل معاملة: {file.Title}", file.CompanyId);
        await db.SaveChangesAsync(ct);
        return file;
    }

    /// <inheritdoc/>
    /// <remarks>
    /// ⚠️ **الحذف للفارغة وحدها**: معاملةٌ فيها كتب يختفي خيطُها بضغطةٍ واحدة. والإفراغ
    /// يقع بإخراج الكتب واحداً واحداً — وهو ما يجعل الفعل **مرئياً** في سجلّ كلٍّ منها.
    /// </remarks>
    public async Task DeleteAsync(int id, CancellationToken ct = default)
    {
        RequireWriteAccess();
        await GetAsync(id, ct);

        var total = await TotalMembersAsync(id, ct);
        if (total > 0)
            throw new ValidationException(
                $"لا يمكن حذف معاملةٍ فيها {total} كتاباً — أخرِج كتبها أولاً.");

        var file = await db.CaseFiles.FirstAsync(c => c.CaseFileId == id, ct);
        file.IsDeleted = true;
        file.DeletedByUserId = current.UserId;
        file.DeletedAt = DateTime.UtcNow;

        audit.Add("Delete", nameof(CaseFile), id.ToString(), "حذف معاملة فارغة", file.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    public async Task AddMemberAsync(int caseFileId, CaseMemberKind kind, int bookId, CancellationToken ct = default)
    {
        RequireWriteAccess();

        var file = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == caseFileId, ct)
                   ?? throw new NotFoundException("المعاملة غير موجودة.");

        await AttachAsync(file, kind, bookId, ct);
        await db.SaveChangesAsync(ct);

        // 🔴 **بعد الحفظ لا قبله**: المستلِمون يُقرأون من القاعدة، والكتابُ المضموم لتوّه
        //    **لم يُثبَّت بعد** — فنداءٌ قبل الحفظ لا يرى الانضمام ولا يصل أحداً.
        await NotifyFollowersAsync(file, kind, bookId, ct);
    }

    public async Task RemoveMemberAsync(int caseFileId, CaseMemberKind kind, int bookId, CancellationToken ct = default)
    {
        RequireWriteAccess();

        var current_ = await CaseFileIdOfVisibleBookAsync(kind, bookId, ct);
        if (current_ != caseFileId)
            throw new ValidationException("هذا الكتاب ليس ضمن هذه المعاملة.");

        var file = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == caseFileId, ct)
                   ?? throw new NotFoundException("المعاملة غير موجودة.");

        await SetCaseFileAsync(kind, bookId, null, file, ct);
        await db.SaveChangesAsync(ct);

        await RetireIfEmptyAsync(file, ct);
    }

    /// <inheritdoc/>
    /// <remarks>
    /// 🔴 **داخل معاملةٍ بقفلٍ مرتّب**: دمجان متزامنان (أ←ب) و(ب←أ) بلا ذلك يحذفان الاثنتين
    /// أو يُديران الكتب بينهما. والترتيب بالمعرّف الأصغر يمنع الجمود (deadlock).
    /// ⚠️ **و`ExecutionStrategy` إلزاميّ** مع `EnableRetryOnFailure` المُفعَّل.
    /// </remarks>
    public async Task MergeAsync(int targetId, int sourceId, CancellationToken ct = default)
    {
        RequireWriteAccess();

        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            // القفل بترتيبٍ ثابت (الأصغر أولاً) لا بترتيب الوسيطين.
            var first = Math.Min(targetId, sourceId);
            var second = Math.Max(targetId, sourceId);
            var lockedFirst = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == first, ct);
            var lockedSecond = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == second, ct);
            if (lockedFirst is null || lockedSecond is null)
                throw new NotFoundException("المعاملة غير موجودة.");

            var target = targetId == first ? lockedFirst : lockedSecond;
            var source = sourceId == first ? lockedFirst : lockedSecond;

            // 🔐 فحصٌ صريح للشركة — لا اتّكالاً على الفلتر العام (السوبر أدمن بلا شركة
            //    فعّالة يُعطّله كلَّه، فيصير دمجُ معاملتَي شركتين ممكناً).
            if (target.CompanyId != source.CompanyId)
                throw new ValidationException("لا يمكن دمج معاملتين من شركتين مختلفتين.");

            CaseFileRules.EnsureCanMerge(
                sourceId, targetId,
                (await VisibleMembersAsync(sourceId, ct)).Count, await TotalMembersAsync(sourceId, ct),
                (await VisibleMembersAsync(targetId, ct)).Count, await TotalMembersAsync(targetId, ct));

            var movedIncoming = await db.IncomingBooks.Where(b => b.CaseFileId == sourceId).ToListAsync(ct);
            foreach (var b in movedIncoming)
            {
                b.CaseFileId = targetId;
                b.UpdatedAt = DateTime.UtcNow;
                // سطرٌ لكل كتابٍ نُقل — فالتراجع يبقى ممكناً بيد إنسان.
                db.MovementLogs.Add(NewMovement(b.CompanyId, b.IncomingId, "CaseFileChanged",
                    $"نُقل إلى المعاملة «{target.Title}» بدمج «{source.Title}»"));
            }

            var movedOutgoing = await db.OutgoingBooks.Where(b => b.CaseFileId == sourceId).ToListAsync(ct);
            foreach (var b in movedOutgoing)
            {
                b.CaseFileId = targetId;
                b.UpdatedAt = DateTime.UtcNow;
            }

            source.IsDeleted = true;
            source.DeletedByUserId = current.UserId;
            source.DeletedAt = DateTime.UtcNow;

            audit.Add("Merge", nameof(CaseFile), targetId.ToString(),
                $"دمج «{source.Title}» في «{target.Title}» — {movedIncoming.Count + movedOutgoing.Count} كتاباً",
                target.CompanyId);

            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
    }

    /// <inheritdoc/>
    /// <remarks>
    /// 🔑 **المدخل الوحيد الذي يستعمله المستخدم فعلاً**: «هذا الكتاب يخصّ الكتاب الفلاني».
    /// ويتصرّف بحسب الحالة — **بلا أن يتعلّم المستخدم مفهوماً جديداً**:
    /// <list type="bullet">
    /// <item>كلاهما بلا معاملة ⇒ تُنشأ واحدة (بعنوانٍ يكتبه المُنشئ) ويُضمّان.</item>
    /// <item>أحدهما فيها ⇒ يُضمّ الآخر إليها.</item>
    /// <item>كلٌّ في معاملة ⇒ **دمج** (بحرّاسه).</item>
    /// <item>كلاهما في المعاملة نفسها ⇒ لا شيء.</item>
    /// </list>
    /// </remarks>
    public async Task<CaseFile> RelateAsync(
        CaseMemberKind kind, int bookId, CaseMemberKind otherKind, int otherBookId,
        string? title, CancellationToken ct = default)
    {
        RequireWriteAccess();

        if (kind == otherKind && bookId == otherBookId)
            throw new ValidationException("لا يمكن ربط الكتاب بنفسه.");

        var mine = await CaseFileIdOfVisibleBookAsync(kind, bookId, ct);
        var theirs = await CaseFileIdOfVisibleBookAsync(otherKind, otherBookId, ct);

        // ⚠️ **404 لا 409 لمن لا يرى الطرف الآخر** — والرسالة واحدة لا تفرّق بين «غير موجود»
        //    و«لا تراه»، وإلا صار الخطأ نفسه يكشف وجود كتابٍ محجوب (سابقة ADR-038).
        _ = await EnsureVisibleBookAsync(otherKind, otherBookId, ct);

        if (mine is not null && mine == theirs)
            return await db.CaseFiles.FirstAsync(c => c.CaseFileId == mine, ct);

        if (mine is not null && theirs is not null)
        {
            await MergeAsync(mine.Value, theirs.Value, ct);
            return await db.CaseFiles.FirstAsync(c => c.CaseFileId == mine, ct);
        }

        var existing = mine ?? theirs;
        CaseFile file;
        if (existing is not null)
        {
            file = await db.CaseFiles.FirstAsync(c => c.CaseFileId == existing, ct);
        }
        else
        {
            file = await CreateAsync(title ?? await DefaultTitleAsync(kind, bookId, ct), null, ct);
        }

        if (mine is null) await AttachAsync(file, kind, bookId, ct);
        if (theirs is null) await AttachAsync(file, otherKind, otherBookId, ct);
        await db.SaveChangesAsync(ct);

        // ⚠️ **إشعارٌ واحد عن الانضمام** لا اثنان: ربطُ كتابين حدثٌ واحد في نظر المتابع،
        //    و`DedupKey` يحمل الكتاب المضموم فلا يتكرّر إن أُعيد الربط.
        await NotifyFollowersAsync(file, otherKind, otherBookId, ct);

        return file;
    }

    // ─────────────────────────── مساعدات ───────────────────────────

    /// <summary>معرّف معاملة كتابٍ **يراه الطالب** — أو `null`.</summary>
    private async Task<int?> CaseFileIdOfVisibleBookAsync(CaseMemberKind kind, int bookId, CancellationToken ct) =>
        kind == CaseMemberKind.Incoming
            ? await incoming.Query().Where(b => b.IncomingId == bookId)
                .Select(b => b.CaseFileId).FirstOrDefaultAsync(ct)
            : await outgoing.Query().Where(b => b.OutgoingId == bookId)
                .Select(b => b.CaseFileId).FirstOrDefaultAsync(ct);

    /// <summary>يتحقّق أن الكتاب موجودٌ **ومرئيّ** — ويرمي 404 موحّدة وإلا.</summary>
    /// <remarks>
    /// 🔐 **وحارسُ القسم هنا أيضاً**: `Query()` لا يفحصه، فمن لا يملك قسم الصادر يجب ألّا
    /// يضمّ كتاباً صادراً ولو رآه الاستعلام.
    /// </remarks>
    private async Task<bool> EnsureVisibleBookAsync(CaseMemberKind kind, int bookId, CancellationToken ct)
    {
        var ok = kind == CaseMemberKind.Incoming
            ? current.HasModule(AppModule.Incoming)
              && await incoming.Query().AnyAsync(b => b.IncomingId == bookId, ct)
            : current.HasModule(AppModule.Outgoing)
              && await outgoing.Query().AnyAsync(b => b.OutgoingId == bookId, ct);

        if (!ok) throw new NotFoundException("الكتاب غير موجود أو لا تملك صلاحية رؤيته.");
        return true;
    }

    /// <summary>يضمّ كتاباً إلى معاملة — **بلا حفظ** (المُستدعي يحفظ).</summary>
    private async Task AttachAsync(CaseFile file, CaseMemberKind kind, int bookId, CancellationToken ct)
    {
        await EnsureVisibleBookAsync(kind, bookId, ct);

        var previous = await CaseFileIdOfVisibleBookAsync(kind, bookId, ct);
        if (previous == file.CaseFileId) return;

        await SetCaseFileAsync(kind, bookId, file.CaseFileId, file, ct);

        if (previous is not null)
        {
            // نقلٌ من معاملةٍ إلى أخرى — والقديمة قد تفرغ فتُطوى.
            var old = await db.CaseFiles.FirstOrDefaultAsync(c => c.CaseFileId == previous, ct);
            if (old is not null)
            {
                await db.SaveChangesAsync(ct);
                await RetireIfEmptyAsync(old, ct);
            }
        }
    }

    /// <summary>🔔 يُشعر **مَن له كتابٌ في المعاملة** بانضمام كتابٍ جديد (الدفعة ٤).</summary>
    /// <remarks>
    /// 🔐 **ومَن «يتابع المعاملة» هو مَن سجّل أحد كتبها الواردة أو أنشأ أحد صادراتها** —
    /// لا كلُّ من يراها. فالرؤية قد تأتي من القسم أو من صلاحيةٍ عامّة، **والمتابعة عملٌ باشره
    /// صاحبُه**؛ وإشعارُ كلِّ من يرى يُنتج ضجيجاً يُعلّم الناس تجاهل الجرس.
    ///
    /// ⚠️ **والقائمة تُبنى من الجدول لا من `Query()`**: المستلِمون هم أصحاب الكتب أنفسهم،
    /// ولو فُلترت بقاعدة رؤية **الفاعل** لسقط منها من لا يراه الفاعلُ — وهم أولى الناس بالخبر.
    /// والعزل قائمٌ بشرط `CompanyId` الصريح.
    ///
    /// ⚠️ **وتحفظ بنفسها**: تُنادى **بعد** حفظ الانضمام (وإلا لم ترَه)، فلا حفظَ لاحقاً يحملها.
    /// </remarks>
    private async Task NotifyFollowersAsync(
        CaseFile file, CaseMemberKind joinedKind, int joinedBookId, CancellationToken ct)
    {
        var recipients = await db.IncomingBooks
            .Where(b => b.CaseFileId == file.CaseFileId && b.CompanyId == file.CompanyId)
            .Select(b => b.ReceivedByUserId)
            .Union(db.OutgoingBooks
                .Where(b => b.CaseFileId == file.CaseFileId && b.CompanyId == file.CompanyId)
                .Select(b => b.CreatedByUserId))
            .Distinct()
            .ToListAsync(ct);

        if (recipients.Count == 0) return;

        await notifications.SendManyAsync(recipients, new NotificationInput(
            RecipientUserId: 0,
            CompanyId: file.CompanyId,
            Title: "كتابٌ جديد في معاملةٍ تتابعها",
            Body: file.Title,
            Category: NotificationKeys.CaseFileCategory,
            EntityType: nameof(CaseFile),
            EntityId: file.CaseFileId,
            Priority: NotificationPriority.Normal,
            DedupKey: NotificationKeys.CaseFileJoined(
                file.CaseFileId, joinedKind.ToString(), joinedBookId)), ct);

        await db.SaveChangesAsync(ct);
    }

    /// <summary>يضبط انتماء الكتاب ويكتب الأثر — **الوارد في سجلّ الحركة والصادر في التدقيق**.</summary>
    /// <remarks>
    /// ⚠️ **الأثر غير متماثل بين النوعين ولا مفرّ**: `MovementLog.IncomingId` **غير قابل
    /// للإفراغ**، فسجلُّ الحركة للوارد وحده. والصادر يكتفي بسجلّ التدقيق (قرار المالك) —
    /// **وأثرُه أن سطر الضمّ لا يظهر في شاشة الصادر**، وهو مقبولٌ في v1 ومُعلَن.
    /// </remarks>
    private async Task SetCaseFileAsync(
        CaseMemberKind kind, int bookId, int? caseFileId, CaseFile file, CancellationToken ct)
    {
        var joining = caseFileId is not null;
        var verb = joining ? "ضُمّ إلى" : "أُخرج من";

        if (kind == CaseMemberKind.Incoming)
        {
            var book = await db.IncomingBooks.FirstOrDefaultAsync(b => b.IncomingId == bookId, ct)
                       ?? throw new NotFoundException("الكتاب الوارد غير موجود.");

            // ⚠️ **الضمّ لا يمسّ الحالة إطلاقاً** — تجميعٌ لا إجراء (قرار المالك). وهذا
            //    يخالف الربط بصادر الذي ينقل إلى «تم الرد»، والزرّان متجاوران في الشاشة.
            if (joining && !CaseFileRules.CanJoin(book.Status))
                throw new ValidationException("لا يمكن ضمّ هذا الكتاب إلى معاملة.");

            book.CaseFileId = caseFileId;
            book.UpdatedAt = DateTime.UtcNow;
            db.MovementLogs.Add(NewMovement(book.CompanyId, book.IncomingId, "CaseFileChanged",
                $"{verb} المعاملة «{file.Title}»"));
            audit.Add(joining ? "Link" : "Unlink", nameof(IncomingBook), bookId.ToString(),
                $"{verb} المعاملة {file.Title}", book.CompanyId);
        }
        else
        {
            var book = await db.OutgoingBooks.FirstOrDefaultAsync(b => b.OutgoingId == bookId, ct)
                       ?? throw new NotFoundException("الكتاب الصادر غير موجود.");
            book.CaseFileId = caseFileId;
            book.UpdatedAt = DateTime.UtcNow;
            audit.Add(joining ? "Link" : "Unlink", nameof(OutgoingBook), bookId.ToString(),
                $"{verb} المعاملة {file.Title}", book.CompanyId);
        }
    }

    /// <summary>تُطوى المعاملة إن لم يبقَ فيها كتاب.</summary>
    /// <remarks>
    /// ⚠️ **وإلا بقيت فارغةً في قائمة الاختيار**، **ومرّت من حارس «يرى كل الكتب» مجاناً**
    /// (شرطٌ يتحقّق تلقائياً على الصفر) فصارت أداةَ دمجٍ بلا معنى.
    /// </remarks>
    private async Task RetireIfEmptyAsync(CaseFile file, CancellationToken ct)
    {
        if (file.IsDeleted) return;
        if (!CaseFileRules.ShouldRetire(await TotalMembersAsync(file.CaseFileId, ct))) return;

        file.IsDeleted = true;
        file.DeletedByUserId = current.UserId;
        file.DeletedAt = DateTime.UtcNow;
        audit.Add("Delete", nameof(CaseFile), file.CaseFileId.ToString(),
            "طيُّ معاملة فرغت من كتبها", file.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    private async Task<string> DefaultTitleAsync(CaseMemberKind kind, int bookId, CancellationToken ct)
    {
        var subject = kind == CaseMemberKind.Incoming
            ? await incoming.Query().Where(b => b.IncomingId == bookId).Select(b => b.Subject).FirstOrDefaultAsync(ct)
            : await outgoing.Query().Where(b => b.OutgoingId == bookId).Select(b => b.Subject).FirstOrDefaultAsync(ct);

        var t = (subject ?? "معاملة").Trim();
        return t.Length > CaseFileRules.MaxTitleLength ? t[..CaseFileRules.MaxTitleLength] : t;
    }

    private MovementLog NewMovement(int companyId, int incomingId, string action, string description) => new()
    {
        CompanyId = companyId,
        IncomingId = incomingId,
        Action = action,
        Description = description,
        PerformedByUserId = current.UserId!.Value,
        PerformedAt = DateTime.UtcNow,
    };
}
