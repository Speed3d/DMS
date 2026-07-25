using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Auth;

/// <summary>وصول المستخدم في شركة واحدة — الأقسام المسموحة وقسم العمل والصلاحيات (ADR-017).</summary>
public sealed record CompanyAccess(
    int CompanyId, List<string> Modules, int? DepartmentId, bool CanApprove, bool CanManageIncoming);

public sealed record AuthResult(
    string AccessToken, DateTime AccessExpires, string RefreshToken,
    int UserId, string FullName, string Username, UserRole Role,
    List<int> CompanyIds, bool MustChangePassword, List<CompanyAccess> Companies);

public interface IAuthService
{
    Task<AuthResult> LoginAsync(string username, string password, CancellationToken ct = default);
    Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct = default);
    Task LogoutAsync(string refreshToken, CancellationToken ct = default);
    Task ChangePasswordAsync(int userId, string currentPassword, string newPassword, CancellationToken ct = default);
}

public sealed class AuthService(
    AppDbContext db,
    IPasswordHasher hasher,
    IJwtTokenService tokens,
    IAuditService audit) : IAuthService
{
    private const int MaxFailed = 5;
    private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(15);

    public async Task<AuthResult> LoginAsync(string username, string password, CancellationToken ct = default)
    {
        var user = await db.Users.Include(u => u.AssignedCompanies).FirstOrDefaultAsync(u => u.Username == username, ct);
        if (user is null || !user.IsActive)
            throw new ValidationException("اسم المستخدم أو كلمة المرور غير صحيحة.");

        if (user.LockedUntil is not null && user.LockedUntil > DateTime.UtcNow)
            throw new ForbiddenException($"الحساب مقفل مؤقتاً حتى {user.LockedUntil:HH:mm}. حاول لاحقاً.");

        if (!hasher.Verify(password, user.PasswordHash))
        {
            user.FailedLoginCount++;
            if (user.FailedLoginCount >= MaxFailed)
            {
                user.LockedUntil = DateTime.UtcNow.Add(LockDuration);
                user.FailedLoginCount = 0;
                audit.Add("LoginLocked", nameof(User), user.UserId.ToString(), "قفل بعد محاولات فاشلة", user.CompanyId);
            }
            await db.SaveChangesAsync(ct);
            throw new ValidationException("اسم المستخدم أو كلمة المرور غير صحيحة.");
        }

        // نجاح: تصفير العدادات + إصدار الرموز
        user.FailedLoginCount = 0;
        user.LockedUntil = null;
        var result = await IssueAsync(user, ct);
        audit.Add("Login", nameof(User), user.UserId.ToString(), null, user.CompanyId);
        await db.SaveChangesAsync(ct);
        return result;
    }

    public async Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct = default)
    {
        var hash = tokens.HashRefreshToken(refreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is null || !stored.IsActive)
            throw new ForbiddenException("جلسة منتهية. سجّل الدخول مجدداً.");

        var user = await db.Users.Include(u => u.AssignedCompanies).FirstOrDefaultAsync(u => u.UserId == stored.UserId, ct);
        if (user is null || !user.IsActive)
            throw new ForbiddenException("الحساب غير متاح.");

        stored.RevokedAt = DateTime.UtcNow;          // تدوير الرمز
        var result = await IssueAsync(user, ct);
        await db.SaveChangesAsync(ct);
        return result;
    }

    public async Task LogoutAsync(string refreshToken, CancellationToken ct = default)
    {
        var hash = tokens.HashRefreshToken(refreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is { RevokedAt: null })
        {
            stored.RevokedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }
    }

    public async Task ChangePasswordAsync(int userId, string currentPassword, string newPassword, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(newPassword) || newPassword.Length < 8)
            throw new ValidationException("كلمة المرور الجديدة يجب ألا تقل عن 8 أحرف.");

        var user = await db.Users.FirstOrDefaultAsync(u => u.UserId == userId, ct)
                   ?? throw new NotFoundException("المستخدم غير موجود.");
        if (!hasher.Verify(currentPassword, user.PasswordHash))
            throw new ValidationException("كلمة المرور الحالية غير صحيحة.");

        user.PasswordHash = hasher.Hash(newPassword);
        user.MustChangePassword = false;
        audit.Add("ChangePassword", nameof(User), userId.ToString(), null, user.CompanyId);
        await db.SaveChangesAsync(ct);
    }

    private async Task<AuthResult> IssueAsync(User user, CancellationToken ct)
    {
        var pair = tokens.Create(user);
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.UserId,
            TokenHash = tokens.HashRefreshToken(pair.RefreshToken),
            ExpiresAt = pair.RefreshExpires,
            CreatedAt = DateTime.UtcNow,
        });
        // SaveChanges يتم في المستدعي
        await Task.CompletedTask;
        var companyIds = user.AssignedCompanies.Select(c => c.CompanyId).ToList();

        // الوصول **لكل شركة** (ADR-017) — تحتاجه الواجهة لتحدّث قائمتها الجانبية عند تبديل
        // الشركة بلا إعادة دخول. الأدوار المعفاة (سوبر أدمن/رئيس) تُرسَل بكل الأقسام.
        var exempt = user.Role is UserRole.SuperAdmin or UserRole.President;
        var access = user.AssignedCompanies
            .Select(c => new CompanyAccess(
                c.CompanyId,
                (exempt ? AppModule.All : c.Modules).ToNames(),
                c.DepartmentId,
                c.CanApprove,
                c.CanManageIncoming))
            .ToList();

        return new AuthResult(pair.AccessToken, pair.AccessExpires, pair.RefreshToken,
            user.UserId, user.FullName, user.Username, user.Role, companyIds,
            user.MustChangePassword, access);
    }
}
