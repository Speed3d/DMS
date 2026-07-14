using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Users;

public sealed record CreateUserInput(
    string FullName, string Username, string Password, UserRole Role, List<int>? CompanyIds, bool CanApprove);

public sealed record UpdateUserInput(string FullName, UserRole Role, List<int>? CompanyIds, bool IsActive, bool CanApprove);

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

        var companyIds = ResolveCompanies(input.CompanyIds, input.Role);
        if (input.Role != UserRole.SuperAdmin && !companyIds.Any())
            throw new ValidationException("يجب إسناد المستخدم لشركة واحدة على الأقل.");
        int? primaryCompanyId = companyIds.Any() ? companyIds.First() : null;

        var user = new User
        {
            FullName = input.FullName.Trim(),
            Username = input.Username.Trim(),
            PasswordHash = hasher.Hash(input.Password),
            Role = input.Role,
            CompanyId = primaryCompanyId,
            CanApprove = input.CanApprove || RoleHierarchy.IsManagerOrAbove(input.Role),
            IsActive = true,
            MustChangePassword = true,
            CreatedByUserId = current.UserId,
            CreatedAt = DateTime.UtcNow,
            AssignedCompanies = companyIds.Select(c => new UserCompany { CompanyId = c }).ToList()
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
        user.CanApprove = input.CanApprove || RoleHierarchy.IsManagerOrAbove(input.Role);

        // إسناد الشركات: السوبر أدمن ورئيس الشركة فقط، وفقط عند إرسال قائمة صريحة
        // (null = «لا تغيير» — يمنع مسح الإسنادات بالخطأ عند تعديل حقول أخرى).
        if (CanManageCompanies && input.CompanyIds is not null)
        {
            var companyIds = ResolveCompanies(input.CompanyIds, input.Role);
            if (input.Role != UserRole.SuperAdmin && !companyIds.Any())
                throw new ValidationException("يجب إسناد المستخدم لشركة واحدة على الأقل.");

            user.CompanyId = companyIds.Any() ? companyIds.First() : null;
            user.AssignedCompanies.Clear();
            foreach (var cid in companyIds)
                user.AssignedCompanies.Add(new UserCompany { CompanyId = cid });
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

    private List<int> ResolveCompanies(List<int>? requested, UserRole role)
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
            if (scoped.Any()) return scoped;
            var cid = current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة.");
            return new List<int> { cid };
        }
        // المدير/الموظف: لا يتحكمان بالإسناد — شركتهما النشطة فقط.
        var currentCid = current.ActiveCompanyId ?? throw new ValidationException("تعذّر تحديد الشركة.");
        return new List<int> { currentCid };
    }
}
