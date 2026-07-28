using System.ComponentModel.DataAnnotations;
using Dms.Api.Auth;
using Dms.Api.Dtos;
using Dms.Domain;
using Dms.Infrastructure.Attachments;
using Dms.Infrastructure.Incoming;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Dms.Api.Controllers;

[ApiController]
[Authorize]
[RequireModule(AppModule.Incoming)]
[Route("api/[controller]")]
public sealed class IncomingController(
    IIncomingService incomingService,
    IAttachmentService attachmentService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<IncomingListItem>>> List(
        [FromQuery] string? search, [FromQuery] string? status, [FromQuery] int? entityId,
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int? documentTypeId, [FromQuery] int? departmentId,
        [FromQuery] int? receiveMethod, CancellationToken ct)
    {
        var q = incomingService.Query().Include(b => b.Entity)
            .Include(b => b.Assignments).ThenInclude(a => a.Department).AsQueryable();

        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(b =>
                (b.IncomingNumber != null && b.IncomingNumber.Contains(search)) ||
                (b.ExternalNumber != null && b.ExternalNumber.Contains(search)) ||
                b.Subject.Contains(search) ||
                (b.Keywords != null && b.Keywords.Contains(search)) ||
                (b.Notes != null && b.Notes.Contains(search)) ||
                b.Entity!.Name.Contains(search));

        // ⚠️ المؤرشف يُستبعد من القائمة **الافتراضية** فقط — مكانه صار قسم الأرشيف.
        //    ويظهر فور اختيار الحالة «مؤرشف» صراحةً من الفلتر، فلا يضيع على من يبحث عنه.
        //
        // Hint: الاستبعاد هنا في الـController **عمداً لا في `Query()`**: الأخيرة تحكم رؤية
        //       الكتاب في كل مسار — المرفقات وسجل الحركة وعدسة الأرشيف وفكّ الأرشفة نفسه —
        //       فحجبُ المؤرشف فيها كان سيُعطّل هذه المسارات كلها لا القائمة وحدها.
        if (!string.IsNullOrWhiteSpace(status))
        {
            if (!Enum.TryParse<IncomingStatus>(status, ignoreCase: true, out var parsedStatus))
                throw new Dms.Domain.ValidationException("قيمة الحالة غير صحيحة.");
            q = q.Where(b => b.Status == parsedStatus);
        }
        else
        {
            q = q.Where(b => b.Status != IncomingStatus.Archived);
        }

        if (entityId.HasValue)
            q = q.Where(b => b.EntityId == entityId.Value);

        if (from.HasValue)
            q = q.Where(b => b.ReceivedDate >= from.Value);

        if (to.HasValue)
            q = q.Where(b => b.ReceivedDate <= to.Value);

        if (documentTypeId.HasValue)
            q = q.Where(b => b.DocumentTypeId == documentTypeId.Value);

        // الفلترة بالقسم صارت «أي إسناد لهذا القسم» بعد تعدّد الأقسام (ADR-018).
        if (departmentId.HasValue)
            q = q.Where(b => b.Assignments.Any(a => a.DepartmentId == departmentId.Value));

        if (receiveMethod.HasValue)
        {
            if (!Enum.IsDefined(typeof(ReceiveMethod), receiveMethod.Value))
                throw new Dms.Domain.ValidationException("قيمة طريقة الاستلام غير صحيحة.");
            q = q.Where(b => b.ReceiveMethod == (ReceiveMethod)receiveMethod.Value);
        }

        var list = await q.OrderByDescending(b => b.ReceivedDate)
            .Select(b => new IncomingListItem(
                b.IncomingId, b.IncomingNumber, b.ExternalNumber, b.ReceivedDate,
                b.Subject, b.Entity!.Name, b.Status,
                // الأقسام صارت متعدّدة (ADR-018) — تُعرض مجموعةً في عمود واحد.
                b.Assignments.Select(a => a.Department!.Name).ToList(), b.AmountInIqd))
            .ToListAsync(ct);

        return Ok(list);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<IncomingDetail>> Get(int id, CancellationToken ct)
        => Map(await incomingService.GetDetailAsync(id, ct));

    /// <summary>تحويل بيانات العرض إلى عقد الـ API (Hint: الأسماء تُجهَّز في الخدمة).</summary>
    private static IncomingDetail Map(IncomingDetailData d)
    {
        var b = d.Book;
        return new IncomingDetail(
            b.IncomingId, b.CompanyId, b.IncomingNumber, b.Year, b.SerialNo,
            b.ExternalNumber, b.ExternalDate, b.ReceivedDate, b.ReceivedTime,
            b.EntityId, d.EntityName, b.Subject, b.DocumentTypeId, d.DocumentTypeName,
            b.ReceiveMethod, b.ReceivedByUserId, d.ReceivedByUserName,
            b.Status,
            d.Departments.Select(a => new IncomingAssignmentDto(
                a.DepartmentId, a.Name, a.Note, a.AssignedByUserName, a.AssignedAt)).ToList(),
            b.LastAction, b.Keywords, b.Notes,
            b.Amount, b.Currency, b.ExchangeRate, b.AmountInIqd,
            b.ReplyOutgoingId, d.ReplyOutgoingNumber, b.CreatedAt);
    }

    [HttpPost]
    public async Task<ActionResult<IncomingDetail>> Create(CreateIncomingRequest req, CancellationToken ct)
    {
        var b = await incomingService.CreateAsync(new CreateIncomingInput(
            req.CompanyId, req.ExternalNumber, req.ExternalDate, req.ReceivedDate,
            req.ReceivedTime, req.EntityId, req.Subject, req.DocumentTypeId,
            req.ReceiveMethod, req.Keywords, req.Notes,
            req.Amount, req.Currency, req.ExchangeRate), ct);

        return await Get(b.IncomingId, ct);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<IncomingDetail>> Update(int id, UpdateIncomingRequest req, CancellationToken ct)
    {
        await incomingService.UpdateAsync(id, new UpdateIncomingInput(
            req.ExternalNumber, req.ExternalDate, req.ReceivedDate, req.ReceivedTime,
            req.EntityId, req.Subject, req.DocumentTypeId, req.ReceiveMethod,
            req.Keywords, req.Notes,
            req.Amount, req.Currency, req.ExchangeRate), ct);

        return await Get(id, ct);
    }

    [HttpPost("{id:int}/status")]
    public async Task<ActionResult<IncomingDetail>> ChangeStatus(int id, ChangeStatusRequest req, CancellationToken ct)
    {
        await incomingService.ChangeStatusAsync(id, req.Status, req.Note, ct);
        return await DetailAfterMutationAsync(id, ct);
    }

    [HttpPost("{id:int}/forward")]
    public async Task<ActionResult<IncomingDetail>> Forward(int id, ForwardRequest req, CancellationToken ct)
    {
        var targets = (req.Departments ?? new List<ForwardTargetDto>())
            .Select(t => new ForwardTarget(t.DepartmentId, t.Note)).ToList();
        await incomingService.ForwardAsync(id, targets, req.GeneralNote, ct);
        return await DetailAfterMutationAsync(id, ct);
    }

    /// <summary>
    /// يُعيد تفاصيل الكتاب بعد عملية ناجحة — أو <c>204</c> إن لم يعُد المنفِّذ يراه.
    /// </summary>
    /// <remarks>
    /// ⚠️ كانت هذه العمليات تُنهي بـ<c>return await Get(id, ct)</c>، فإذا **أخرجت العمليةُ
    /// الكتابَ من رؤية المنفِّذ** (إحالة موظف لكتاب قسمه إلى قسم آخر، أو أرشفة) فشلت القراءة
    /// التالية بـ<c>404</c> — **بعد أن كُتب التغيير وحُفظ**. فيرى المستخدم فشلاً لعملية نجحت،
    /// فيُعيدها أو يظنّ بياناته ضاعت. الردّ الصحيح هنا «تمّت، ولم يعُد الكتاب لديك».
    /// </remarks>
    private async Task<ActionResult<IncomingDetail>> DetailAfterMutationAsync(int id, CancellationToken ct)
    {
        try
        {
            return Map(await incomingService.GetDetailAsync(id, ct));
        }
        catch (NotFoundException)
        {
            return NoContent();
        }
    }

    [HttpPost("{id:int}/link/{outgoingId:int}")]
    public async Task<ActionResult<IncomingDetail>> Link(int id, int outgoingId, CancellationToken ct)
    {
        await incomingService.LinkToOutgoingAsync(id, outgoingId, ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}/link")]
    public async Task<ActionResult<IncomingDetail>> Unlink(int id, CancellationToken ct)
    {
        await incomingService.UnlinkFromOutgoingAsync(id, ct);
        return await Get(id, ct);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await incomingService.SoftDeleteAsync(id, ct);
        return NoContent();
    }

    // ----------------- سجل الحركة -----------------
    [HttpGet("{id:int}/movements")]
    public async Task<ActionResult<List<MovementLogItem>>> GetMovements(int id, CancellationToken ct)
    {
        var movements = await incomingService.GetMovementsAsync(id, ct);
        return movements.Select(m => new MovementLogItem(
            m.Log.MovementId, m.Log.Action, m.Log.Description,
            m.Log.FromDepartment, m.Log.ToDepartment,
            m.PerformedByUserName, m.Log.PerformedAt)).ToList();
    }

    // ----------------- المرفقات -----------------
    [HttpGet("{id:int}/attachments")]
    public async Task<ActionResult<List<AttachmentResponse>>> GetAttachments(int id, CancellationToken ct)
    {
        var atts = await attachmentService.ListAsync(OwnerType.Incoming, id, ct);
        return atts.Select(a => new AttachmentResponse(a.AttachmentId, a.FileName, a.FileType, a.FileSize, a.UploadedAt)).ToList();
    }

    [HttpPost("{id:int}/attachments")]
    public async Task<ActionResult<AttachmentResponse>> UploadAttachment(int id, IFormFile file, CancellationToken ct)
    {
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms, ct);
        var att = await attachmentService.AddAsync(OwnerType.Incoming, id, file.FileName, ms.ToArray(), ct);
        return new AttachmentResponse(att.AttachmentId, att.FileName, att.FileType, att.FileSize, att.UploadedAt);
    }

    [HttpDelete("{id:int}/attachments/{attachmentId:int}")]
    public async Task<IActionResult> DeleteAttachment(int id, int attachmentId, CancellationToken ct)
    {
        await attachmentService.DeleteAsync(attachmentId, ct);
        return NoContent();
    }

    /// <summary>
    /// تنزيل مرفق.
    /// Hint: يتطلب مصادقة كبقية النقاط — التحقق من ملكية المرفق وصلاحية القسم يتم داخل
    /// AttachmentService.GetAsync. (أُزيلت سِمة AllowAnonymous ومعامل token الذي كان يُستقبل ويُهمَل.)
    /// </summary>
    [HttpGet("{id:int}/attachments/{attachmentId:int}/download")]
    public async Task<IActionResult> DownloadAttachment(int id, int attachmentId, bool inline, CancellationToken ct)
    {
        var (meta, content) = await attachmentService.GetAsync(attachmentId, ct);

        // ⚠️ `inline=true` للعرض داخل البرنامج: نُرسل **النوع الحقيقي** وبلا اسم ملف.
        // تمرير اسم الملف يجعل ASP.NET يضع `Content-Disposition: attachment`، فتُعامَل
        // الاستجابة كتنزيل — و**مديرو التحميل (مثل IDM) يختطفون الطلب** حتى حين نجلبه
        // بـXHR للعرض، فيصل العميل بلا ردّ ويظنّها انقطاع شبكة. هذا ما كان يُفشل زر العين
        // لكل المستخدمين بلا استثناء بينما يبدو التنزيل ناجحاً.
        if (inline) return File(content, MimeTypes.For(meta.FileName));

        return File(content, "application/octet-stream", meta.FileName);
    }
}
