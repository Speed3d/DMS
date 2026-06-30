using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Users;

public sealed record CreateDelegationInput(int ToUserId, DateTime StartDate, DateTime? EndDate);

public interface IDelegationService
{
    Task<List<ApprovalDelegation>> ListAsync(CancellationToken ct = default);
    Task<ApprovalDelegation> CreateAsync(CreateDelegationInput input, CancellationToken ct = default);
    Task RevokeAsync(int id, CancellationToken ct = default);
}

/// <summary>تفويض صلاحية الاعتماد (دائم أو مؤقت) لموظف أدنى — Manager فأعلى فقط.</summary>
public sealed class DelegationService(AppDbContext db, ICurrentUser current, IAuditService audit) : IDelegationService
{
    public async Task<List<ApprovalDelegation>> ListAsync(CancellationToken ct = default)
        => await db.ApprovalDelegations.OrderByDescending(d => d.CreatedAt).ToListAsync(ct);

    public async Task<ApprovalDelegation> CreateAsync(CreateDelegationInput input, CancellationToken ct = default)
    {
        var role = current.Role ?? throw new ForbiddenException("غير مصرّح.");
        if (!current.IsSuperAdmin && !RoleHierarchy.IsManagerOrAbove(role))
            throw new ForbiddenException("التفويض يتطلب صلاحية مدير فأعلى.");

        var target = await db.Users.FirstOrDefaultAsync(u => u.UserId == input.ToUserId, ct)
                     ?? throw new NotFoundException("المستخدم المفوَّض غير موجود.");
        if (!current.IsSuperAdmin && !RoleHierarchy.CanManage(role, target.Role))
            throw new ForbiddenException("لا يمكنك التفويض إلا لمن هم أدنى منك.");
        if (input.EndDate is not null && input.EndDate <= input.StartDate)
            throw new ValidationException("تاريخ نهاية التفويض يجب أن يكون بعد بدايته.");

        var delegation = new ApprovalDelegation
        {
            CompanyId = target.CompanyId ?? current.ActiveCompanyId ?? 0,
            FromUserId = current.UserId!.Value,
            ToUserId = input.ToUserId,
            StartDate = input.StartDate,
            EndDate = input.EndDate,
            IsActive = true,
            CreatedByUserId = current.UserId!.Value,
            CreatedAt = DateTime.UtcNow,
        };
        db.ApprovalDelegations.Add(delegation);
        audit.Add("Delegate", nameof(ApprovalDelegation), null,
            $"تفويض اعتماد للمستخدم {input.ToUserId}", delegation.CompanyId);
        await db.SaveChangesAsync(ct);
        return delegation;
    }

    public async Task RevokeAsync(int id, CancellationToken ct = default)
    {
        var d = await db.ApprovalDelegations.FirstOrDefaultAsync(x => x.DelegationId == id, ct)
                ?? throw new NotFoundException("التفويض غير موجود.");
        d.IsActive = false;
        audit.Add("RevokeDelegation", nameof(ApprovalDelegation), id.ToString(), null, d.CompanyId);
        await db.SaveChangesAsync(ct);
    }
}
