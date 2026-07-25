using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/departments")]
public sealed class DepartmentsController(AppDbContext db, ICurrentUser current, IAuditService audit) : ControllerBase
{
    /// <summary>
    /// أقسام الشركة الفعّالة. و<paramref name="companyId"/> يوسّع النطاق **للمانح** (سوبر أدمن/رئيس)
    /// ليملأ نموذج المستخدم بأقسام كل شركة مُسندة له (ADR-017).
    /// </summary>
    /// <remarks>
    /// Hint: بلا هذا المعامل كانت القائمة مفلترة بالشركة الفعّالة وحدها، فتعذّر إسناد الموظف
    /// لقسم في شركته الثانية — القسم ببساطة لا يظهر.
    /// </remarks>
    [HttpGet]
    public async Task<ActionResult<List<DepartmentResponse>>> List(int? companyId, CancellationToken ct)
    {
        var q = db.Departments.AsQueryable();

        if (companyId is not null)
        {
            var granter = current.IsSuperAdmin || current.Role == UserRole.President;
            if (!granter) throw new ForbiddenException("لا تملك صلاحية استعراض أقسام شركة أخرى.");
            // السوبر أدمن بلا حدود؛ الرئيس ضمن شركاته وحدها (fail-closed).
            if (!current.IsSuperAdmin && !current.AllowedCompanyIds.Contains(companyId.Value))
                throw new ForbiddenException("هذه الشركة ليست ضمن شركاتك.");
            q = q.IgnoreQueryFilters().Where(d => d.CompanyId == companyId.Value);
        }

        return await q.OrderBy(d => d.Name)
            .Select(d => new DepartmentResponse(d.DepartmentId, d.CompanyId, d.Name, d.IsActive))
            .ToListAsync(ct);
    }

    [HttpPost]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<DepartmentResponse>> Create(DepartmentRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم القسم مطلوب.");
        var companyId = current.ActiveCompanyId ?? req.CompanyId ?? throw new ValidationException("حدّد الشركة.");

        var name = req.Name.Trim();
        if (await db.Departments.AnyAsync(d => d.CompanyId == companyId && d.Name == name, ct))
            throw new ConflictException($"يوجد قسم بالاسم «{name}» في هذه الشركة.");

        var d = new Department { CompanyId = companyId, Name = name, IsActive = true, CreatedAt = DateTime.UtcNow };
        db.Departments.Add(d);
        audit.Add("Create", nameof(Department), null, d.Name, companyId);
        await db.SaveChangesAsync(ct);
        return new DepartmentResponse(d.DepartmentId, d.CompanyId, d.Name, d.IsActive);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<ActionResult<DepartmentResponse>> Update(int id, DepartmentRequest req, CancellationToken ct)
    {
        var d = await db.Departments.FirstOrDefaultAsync(x => x.DepartmentId == id, ct)
                ?? throw new NotFoundException("القسم غير موجود.");
        if (string.IsNullOrWhiteSpace(req.Name)) throw new ValidationException("اسم القسم مطلوب.");

        var name = req.Name.Trim();
        if (await db.Departments.AnyAsync(x => x.CompanyId == d.CompanyId && x.Name == name && x.DepartmentId != id, ct))
            throw new ConflictException($"يوجد قسم آخر بالاسم «{name}».");

        d.Name = name;
        d.IsActive = req.IsActive;
        audit.Add("Update", nameof(Department), id.ToString(), null, d.CompanyId);
        await db.SaveChangesAsync(ct);
        return new DepartmentResponse(d.DepartmentId, d.CompanyId, d.Name, d.IsActive);
    }

    /// <summary>
    /// حذف قسم — مسموح فقط إن لم يكن مستخدَماً في أي كتاب وارد.
    /// Hint: ارتباط المستخدمين به يُفكّ تلقائياً (SetNull)، لكن الكتب الواردة المحالة إليه سجلّ
    ///       رسمي — نرفض الحذف بـ 409 ونقترح التعطيل بدلاً منه (يبقى الاسم في السجلات).
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var d = await db.Departments.FirstOrDefaultAsync(x => x.DepartmentId == id, ct)
                ?? throw new NotFoundException("القسم غير موجود.");

        var usedInIncoming = await db.IncomingBooks.IgnoreQueryFilters().CountAsync(b => b.DepartmentId == id, ct);
        if (usedInIncoming > 0)
            throw new ConflictException(
                $"لا يمكن حذف القسم «{d.Name}» لأنه محال إليه {usedInIncoming} كتاب وارد. عطّله بدل حذفه.");

        db.Departments.Remove(d);
        audit.Add("Delete", nameof(Department), id.ToString(), d.Name, d.CompanyId);
        await db.SaveChangesAsync(ct);
        return NoContent();
    }
}
