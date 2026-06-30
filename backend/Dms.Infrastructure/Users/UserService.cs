using Dms.Domain;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Users;

public sealed record CreateUserInput(
    string FullName, string Username, string Password, UserRole Role, int? CompanyId, bool CanApprove);

public sealed record UpdateUserInput(string FullName, UserRole Role, bool IsActive, bool CanApprove);

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
        var q = db.Users.AsQueryable();
        // كل مستخدم يرى المستويات الأدنى منه فقط (العزل حسب الشركة يفرضه DbContext)
        if (current.Role is { } role && !current.IsSuperAdmin)
            q = q.Where(u => (int)u.Role > (int)role);
        return await q.OrderBy(u => u.Role).ThenBy(u => u.FullName).ToListAsync(ct);
    }

    public async Task<User> CreateAsync(CreateUserInput input, CancellationToken ct = default)
    {
        EnsureCanManage(input.Role);
        if (string.IsNullOrWhiteSpace(input.Username)) throw new ValidationException("اسم المستخدم مطلوب.");
        if (string.IsNullOrWhiteSpace(input.Password) || input.Password.Length < 8)
            throw new ValidationException("كلمة المرور يجب ألا تقل عن 8 أحرف.");
        if (await db.Users.IgnoreQueryFilters().AnyAsync(u => u.Username == input.Username, ct))
            throw new ConflictException("اسم المستخدم مستخدم بالفعل.");

        var companyId = ResolveCompany(input.CompanyId, input.Role);

        var user = new User
        {
            FullName = input.FullName.Trim(),
            Username = input.Username.Trim(),
            PasswordHash = hasher.Hash(input.Password),
            Role = input.Role,
            CompanyId = companyId,
            CanApprove = input.CanApprove || RoleHierarchy.IsManagerOrAbove(input.Role),
            IsActive = true,
            MustChangePassword = true,
            CreatedByUserId = current.UserId,
            CreatedAt = DateTime.UtcNow,
        };
        db.Users.Add(user);
        audit.Add("Create", nameof(User), null, $"إنشاء مستخدم {user.Username} ({user.Role})", companyId);
        await db.SaveChangesAsync(ct);
        return user;
    }

    public async Task<User> UpdateAsync(int id, UpdateUserInput input, CancellationToken ct = default)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.UserId == id, ct)
                   ?? throw new NotFoundException("المستخدم غير موجود.");
        EnsureCanManage(user.Role);     // الدور الحالي
        EnsureCanManage(input.Role);    // الدور الجديد
        if (user.UserId == current.UserId) throw new ValidationException("لا يمكنك تعديل دورك بنفسك.");

        user.FullName = input.FullName.Trim();
        user.Role = input.Role;
        user.IsActive = input.IsActive;
        user.CanApprove = input.CanApprove || RoleHierarchy.IsManagerOrAbove(input.Role);
        audit.Add("Update", nameof(User), id.ToString(), null, user.CompanyId);
        await db.SaveChangesAsync(ct);
        return user;
    }

    public async Task ResetPasswordAsync(int id, string newPassword, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(newPassword) || newPassword.Length < 8)
            throw new ValidationException("كلمة المرور يجب ألا تقل عن 8 أحرف.");
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

    private int? ResolveCompany(int? requested, UserRole role)
    {
        if (current.IsSuperAdmin)
            return role == UserRole.SuperAdmin ? null : requested; // سوبر أدمن بلا شركة
        // غير السوبر أدمن: ضمن شركته فقط
        return current.ActiveCompanyId
               ?? throw new ValidationException("تعذّر تحديد الشركة.");
    }
}
