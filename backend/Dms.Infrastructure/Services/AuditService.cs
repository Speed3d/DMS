using Dms.Domain;
using Dms.Infrastructure.Persistence;

namespace Dms.Infrastructure.Services;

public interface IAuditService
{
    /// <summary>يضيف سجل تدقيق إلى التتبّع (يُحفظ ضمن SaveChanges للعملية).</summary>
    void Add(string action, string entityType, string? entityId, string? details = null, int? companyId = null);
}

public sealed class AuditService(AppDbContext db, ICurrentUser current) : IAuditService
{
    public void Add(string action, string entityType, string? entityId, string? details = null, int? companyId = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            UserId = current.UserId,
            CompanyId = companyId ?? current.ActiveCompanyId,
            Action = action,
            EntityType = entityType,
            EntityId = entityId,
            Details = details,
            Timestamp = DateTime.UtcNow,
        });
    }
}
