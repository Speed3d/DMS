using Dms.Documents.Storage;
using Dms.Domain;
using Dms.Infrastructure.Incoming;
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

    /// <summary>عدد المرفقات لكل مالك — **استعلامٌ واحد** لقائمةٍ كاملة لا واحدٌ لكل صفّ.</summary>
    Task<Dictionary<int, int>> CountByOwnersAsync(
        OwnerType ownerType, List<int> ownerIds, CancellationToken ct = default);
}

public sealed class AttachmentService(
    AppDbContext db, ICurrentUser current, IAuditService audit, IFileStorage storage,
    IIncomingService incoming) : IAttachmentService
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
    /// <summary>عدد المرفقات لكل مالك — للعرض فقط، فلا يفحص كل مالكٍ على حدة.</summary>
    /// <remarks>
    /// ⚠️ **بلا `EnsureOwnerAccessibleAsync` لكل معرّف**: المنادي جلب الصفوف بنفسه من
    /// استعلامٍ **مفلترٍ بالشركة**، فالمعرّفات مرئيةٌ له أصلاً. وفحصُها واحداً واحداً كان
    /// يُنتج مئة رحلةٍ لعرض عدّاد.
    /// </remarks>
    public async Task<Dictionary<int, int>> CountByOwnersAsync(
        OwnerType ownerType, List<int> ownerIds, CancellationToken ct = default)
    {
        if (ownerIds.Count == 0) return [];
        return await db.Attachments
            .Where(a => a.OwnerType == ownerType && ownerIds.Contains(a.OwnerId))
            .GroupBy(a => a.OwnerId)
            .Select(g => new { OwnerId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.OwnerId, x => x.Count, ct);
    }

    private async Task EnsureOwnerAccessibleAsync(OwnerType type, int ownerId, CancellationToken ct)
    {
        // فحص صلاحية القسم (يمنع تجاوز تقييد الأقسام عبر مسار المرفقات المباشر).
        var requiredModule = type switch
        {
            OwnerType.Outgoing => AppModule.Outgoing,
            OwnerType.Archive => AppModule.Archive,
            OwnerType.Incoming => AppModule.Incoming,
            OwnerType.Employee => AppModule.Employees,
            OwnerType.PayrollEntry => AppModule.Payroll,
            _ => throw new ValidationException("نوع غير معروف")
        };
        if (!current.HasModule(requiredModule))
            throw new ForbiddenException("لا تملك صلاحية الوصول لهذا القسم.");

        // ── مستمسكات الموظف: الرؤية بالإسناد لا بالمُنشئ ──
        // ⚠️ Employee **بلا CreatedByUserId يُقاس عليه** (كيان عابر للشركات)، فقاعدة «عنصر
        //    غيرك» أدناه لا تنطبق. والحدّ الحقيقي هو الفلتر العام: موظفٌ غير مُسنَد للشركة
        //    الفعّالة لا يُرى أصلاً. ونضيف حدّ الدور **مرآةً لـ`[RequireHrModule]`** (ADR-025):
        //    القارئ محجوبٌ بدوره، فلا يبلغ المستمسكات من باب المرفقات بعد أن حُجب عن الوحدة.
        if (type == OwnerType.Employee)
        {
            if (current.Role is not { } hrRole || !RoleHierarchy.IsEmployeeOrAbove(hrRole))
                throw new ForbiddenException("مستمسكات الموظفين غير متاحة لدور القارئ.");

            var visible = await db.Employees.AnyAsync(e => e.EmployeeId == ownerId, ct);
            if (!visible)
                throw new NotFoundException("الموظف غير موجود أو لا تملك صلاحية رؤيته.");
            return;
        }

        // ── إيصال الاستلام الموقَّع: مالكُه سطرُ راتبٍ في شهر (ADR-026) ──
        // ⚠️ الحدّ الحقيقي هو الفلتر العام على `PayrollEntries`: سطرُ شركةٍ أخرى لا يُعثر
        //    عليه أصلاً. ونضيف حدّ الدور مرآةً لـ`[RequireHrModule]` فلا يبلغه القارئ.
        if (type == OwnerType.PayrollEntry)
        {
            if (current.Role is not { } payRole || !RoleHierarchy.IsEmployeeOrAbove(payRole))
                throw new ForbiddenException("إيصالات الرواتب غير متاحة لدور القارئ.");

            var seen = await db.PayrollEntries.AnyAsync(e => e.EntryId == ownerId && !e.IsDeleted, ct);
            if (!seen)
                throw new NotFoundException("سطر الراتب غير موجود أو لا تملك صلاحية رؤيته.");
            return;
        }

        // ── الوارد: الرؤية ليست «مَن أنشأ» بل قاعدة ADR-015 ──
        // ⚠️ كان الوارد يُفحَص بـ CreatedByUserId مثل الصادر والأرشيف، فكان موظف القسم يُمنع
        //    من مرفقات كتاب **مُحال إلى قسمه** («لا تملك صلاحية الوصول لمرفقات عنصر غيرك»)
        //    رغم أنه يرى الكتاب نفسه. السبب أن قاعدة الرؤية كانت مكتوبة في مكانين فتباعدا.
        //    نستدعي الآن **نفس** استعلام الخدمة، فلا مجال لتباعد ثانٍ.
        if (type == OwnerType.Incoming)
        {
            var visible = await incoming.Query().AnyAsync(b => b.IncomingId == ownerId, ct);
            if (!visible)
                throw new NotFoundException("الكتاب الوارد غير موجود أو لا تملك صلاحية رؤيته.");
            return;
        }

        int? creator = type switch
        {
            OwnerType.Outgoing => await db.OutgoingBooks.Where(b => b.OutgoingId == ownerId)
                .Select(b => (int?)b.CreatedByUserId).FirstOrDefaultAsync(ct),
            OwnerType.Archive => await db.ArchiveDocs.Where(a => a.ArchiveId == ownerId)
                .Select(a => (int?)a.CreatedByUserId).FirstOrDefaultAsync(ct),
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
