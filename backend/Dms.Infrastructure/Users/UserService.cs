using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Users;

/// <summary>صلاحيات المستخدم وقسمه **في شركة واحدة** (ADR-017).</summary>
public sealed record UserCompanyInput(
    int CompanyId, List<string>? Modules = null, int? DepartmentId = null,
    bool CanApprove = false, bool CanManageIncoming = false, bool CanViewAllIncoming = false,
    bool CanManageEmployees = false, bool CanManagePayroll = false,
    bool CanAmendPaidPayroll = false,
    bool CanManageTasks = false);

public sealed record CreateUserInput(
    string FullName, string Username, string Password, UserRole Role, List<UserCompanyInput>? Companies);

public sealed record UpdateUserInput(
    string FullName, UserRole Role, List<UserCompanyInput>? Companies, bool IsActive);

public interface IUserService
{
    Task<List<User>> ListAsync(CancellationToken ct = default);
    Task<User> CreateAsync(CreateUserInput input, CancellationToken ct = default);
    Task<User> UpdateAsync(int id, UpdateUserInput input, CancellationToken ct = default);
    Task ResetPasswordAsync(int id, string newPassword, CancellationToken ct = default);
}

public sealed class UserService(
    AppDbContext db, ICurrentUser current, IPasswordHasher hasher, IAuditService audit) : IUserService
{
    public async Task<List<User>> ListAsync(CancellationToken ct = default)
    {
        // العزل حسب الشركة يفرضه الفلتر العام في AppDbContext (يشمل الشركات المُسندة).
        var q = db.Users.Include(u => u.AssignedCompanies).AsQueryable();

        // كل مستخدم يرى المستويات الأدنى منه فقط (عدا السوبر أدمن)
        if (current.Role is { } role && !current.IsSuperAdmin)
            q = q.Where(u => (int)u.Role > (int)role);
        return await q.OrderBy(u => u.Role).ThenBy(u => u.FullName).ToListAsync(ct);
    }

    /// <summary>هل يملك المستخدم الحالي صلاحية ربط/تعديل شركات مستخدم آخر؟ (السوبر أدمن ورئيس الشركة فقط)</summary>
    private bool CanManageCompanies =>
        current.IsSuperAdmin || current.Role == UserRole.President;

    public async Task<User> CreateAsync(CreateUserInput input, CancellationToken ct = default)
    {
        EnsureCanManage(input.Role);
        if (string.IsNullOrWhiteSpace(input.Username)) throw new ValidationException("اسم المستخدم مطلوب.");
        if (string.IsNullOrWhiteSpace(input.Password) || input.Password.Length < 8)
            throw new ValidationException("كلمة المرور يجب ألا تقل عن 8 أحرف.");
        if (await db.Users.IgnoreQueryFilters().AnyAsync(u => u.Username == input.Username, ct))
            throw new ConflictException("اسم المستخدم مستخدم بالفعل.");

        var links = await ResolveLinksAsync(input.Companies, input.Role, ct);
        if (input.Role != UserRole.SuperAdmin && links.Count == 0)
            throw new ValidationException("يجب إسناد المستخدم لشركة واحدة على الأقل.");
        int? primaryCompanyId = links.Count > 0 ? links[0].CompanyId : null;

        var user = new User
        {
            FullName = input.FullName.Trim(),
            Username = input.Username.Trim(),
            PasswordHash = hasher.Hash(input.Password),
            Role = input.Role,
            CompanyId = primaryCompanyId,
            IsActive = true,
            MustChangePassword = true,
            CreatedByUserId = current.UserId,
            CreatedAt = DateTime.UtcNow,
            AssignedCompanies = links
        };
        db.Users.Add(user);
        audit.Add("Create", nameof(User), null, $"إنشاء مستخدم {user.Username} ({user.Role})", primaryCompanyId);
        await db.SaveChangesAsync(ct);
        return user;
    }

    public async Task<User> UpdateAsync(int id, UpdateUserInput input, CancellationToken ct = default)
    {
        // العزل يفرضه الفلتر العام: مستخدم خارج نطاق الشركة الحالية يعود null ⇒ NotFound (fail-closed).
        var user = await db.Users.Include(u => u.AssignedCompanies).FirstOrDefaultAsync(u => u.UserId == id, ct)
                   ?? throw new NotFoundException("المستخدم غير موجود.");

        EnsureCanManage(user.Role);     // الدور الحالي
        EnsureCanManage(input.Role);    // الدور الجديد
        if (user.UserId == current.UserId) throw new ValidationException("لا يمكنك تعديل دورك بنفسك.");

        user.FullName = input.FullName.Trim();
        user.Role = input.Role;
        user.IsActive = input.IsActive;

        // الإسناد وما يحمله من صلاحيات وقسم: يُعاد بناؤه فقط عند إرسال قائمة صريحة
        // (null = «لا تغيير» — يمنع مسح الإسنادات بالخطأ عند تعديل حقول أخرى).
        if (input.Companies is not null)
        {
            // 🔴 **لا يمسّ المعدِّلُ إلا ما يملكه** (مراجعة 2026-09-23). الواجهة ترسل قائمة
            //    شركات المستخدم **كاملةً** دائماً، فكان الخادم:
            //    · يُسقط إسناداته في شركاتٍ **لا يملكها المعدِّل** (المدير يملك شركته الفعّالة
            //      وحدها، والرئيس شركاتِه) — فيخرج المستخدم من شركةٍ ثانية بتعديل اسمه.
            //    · ويعيد أقسامه إلى الافتراض (127) لأن المدير «لا يحدّد الأقسام» — فيكسب
            //      الصادرَ والتقارير مَن كان مقصوراً على الوارد، ويخسر المهام والرواتب.
            //    والعلاج: خارجَ نطاق المعدِّل يبقى كما هو، وداخلَه ما لا يتحكّم فيه يبقى كما هو.
            var existing = user.AssignedCompanies.ToList();
            var scope = EditableCompanies();
            bool InScope(int cid) => scope is null || scope.Contains(cid);

            var links = await ResolveLinksAsync(
                input.Companies.Where(c => InScope(c.CompanyId)).ToList(), input.Role, ct,
                existing, fallbackToActive: false);

            // ما خارج النطاق يبقى — لكن **قاعدة الدور تسري عليه**: مَن صار قارئاً يُجرَّد
            // من الأقسام الحسّاسة في كل شركاته لا في شركة المعدِّل وحدها.
            var kept = existing.Where(l => !InScope(l.CompanyId)).ToList();
            foreach (var k in kept) NormalizeForRole(k, input.Role);

            if (input.Role != UserRole.SuperAdmin && links.Count + kept.Count == 0)
                throw new ValidationException("يجب إسناد المستخدم لشركة واحدة على الأقل.");

            foreach (var old in existing.Where(l => InScope(l.CompanyId)))
                user.AssignedCompanies.Remove(old);
            foreach (var link in links) user.AssignedCompanies.Add(link);

            // الشركة الرئيسية تبقى ما دامت مُسندة، وإلا فأوّلُ إسنادٍ باقٍ.
            var finalIds = kept.Select(l => l.CompanyId).Concat(links.Select(l => l.CompanyId)).ToList();
            if (user.CompanyId is not { } primary || !finalIds.Contains(primary))
                user.CompanyId = links.Count > 0 ? links[0].CompanyId
                               : kept.Count > 0 ? kept[0].CompanyId : null;
        }

        audit.Add("Update", nameof(User), id.ToString(), null, user.CompanyId);
        await db.SaveChangesAsync(ct);
        return user;
    }

    public async Task ResetPasswordAsync(int id, string newPassword, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(newPassword) || newPassword.Length < 8)
            throw new ValidationException("كلمة المرور يجب ألا تقل عن 8 أحرف.");
        // العزل يفرضه الفلتر العام (fail-closed): مستخدم خارج النطاق يعود null ⇒ NotFound.
        var user = await db.Users.FirstOrDefaultAsync(u => u.UserId == id, ct)
                   ?? throw new NotFoundException("المستخدم غير موجود.");

        EnsureCanManage(user.Role);

        user.PasswordHash = hasher.Hash(newPassword);
        user.MustChangePassword = true;
        user.FailedLoginCount = 0;
        user.LockedUntil = null;
        audit.Add("ResetPassword", nameof(User), id.ToString(), null, user.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    private void EnsureCanManage(UserRole targetRole)
    {
        if (current.IsSuperAdmin) return;
        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if (!RoleHierarchy.CanManage(role, targetRole))
            throw new ForbiddenException("لا تملك صلاحية إدارة هذا المستوى.");
    }

    /// <summary>
    /// يبني إسنادات الشركات وما تحمله من صلاحيات وقسم (ADR-017).
    /// </summary>
    /// <remarks>
    /// Hint: كان القسم يُتحقَّق منه مقابل الشركة **الرئيسية** وحدها، فكان قسمٌ من شركة ثانية
    /// يُرفَض دائماً. الآن يُتحقَّق من كل قسم مقابل **شركة صفّه**.
    /// </remarks>
    /// <param name="existing">
    /// إسنادات المستخدم الحالية عند التعديل — ما لا يتحكّم فيه المعدِّل يُؤخذ منها لا من
    /// الافتراض (مراجعة 2026-09-23). <c>null</c> عند الإنشاء.
    /// </param>
    /// <param name="fallbackToActive">
    /// إن لم يطلب الرئيس شركةً من شركاته أُسند لشركته الفعّالة — **عند الإنشاء وحده**؛
    /// عند التعديل يعني ذلك أنه أزال إسنادات شركاته، فلا يُعاد فرضها عليه.
    /// </param>
    private async Task<List<UserCompany>> ResolveLinksAsync(
        List<UserCompanyInput>? requested, UserRole role, CancellationToken ct,
        IReadOnlyCollection<UserCompany>? existing = null, bool fallbackToActive = true)
    {
        var byCompany = (requested ?? new List<UserCompanyInput>())
            .GroupBy(c => c.CompanyId)
            .ToDictionary(g => g.Key, g => g.Last());

        var companyIds = ResolveCompanies(byCompany.Keys.ToList(), role, fallbackToActive);
        if (companyIds.Count == 0) return new List<UserCompany>();

        // المدير فأعلى يعتمد ويدير الوارد بحكم دوره في كل شركاته.
        var byRole = RoleHierarchy.IsManagerOrAbove(role);

        // هل يجوز أن يحمل هذا الدور أعلامَ الأقسام التي **تُمنح صراحةً**؟
        // مرآةٌ حرفية لشرط التجريد في `ResolveModules` — والاثنان يجب أن يتحرّكا معاً،
        // وإلا بقي العلَم بلا قسمه (وهو ما كان يقع فعلاً حتى ADR-037).
        var grantable = RoleHierarchy.IsEmployeeOrAbove(role);

        // أقسام الشركات المطلوبة دفعةً واحدة (تفادياً لاستعلام لكل صفّ).
        var wanted = byCompany.Values.Where(c => c.DepartmentId is not null)
            .Select(c => c.DepartmentId!.Value).Distinct().ToList();
        var deptCompany = wanted.Count == 0
            ? new Dictionary<int, int>()
            : await db.Departments.IgnoreQueryFilters()
                .Where(d => wanted.Contains(d.DepartmentId))
                .ToDictionaryAsync(d => d.DepartmentId, d => d.CompanyId, ct);

        var links = new List<UserCompany>();
        foreach (var cid in companyIds)
        {
            byCompany.TryGetValue(cid, out var wish);
            var prior = existing?.FirstOrDefault(l => l.CompanyId == cid);

            // ما لم يُطلب لهذه الشركة يبقى كما هو (المدير لا يتحكّم بالإسناد نفسه).
            if (wish is null && prior is not null) wish = FromLink(prior);

            // 🔐 **الأقسام والأعلام الحسّاسة ملكُ المانح وحده** (سوبر أدمن/رئيس): الواجهة
            //    تُخفيها عن المدير وترسل قيمها القائمة، فالخادم يأخذها **من القائمة لا من
            //    الطلب** — وإلا صار طلبٌ مباشرٌ من مديرٍ بابَ منحٍ لما لا يملك منحه.
            var sensitive = !CanManageCompanies && prior is not null ? FromLink(prior) : wish;

            int? deptId = wish?.DepartmentId;
            if (deptId is not null)
            {
                if (!deptCompany.TryGetValue(deptId.Value, out var owner) || owner != cid)
                    throw new ValidationException("القسم المحدّد غير موجود في الشركة المسندة له.");
            }

            links.Add(new UserCompany
            {
                CompanyId = cid,
                Modules = ResolveModules(wish?.Modules, role, prior?.Modules),
                DepartmentId = deptId,
                CanApprove = byRole || (wish?.CanApprove ?? false),
                CanManageIncoming = byRole || (wish?.CanManageIncoming ?? false),
                // Hint: `byRole` يعني المدير فأعلى — وهو يرى كل كتب الشركة بحكم دوره أصلاً
                //       (قاعدة الرؤية لا تقيّده)، فمنحُه العلَم توثيقٌ للواقع لا توسعة.
                CanViewAllIncoming = byRole || (wish?.CanViewAllIncoming ?? false),

                // ⚠️ **لا `byRole` هنا** خلافاً لأخواتها الثلاث: الوحدة كلها للمدير فأعلى،
                //    لكن ذلك يفتح **الرؤية** لا **الكتابة**. كونُه مديراً لا يعني تلقائياً أنه
                //    مَن يحرّر الرواتب — وهذا كل معنى فصل العلَم عن القسم.
                //
                // 🔴 **و`grantable` تُصفّرها كلها للقارئ** (ADR-037): `ResolveModules` يجرّد
                //    القارئ من الأقسام الثلاثة، وكان العلَم **يبقى مخزَّناً `true` بلا قسمٍ
                //    يراه**. كُشف بالتشغيل الحيّ لا بالمراجعة: `/me` أعاد للقارئ
                //    `modules=[Outgoing]` **و`canManageTasks=true` معاً**.
                //    ⚠️ **غيرُ مستغَلٍّ اليوم** — حدُّ الدور في `[RequireGrantedModule]` يحجبه —
                //    لكنه لغمٌ: أيُّ فحصٍ قادمٍ يسأل عن العلَم وحده يمنح القارئَ إدارةً.
                //    **علَمٌ جُرِّد قسمُه لا يبقى.**
                CanManageEmployees = grantable && (sensitive?.CanManageEmployees ?? false),
                CanManagePayroll = grantable && (sensitive?.CanManagePayroll ?? false),
                // ⚠️ **بلا `byRole`**: الإعفاء يقع في `HttpCurrentUser` بالدور، وإدراجه هنا
                //    كان يُخزّن `true` لكل مدير فيبدو في الشاشة ممنوحاً وهو ليس كذلك.
                CanAmendPaidPayroll = grantable && (sensitive?.CanAmendPaidPayroll ?? false),
                // ⚠️ **بلا `byRole` كأخواتها الثلاث أعلاه**: القسم يفتح مهامّه ومهامّ قسمه،
                //    وهذا العلَم يفتح **الإسناد لغيره**. وكونُه مديراً لا يعني أنه مَن يوزّع
                //    المهام — قد يكون مديرَ قسمٍ يستلم لا يوزّع (ADR-037).
                CanManageTasks = grantable && (sensitive?.CanManageTasks ?? false),
            });
        }
        return links;
    }

    private List<int> ResolveCompanies(List<int>? requested, UserRole role, bool fallbackToActive = true)
    {
        var reqList = (requested ?? new List<int>()).Distinct().ToList();
        if (current.IsSuperAdmin)
        {
            if (role == UserRole.SuperAdmin) return new List<int>(); // السوبر أدمن يمكن أن يكون بلا شركة
            return reqList;
        }
        if (current.Role == UserRole.President)
        {
            // رئيس الشركة: يربط ضمن شركاته المسموحة فقط؛ إن لم يحدّد صحيحاً فشركته النشطة افتراضياً.
            var allowed = current.AllowedCompanyIds;
            var scoped = reqList.Where(id => allowed.Contains(id)).ToList();
            if (scoped.Any() || !fallbackToActive) return scoped;
            var cid = current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة.");
            return new List<int> { cid };
        }
        // المدير/الموظف: لا يتحكمان بالإسناد — شركتهما النشطة فقط.
        var currentCid = current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة.");
        return new List<int> { currentCid };
    }

    /// <summary>
    /// يحدّد أقسام المستخدم عند الإنشاء: معفيان (كل شيء) للسوبر أدمن/الرئيس؛ غيرهما يحدّدها
    /// المانح المخوّل وإلا الأقسام الافتراضية.
    /// </summary>
    /// <remarks>
    /// ⚠️ **حارسان يمنعان تسريب الرواتب من هذا الموضع بالذات:**
    /// <list type="number">
    /// <item>مسار «التوافق الخلفي» يعيد <see cref="AppModule.All"/> **وهي 127 بلا HR** — فلو
    /// ضُمّت HR إليها لحصل كل مستخدم ينشئه مديرٌ بلا تحديد أقسام على رؤية رواتب الشركة كلها.</item>
    /// <item>ومَن دون المدير **تُجرَّد منه HR ولو طُلبت صراحةً** — قرار المالك أن الوحدة كلها
    /// للمدير فأعلى، وحارسٌ في الواجهة وحدها يُلتَفّ عليه بطلب HTTP مباشر.</item>
    /// </list>
    /// </remarks>
    private AppModule ResolveModules(List<string>? requested, UserRole targetRole, AppModule? prior = null)
    {
        if (targetRole is UserRole.SuperAdmin or UserRole.President) return AppModule.AllWithHr;

        // 🔴 **المدير لا يحدّد الأقسام — فعند التعديل تبقى كما هي** (مراجعة 2026-09-23).
        //    كان يعود إلى `All` في كل تعديل، فتُمحى قيود المانح بتعديل اسمٍ أو قسم.
        var modules = CanManageCompanies && requested is not null
            ? AppModuleExtensions.FromNames(requested)
            : prior ?? AppModule.All; // عند الإنشاء: توافق خلفي — المدير لا يقيّد (وAll لا تشمل HR)

        // ⚠️ **يُجرَّد القارئ وحده** (ADR-025 — كان «مَن دون المدير» في ADR-023).
        //    حارسٌ في الواجهة وحدها يُلتَفّ عليه بطلب HTTP مباشر، فالتجريد يقع هنا.
        //    🔴 **والمهام معها منذ ADR-037** بقرار المالك: دور القارئ اطّلاعٌ على الوثائق،
        //    والمهمة **تكليفٌ يُنفَّذ ويُحدَّث** لا وثيقةٌ تُقرأ.
        if (!RoleHierarchy.IsEmployeeOrAbove(targetRole))
            modules &= ~(AppModule.Employees | AppModule.Payroll | AppModule.Tasks);
        return modules;
    }

    /// <summary>
    /// الشركات التي يملك المعدِّلُ تعديلَ إسنادها — <c>null</c> = كلُّها (السوبر أدمن).
    /// </summary>
    /// <remarks>مرآةٌ لـ<see cref="ResolveCompanies"/>: الرئيس شركاتُه · وغيره شركتُه الفعّالة.</remarks>
    private HashSet<int>? EditableCompanies()
    {
        if (current.IsSuperAdmin) return null;
        if (current.Role == UserRole.President) return current.AllowedCompanyIds.ToHashSet();
        return current.ActiveCompanyId is { } cid ? [cid] : [];
    }

    private static UserCompanyInput FromLink(UserCompany l) => new(
        l.CompanyId, l.Modules.ToNames(), l.DepartmentId, l.CanApprove, l.CanManageIncoming,
        l.CanViewAllIncoming, l.CanManageEmployees, l.CanManagePayroll,
        l.CanAmendPaidPayroll, l.CanManageTasks);

    /// <summary>
    /// يطبّق قواعد الدور على إسنادٍ **لم يُعَد بناؤه** (خارج نطاق المعدِّل) — نفسَ ما يطبّقه
    /// <see cref="ResolveLinksAsync"/> على ما يبنيه، فلا يختلف الإسنادان باختلاف مَن عدّل.
    /// </summary>
    private static void NormalizeForRole(UserCompany l, UserRole role)
    {
        if (role is UserRole.SuperAdmin or UserRole.President) l.Modules = AppModule.AllWithHr;

        if (RoleHierarchy.IsManagerOrAbove(role))
        {
            l.CanApprove = true;
            l.CanManageIncoming = true;
            l.CanViewAllIncoming = true;
        }

        if (!RoleHierarchy.IsEmployeeOrAbove(role))
        {
            l.Modules &= ~(AppModule.Employees | AppModule.Payroll | AppModule.Tasks);
            l.CanManageEmployees = false;
            l.CanManagePayroll = false;
            l.CanAmendPaidPayroll = false;
            l.CanManageTasks = false;
        }
    }
}
