using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Attachments;

public interface IAttachmentService
{
    Task<Attachment> AddAsync(OwnerType ownerType, int ownerId, string fileName, byte[] content, CancellationToken ct = default);
    Task<List<Attachment>> ListAsync(OwnerType ownerType, int ownerId, CancellationToken ct = default);
    Task<(Attachment meta, byte[] content)> GetAsync(int attachmentId, CancellationToken ct = default);
    Task DeleteAsync(int attachmentId, CancellationToken ct = default);
}

public sealed class AttachmentService(
    AppDbContext db, ICurrentUser current, IAuditService audit, IFileStorage storage) : IAttachmentService
{
    private const long MaxBytes = 50 * 1024 * 1024; // 50MB
    private static readonly string[] Allowed = [".pdf", ".jpg", ".jpeg", ".png", ".docx", ".xlsx", ".zip", ".dwg"];

    public async Task<Attachment> AddAsync(OwnerType ownerType, int ownerId, string fileName, byte[] content, CancellationToken ct = default)
    {
        RequireNotReader();
        await EnsureOwnerAccessibleAsync(ownerType, ownerId, ct);

        if (content.Length == 0) throw new ValidationException("الملف فارغ.");
        if (content.Length > MaxBytes) throw new ValidationException("حجم الملف يتجاوز الحد المسموح (50 ميغابايت).");
        var ext = Path.GetExtension(fileName).ToLowerInvariant();
        if (!Allowed.Contains(ext))
            throw new ValidationException("صيغة الملف غير مسموحة (PDF/JPG/PNG/DOCX/XLSX/ZIP/DWG).");

        var key = await storage.SaveAsync($"att-{ownerType}-{ownerId}-{Path.GetFileName(fileName)}", content, ct);
        var att = new Attachment
        {
            OwnerType = ownerType,
            OwnerId = ownerId,
            FileName = Path.GetFileName(fileName),
            BlobKey = key,
            FileType = ext.TrimStart('.'),
            FileSize = content.Length,
            UploadedByUserId = current.UserId ?? 0,
            UploadedAt = DateTime.UtcNow,
        };
        db.Attachments.Add(att);
        audit.Add("AddAttachment", ownerType.ToString(), ownerId.ToString(), att.FileName, current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);
        return att;
    }

    public async Task<List<Attachment>> ListAsync(OwnerType ownerType, int ownerId, CancellationToken ct = default)
    {
        await EnsureOwnerAccessibleAsync(ownerType, ownerId, ct);
        return await db.Attachments
            .Where(a => a.OwnerType == ownerType && a.OwnerId == ownerId)
            .OrderByDescending(a => a.UploadedAt).ToListAsync(ct);
    }

    public async Task<(Attachment meta, byte[] content)> GetAsync(int attachmentId, CancellationToken ct = default)
    {
        var att = await db.Attachments.FirstOrDefaultAsync(a => a.AttachmentId == attachmentId, ct)
                  ?? throw new NotFoundException("المرفق غير موجود.");
        await EnsureOwnerAccessibleAsync(att.OwnerType, att.OwnerId, ct);
        var bytes = await storage.ReadAsync(att.BlobKey, ct);
        return (att, bytes);
    }

    public async Task DeleteAsync(int attachmentId, CancellationToken ct = default)
    {
        RequireNotReader();
        var att = await db.Attachments.FirstOrDefaultAsync(a => a.AttachmentId == attachmentId, ct)
                  ?? throw new NotFoundException("المرفق غير موجود.");
        await EnsureOwnerAccessibleAsync(att.OwnerType, att.OwnerId, ct);

        db.Attachments.Remove(att);
        audit.Add("DeleteAttachment", att.OwnerType.ToString(), att.OwnerId.ToString(), att.FileName, current.ActiveCompanyId);
        await db.SaveChangesAsync(ct);
        await storage.DeleteAsync(att.BlobKey, ct);
    }

    /// <summary>يتحقق أن المالك (صادر/أرشيف) ضمن شركة المستخدم ورؤيته (الموظف/القارئ: عمله فقط).</summary>
    private async Task EnsureOwnerAccessibleAsync(OwnerType type, int ownerId, CancellationToken ct)
    {
        // فحص صلاحية القسم (يمنع تجاوز تقييد الأقسام عبر مسار المرفقات المباشر).
        var requiredModule = type switch
        {
            OwnerType.Outgoing => AppModule.Outgoing,
            OwnerType.Archive => AppModule.Archive,
            OwnerType.Incoming => AppModule.Incoming,
            _ => throw new ValidationException("نوع غير معروف")
        };
        if (!current.HasModule(requiredModule))
            throw new ForbiddenException("لا تملك صلاحية الوصول لهذا القسم.");

        int? creator = type switch
        {
            OwnerType.Outgoing => await db.OutgoingBooks.Where(b => b.OutgoingId == ownerId)
                .Select(b => (int?)b.CreatedByUserId).FirstOrDefaultAsync(ct),
            OwnerType.Archive => await db.ArchiveDocs.Where(a => a.ArchiveId == ownerId)
                .Select(a => (int?)a.CreatedByUserId).FirstOrDefaultAsync(ct),
            OwnerType.Incoming => await db.IncomingBooks.Where(b => b.IncomingId == ownerId)
                .Select(b => (int?)b.CreatedByUserId).FirstOrDefaultAsync(ct),
            _ => null,
        };
        if (creator is null)
            throw new NotFoundException("العنصر غير موجود أو لا تملك صلاحية الوصول.");

        if (current.Role is UserRole.Employee or UserRole.Reader && creator != current.UserId)
            throw new ForbiddenException("لا تملك صلاحية الوصول لمرفقات عنصر غيرك.");
    }

    private void RequireNotReader()
    {
        if (current.Role is null or UserRole.Reader)
            throw new ForbiddenException("القارئ لا يملك صلاحية تعديل المرفقات.");
    }
}
