using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Incoming;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Archive)]
[Route("api/[controller]")]
public sealed class ArchiveController(
    IArchiveService svc,
    IAttachmentService attachments,
    AppDbContext db,
    IIncomingService incomingService,
    ICurrentUser current) : ControllerBase
{
    /// <summary>
    /// **عدسة الأرشيف**: عرض موحّد يجمع الوارد المؤرشف والأضابير الورقية، مرتّباً بالأحدث.
    /// </summary>
    /// <remarks>
    /// 🔐 **حدّ الصلاحية مزدوج على صفوف الوارد:** الوصول لهذه النقطة يتطلّب قسم «الأرشيف»
    /// (سِمة الصنف)، لكن صفوف الوارد المؤرشف **تتطلّب قسم «الوارد» أيضاً**. بدون هذا الشرط
    /// يصير الأرشيف **باباً خلفياً** يقرأ منه صاحبُ صلاحية الأرشيف كتبَ الوارد التي لا يملك
    /// رؤيتها — وهي بيانات محجوبة عنه في `/api/incoming` بحرّاسها.
    ///
    /// 🔐 **ورؤية الصفوف تُبنى على `IncomingService.Query()` نفسها** لا بإعادة كتابة الشرط:
    /// قاعدة الرؤية (ما استلمه · ما أُحيل لقسمه · ما أحاله بنفسه) تطوّرت مرّتين (ADR-015 ثم
    /// ADR-018)، ونسخةٌ ثانية منها هنا كانت ستتخلّف عن الأصل عند أي تعديل ثالث فتُسرّب أو تحجب.
    /// </remarks>
    [HttpGet("lens")]
    public async Task<ActionResult<List<ArchiveLensItem>>> Lens(
        [FromQuery] string? search, [FromQuery] int? year, [FromQuery] int? departmentId,
        CancellationToken ct = default)
    {
        var items = new List<ArchiveLensItem>();

        // ---- المصدر الأول: الوارد المؤرشف (يتطلّب قسم الوارد أيضاً) ----
        if (current.HasModule(AppModule.Incoming))
        {
            var q = incomingService.Query()
                .Where(b => b.Status == IncomingStatus.Archived)
                .Include(b => b.Entity)
                .Include(b => b.Assignments).ThenInclude(a => a.Department)
                .AsQueryable();

            if (!string.IsNullOrWhiteSpace(search))
                q = q.Where(b => (b.IncomingNumber != null && b.IncomingNumber.Contains(search))
                                 || b.Subject.Contains(search)
                                 || (b.Keywords != null && b.Keywords.Contains(search)));

            if (departmentId.HasValue)
                q = q.Where(b => b.Assignments.Any(a => a.DepartmentId == departmentId.Value));

            var books = await q.ToListAsync(ct);
            var typeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

            items.AddRange(books.Select(b =>
            {
                // Hint: `UpdatedAt` هو تاريخ الأرشفة فعلياً — التعديل ممنوع بعدها، فآخر
                //       تحديث للكتاب هو لحظة أرشفته. فلا حاجة لعمود جديد ولا مهاجرة.
                var archivedAt = b.UpdatedAt ?? b.CreatedAt;
                return new ArchiveLensItem(
                    ArchiveSource.Incoming, b.IncomingId, b.IncomingNumber ?? "—", b.Subject,
                    archivedAt, archivedAt.Year, archivedAt.Month,
                    b.Entity?.Name,
                    b.DocumentTypeId is not null && typeNames.TryGetValue(b.DocumentTypeId.Value, out var tn) ? tn : null,
                    b.Assignments.Select(a => a.Department?.Name ?? "—").ToList(),
                    b.Notes);
            }));
        }

        // ---- المصدر الثاني: الأضابير الورقية القديمة ----
        var docs = await svc.SearchAsync(new ArchiveSearchInput(search, null, null, null, null), ct);
        var docTypeNames = await db.DocumentTypes.ToDictionaryAsync(t => t.DocumentTypeId, t => t.Name, ct);

        items.AddRange(docs
            .Where(a => !departmentId.HasValue || a.DepartmentId == departmentId.Value)
            .Select(a =>
            {
                // تاريخ الكتاب الأصلي أدقّ للأضبارة القديمة من تاريخ إدخالها في النظام.
                var at = a.BookDate ?? a.CreatedAt;
                return new ArchiveLensItem(
                    ArchiveSource.Paper, a.ArchiveId, a.ArchiveNumber, a.Title,
                    at, at.Year, at.Month, null,
                    a.DocumentTypeId is not null && docTypeNames.TryGetValue(a.DocumentTypeId.Value, out var tn) ? tn : null,
                    a.Department?.Name is null ? [] : [a.Department.Name],
                    a.Notes);
            }));

        if (year.HasValue) items = items.Where(i => i.Year == year.Value).ToList();

        return items.OrderByDescending(i => i.ArchivedAt).ToList();
    }

    /// <summary>
    /// **استيراد دفعة من الأرشيف الورقي**: ملفات متعدّدة ببيانات وصفية مشتركة.
    /// </summary>
    /// <remarks>
    /// ⚠️ **لماذا بالجملة لا واحداً واحداً:** أرشيف الشركة ~80 غيغا ≈ **6,500 كتاب**؛
    /// إدخالها يدوياً بدقيقتين للكتاب = **٢٧ يوم عمل متواصل** — وهو ما لا يكتمل عملياً
    /// فينتهي الأمر بأرشيف نصفه في النظام ونصفه على أجهزة الموظفين.
    /// البيانات المشتركة (السنة/الشهر/القسم/الجهة/النوع) تُعطي الترتيب المطلوب نفسه،
    /// والعنوان يُستخلص من اسم الملف ويُحسَّن لاحقاً عند الحاجة.
    ///
    /// **الفشل جزئي:** كل ملف يُعالَج على حدة ويحمل نتيجته، فملفٌ واحد تالف لا يُبطل الدفعة.
    /// </remarks>
    [HttpPost("bulk")]
    [Authorize(Roles = "SuperAdmin,President,Manager")]
    [RequestSizeLimit(600 * 1024 * 1024)]
    public async Task<ActionResult<BulkImportResult>> BulkImport(
        [FromForm] IFormFileCollection files,
        [FromForm] int? year, [FromForm] int? month,
        [FromForm] int? departmentId, [FromForm] int? fromEntityId,
        [FromForm] int? documentTypeId, [FromForm] string? keywords,
        CancellationToken ct)
    {
        if (files is null || files.Count == 0)
            throw new ValidationException("اختر ملفاً واحداً على الأقل.");

        // سقفٌ للدفعة: يحمي الذاكرة ومهلة الطلب. الأرشيف يُرفع على دفعات شهرية أصلاً.
        const int maxPerBatch = 50;
        if (files.Count > maxPerBatch)
            throw new ValidationException($"الحد الأقصى {maxPerBatch} ملفاً في الدفعة الواحدة — قسّمها على دفعات (شهراً شهراً مثلاً).");

        var rows = new List<BulkImportRow>();

        foreach (var file in files)
        {
            var parsed = ArchiveFileNameParser.Parse(file.FileName);

            // ⚠️ يُتتبَّع ليُنظَّف عند فشل الإرفاق: أول نسخة كانت تُنشئ المستند ثم تُرفق،
            //    فإذا رُفض الملف (امتداد ممنوع مثلاً) بقي **سجلّ أرشيف يتيم بلا ملف** —
            //    ظهر فعلاً في الاختبار (ArchiveId=5 بصفر مرفقات). ولا نُكرّر قواعد التحقّق
            //    هنا لأن مصدرها الوحيد `AttachmentService`، ونسخةٌ ثانية منها تتخلّف عنه.
            int? createdId = null;
            try
            {
                if (file.Length == 0) throw new ValidationException("الملف فارغ.");

                // العنوان: من اسم الملف، وإلا اسم الملف كما هو ليبقى للمالك خيطٌ يتعرّف به
                // عليه في قائمة «تحتاج عنواناً» — **ولا نخترع عنواناً وهمياً**.
                var title = parsed.Title ?? Path.GetFileNameWithoutExtension(file.FileName).Trim();
                if (string.IsNullOrWhiteSpace(title)) title = "بلا عنوان";

                // التاريخ: من اسم الملف إن وُجد، وإلا من بيانات الدفعة (سنة/شهر).
                var date = parsed.Date
                           ?? (year is not null ? new DateTime(year.Value, month ?? 1, 1) : (DateTime?)null);

                var doc = await svc.CreateAsync(new CreateArchiveInput(
                    null, title, null, date,
                    fromEntityId, null, documentTypeId,
                    null, null, null, keywords, null, null, departmentId), ct);
                createdId = doc.ArchiveId;

                using var ms = new MemoryStream();
                await file.CopyToAsync(ms, ct);
                await attachments.AddAsync(OwnerType.Archive, doc.ArchiveId, file.FileName, ms.ToArray(), ct);

                rows.Add(new BulkImportRow(file.FileName, true, doc.ArchiveId, doc.ArchiveNumber, title, parsed.NeedsTitle, null));
            }
            catch (Exception ex)
            {
                // نحذف المستند إن كان أُنشئ قبل فشل الإرفاق — لا نترك سجلاً بلا ملف.
                if (createdId is not null)
                {
                    try { await svc.SoftDeleteAsync(createdId.Value, ct); }
                    catch { /* أفضل جهد: فشل التنظيف لا يجوز أن يُخفي سبب الفشل الأصلي */ }
                }
                // Hint: نلتقط الاستثناء لكل ملف — الرسالة العربية من استثناءات المجال تصل
                //       للمالك كما هي، وغيرها يُختصر حتى لا نكشف تفاصيل داخلية.
                var msg = ex is ValidationException or NotFoundException or ConflictException
                    ? ex.Message
                    : "تعذّر استيراد هذا الملف.";
                rows.Add(new BulkImportRow(file.FileName, false, null, null, null, parsed.NeedsTitle, msg));
            }
        }

        return new BulkImportResult(
            rows.Count,
            rows.Count(r => r.Ok),
            rows.Count(r => !r.Ok),
            rows.Count(r => r.Ok && r.NeedsTitle),
            rows);
    }

    [HttpGet]
    public async Task<ActionResult<List<ArchiveListItem>>> List(
        [FromQuery] string? search, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? documentTypeId, [FromQuery] int? entityId, CancellationToken ct = default)
    {
        var docs = await svc.SearchAsync(new ArchiveSearchInput(search, from, to, documentTypeId, entityId), ct);
        return docs.Select(a => new ArchiveListItem(
            a.ArchiveId, a.ArchiveNumber, a.Title, a.BookNumber, a.BookDate,
            a.DocumentTypeId, a.AmountInIqd, a.CreatedAt)).ToList();
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ArchiveDetail>> Get(int id, CancellationToken ct)
        => await DetailAsync(await svc.GetAsync(id, ct), ct);

    [HttpPost]
    public async Task<ActionResult<ArchiveDetail>> Create(ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.CreateAsync(new CreateArchiveInput(
            req.CompanyId, req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml,
            req.DepartmentId), ct);
        return await DetailAsync(doc, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ArchiveDetail>> Update(int id, ArchiveRequest req, CancellationToken ct)
    {
        var doc = await svc.UpdateAsync(id, new UpdateArchiveInput(
            req.Title, req.BookNumber, req.BookDate,
            req.FromEntityId, req.ToEntityId, req.DocumentTypeId,
            req.Amount, req.Currency, req.ExchangeRate, req.Keywords, req.Notes, req.BodyHtml,
            req.DepartmentId), ct);
        return await DetailAsync(doc, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await svc.SoftDeleteAsync(id, ct);
        return NoContent();
    }

    // ----- المرفقات -----
    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> ListAttachments(int id, CancellationToken ct)
    {
        var list = await attachments.ListAsync(OwnerType.Archive, id, ct);
        return list.Select(a => new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt)).ToList();
    }

    [HttpPost("{id:int}/attachments")]
    public async Task<ActionResult<AttachmentResponse>> AddAttachment(int id, IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length == 0) throw new ValidationException("الملف فارغ.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var a = await attachments.AddAsync(OwnerType.Archive, id, file.FileName, ms.ToArray(), ct);
        return new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt);
    }

    /// <summary>يحوّل المستند إلى DTO ويُحلّ اسمَي نوع المستند والقسم من معرّفيهما.</summary>
    private async Task<ArchiveDetail> DetailAsync(ArchiveDoc a, CancellationToken ct)
    {
        var typeName = a.DocumentTypeId is null
            ? null
            : await db.DocumentTypes.Where(t => t.DocumentTypeId == a.DocumentTypeId)
                .Select(t => t.Name).FirstOrDefaultAsync(ct);

        var deptName = a.DepartmentId is null
            ? null
            : await db.Departments.Where(d => d.DepartmentId == a.DepartmentId)
                .Select(d => d.Name).FirstOrDefaultAsync(ct);

        return new ArchiveDetail(
            a.ArchiveId, a.CompanyId, a.ArchiveNumber, a.Title, a.BookNumber, a.BookDate,
            a.FromEntityId, a.ToEntityId, a.DocumentTypeId,
            a.Amount, a.Currency, a.ExchangeRate, a.AmountInIqd, a.Keywords, a.Notes, a.BodyHtml, a.CreatedAt,
            typeName, a.DepartmentId, deptName);
    }
}
