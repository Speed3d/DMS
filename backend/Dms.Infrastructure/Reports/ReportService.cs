using System.Globalization;
using Dms.Documents.Reports;
using Dms.Domain;
using Dms.Infrastructure.Archive;
using Dms.Infrastructure.Outgoing;
using Dms.Infrastructure.Persistence;
using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Dms.Infrastructure.Reports;

public sealed record FinancialReportRow(
    string Source, string Number, DateTime Date, string EntityName,
    decimal? Amount, Currency? Currency, decimal? AmountInIqd);

public sealed record FinancialReportResult(
    DateTime? From, DateTime? To, List<FinancialReportRow> Rows, decimal TotalIqd, int Count);

/// <param name="Action">الفعل الخام كما في السجلّ (Create/Approve…) — للفلترة والمطابقة الآلية.</param>
/// <param name="ActionLabel">عربيّته — للعرض والطباعة.</param>
public sealed record ActivityRow(
    DateTime Timestamp, int? UserId, string UserName,
    string Action, string ActionLabel,
    string EntityType, string EntityLabel,
    string? EntityId, string? Details);

/// <param name="Rows">السطور بعد الفلترة، مقصوصةً عند <c>take</c>.</param>
/// <param name="TotalCount">العدد الكلّي **قبل القصّ** — ليعرف القارئ أنه يرى جزءاً.</param>
/// <param name="ByAction">توزيع العمليات على الأفعال (عربيّةً) — أكثرها أولاً.</param>
/// <param name="ByUser">توزيع العمليات على المستخدمين — أكثرهم أولاً.</param>
public sealed record ActivityResult(
    DateTime? From, DateTime? To, List<ActivityRow> Rows, int TotalCount,
    List<CountRow> ByAction, List<CountRow> ByUser);

public sealed record CountRow(string Label, int Count);

/// <summary>خيارات تقرير النشاط — تُمرَّر ككائنٍ واحد لأنها ستّة وستزيد.</summary>
public sealed record ActivityFilter(
    DateTime? From = null, DateTime? To = null, int? UserId = null,
    string? Action = null, string? EntityType = null, int Take = 500);

public sealed record OutgoingDetailRow(
    int OutgoingId, string Number, DateTime Date, string Subject, string EntityName,
    BookStatus Status, string StatusLabel, string CreatedBy, string? ApprovedBy,
    DateTime? ApprovedAt, decimal? Amount, Currency? Currency, decimal? AmountInIqd);

/// <param name="Drafts">عدد المسودّات ضمن النتيجة — تُعدّ ولا تُجمع مبالغُها (درس ADR-029).</param>
public sealed record OutgoingDetailResult(
    List<OutgoingDetailRow> Rows, int Count, int Drafts, int Approved, decimal ApprovedTotalIqd);

/// <param name="IsIncoming">صفٌّ من الوارد المؤرشف (لا مبلغ له) أم أضبارة ورقية.</param>
public sealed record ArchiveDetailRow(
    bool IsIncoming, string SourceLabel, string Number, DateTime Date, string Title,
    string? EntityName, string? DocumentType, string Departments, decimal? AmountInIqd);

public sealed record ArchiveDetailResult(
    List<ArchiveDetailRow> Rows, int Count, int IncomingCount, int PaperCount, decimal TotalIqd);

/// <param name="Status">حالة الصادر المطلوبة، أو فارغ = الكل.</param>
public sealed record OutgoingDetailFilter(
    DateTime? From = null, DateTime? To = null, int? EntityId = null, BookStatus? Status = null);

public interface IReportService
{
    Task<FinancialReportResult> FinancialAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);
    Task<byte[]> FinancialPdfAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);
    Task<byte[]> FinancialExcelAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default);

    Task<ActivityResult> ActivityAsync(ActivityFilter filter, CancellationToken ct = default);
    Task<byte[]> ActivityPdfAsync(ActivityFilter filter, CancellationToken ct = default);
    Task<byte[]> ActivityExcelAsync(ActivityFilter filter, CancellationToken ct = default);

    Task<OutgoingDetailResult> OutgoingDetailAsync(OutgoingDetailFilter filter, CancellationToken ct = default);
    Task<byte[]> OutgoingDetailPdfAsync(OutgoingDetailFilter filter, CancellationToken ct = default);
    Task<byte[]> OutgoingDetailExcelAsync(OutgoingDetailFilter filter, CancellationToken ct = default);

    Task<ArchiveDetailResult> ArchiveDetailAsync(ArchiveLensFilter filter, CancellationToken ct = default);
    Task<byte[]> ArchiveDetailPdfAsync(ArchiveLensFilter filter, CancellationToken ct = default);
    Task<byte[]> ArchiveDetailExcelAsync(ArchiveLensFilter filter, CancellationToken ct = default);
}

public sealed class ReportService(
    AppDbContext db, ICurrentUser current,
    IOutgoingService outgoing, IArchiveService archive) : IReportService
{
    // 🔴 **لا قاعدةَ رؤيةٍ مكتوبة هنا (ADR-030).** كان هذا الملفّ يحمل نسختَه الخاصة
    //    («المُنشئ وحده») للصادر والأرشيف معاً، فتباعدت عن الشاشتين:
    //      · الصادر — صار يُرى بالقسم، والتقرير بقي مقصوراً على المُنشئ.
    //      · الأرشيف — الشاشة تُظهر «عمله + قسمه»، والتقرير يُظهر «عمله» وحده، فيقرأ
    //        موظفُ القسم أضبارةً على الشاشة **ولا يجدها في تقريره**.
    //    ⇒ التقرير ينادي الآن `Query()` كلٍّ من الخدمتين، فما يُجمَع هو **عين ما يُرى**.

    public async Task<FinancialReportResult> FinancialAsync(
        DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var rows = new List<FinancialReportRow>();
        var includeOutgoing = source is "All" or "Outgoing";
        var includeArchive = source is "All" or "Archive";

        if (includeOutgoing)
        {
            var oq = outgoing.Query().Where(b => b.Status == BookStatus.Final && b.AmountInIqd != null);
            if (from is not null) oq = oq.Where(b => b.Date >= from);
            if (to is not null) oq = oq.Where(b => b.Date <= to);
            if (entityId is not null) oq = oq.Where(b => b.EntityId == entityId);

            rows.AddRange(await oq
                .Select(b => new FinancialReportRow("صادر", b.Number!, b.Date, b.Entity!.Name,
                    b.Amount, b.Currency, b.AmountInIqd))
                .ToListAsync(ct));
        }

        if (includeArchive)
        {
            var aq = archive.Query().Where(a => a.AmountInIqd != null);
            if (from is not null) aq = aq.Where(a => (a.BookDate ?? a.CreatedAt) >= from);
            if (to is not null) aq = aq.Where(a => (a.BookDate ?? a.CreatedAt) <= to);
            if (entityId is not null) aq = aq.Where(a => a.FromEntityId == entityId || a.ToEntityId == entityId);

            var aList = await aq.Select(a => new
            {
                a.ArchiveNumber, Date = a.BookDate ?? a.CreatedAt,
                a.FromEntityId, a.ToEntityId, a.Amount, a.Currency, a.AmountInIqd,
            }).ToListAsync(ct);

            var ids = aList.SelectMany(a => new[] { a.ToEntityId, a.FromEntityId })
                .Where(x => x is not null).Select(x => x!.Value).Distinct().ToList();
            var names = await db.Entities.Where(e => ids.Contains(e.EntityId))
                .ToDictionaryAsync(e => e.EntityId, e => e.Name, ct);

            rows.AddRange(aList.Select(a =>
            {
                var eid = a.ToEntityId ?? a.FromEntityId;
                var name = eid is not null && names.TryGetValue(eid.Value, out var n) ? n : "—";
                return new FinancialReportRow("أرشيف", a.ArchiveNumber, a.Date, name, a.Amount, a.Currency, a.AmountInIqd);
            }));
        }

        // Hint: أُلغي مصدر «وارد» من التقرير المالي بقرار المالك (2026-07-25) لأن الكتاب الوارد
        //       يُسجَّل للمتابعة لا للمحاسبة، فمبالغه كانت تضخّم الإجمالي بلا معنى مالي.
        //       أعمدة المبالغ باقية في جدول IncomingBooks (لم تُحذف بـmigration) فالقرار قابل
        //       للتراجع ببساطة، والبيانات القديمة سليمة.

        rows = rows.OrderBy(r => r.Date).ToList();
        var total = rows.Sum(r => r.AmountInIqd ?? 0m);
        return new FinancialReportResult(from, to, rows, total, rows.Count);
    }

    public async Task<byte[]> FinancialPdfAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var result = await FinancialAsync(from, to, entityId, source, ct);
        var company = await CompanyNameAsync(ct);
        var model = new FinancialReportModel(
            company, PeriodLabel(from, to),
            result.Rows.Select(r => new FinancialReportLine(
                r.Source, r.Number, r.Date.ToString("yyyy-MM-dd"), r.EntityName,
                Money(r.Amount, r.Currency), Money(r.AmountInIqd, Currency.IQD))).ToList(),
            Money(result.TotalIqd, Currency.IQD), result.Count);
        return FinancialReportPdf.Generate(model);
    }

    public async Task<byte[]> FinancialExcelAsync(DateTime? from, DateTime? to, int? entityId, string source, CancellationToken ct = default)
    {
        var result = await FinancialAsync(from, to, entityId, source, ct);
        var headers = new[] { "المصدر", "الرقم", "التاريخ", "الجهة", "المبلغ", "العملة", "بالدينار" };
        var rows = result.Rows.Select(r => (IReadOnlyList<string>)new[]
        {
            r.Source, r.Number, r.Date.ToString("yyyy-MM-dd"), r.EntityName,
            r.Amount?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
            CurrencyLabel(r.Currency),
            r.AmountInIqd?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
        }).ToList();
        rows.Add(new[] { "الإجمالي", "", "", "", "", "", result.TotalIqd.ToString("0.##", CultureInfo.InvariantCulture) });
        return ExcelExporter.Create("التقرير المالي", headers, rows);
    }

    // ══════════════════ تقرير النشاط (من سجل التدقيق) ══════════════════
    //
    // 🔐 **حدّ الصلاحية ليس هنا بل على الـController** — ونُصّ عليه لئلا يُنسى عند إضافة نقطة:
    //    سجلّ التدقيق يكشف مواضيع الصادر وأرقامه والأرشيف والمستخدمين، أي **بيانات كل
    //    الأقسام**. ولذلك `AuditController` مقصورٌ على «رئيس الشركة فأعلى» منذ تدقيق 2026-07-14
    //    (البند D4). وفتحُ البيانات نفسها من باب التقارير بحارس القسم وحده **التفافٌ على ذلك
    //    القرار**، لا ميزةٌ جديدة — نظير «الحدّ المزدوج» الذي منع قراءة الوارد من باب الأرشيف
    //    (ADR-021).
    //
    // ⚠️ **والعزل بين الشركات نافذٌ فوق ذلك كله**: `AuditLogs` لها فلترٌ عامّ على `CompanyId`
    //    في `AppDbContext` (يسمح بـ`null` لأحداث ما قبل اختيار الشركة كالدخول).

    public async Task<ActivityResult> ActivityAsync(ActivityFilter filter, CancellationToken ct = default)
    {
        var q = FilteredLogs(filter);

        // العدّ الكلّي **قبل القصّ**: «رأيتَ 500 من 12,340» معلومةٌ، و«رأيتَ 500» تضليل.
        var total = await q.CountAsync(ct);

        var take = Math.Clamp(filter.Take, 1, 5000);
        var logs = await q.OrderByDescending(a => a.Timestamp).Take(take)
            .Select(a => new { a.Timestamp, a.UserId, a.Action, a.EntityType, a.EntityId, a.Details })
            .ToListAsync(ct);

        // التجميع على **كامل النطاق المفلتَر** لا على المقصوص — وإلا صار الملخّص يصف
        // الصفحةَ الأولى ويُقرأ على أنه يصف الفترة.
        var byAction = await q.GroupBy(a => a.Action)
            .Select(g => new { g.Key, Count = g.Count() })
            .OrderByDescending(x => x.Count).Take(20).ToListAsync(ct);

        // 🔴 **التجميع بالمستخدم يُجمع من مصدرين لا واحد** — لأن أحداث المصادقة تُكتب
        //    بـ`UserId = null` والفاعل فيها في `EntityId` (انظر `AuditLabels.ActorUserId`).
        //    وبمصدرٍ واحد كان «الأنشط» **يتجاهل كل عمليات الدخول** فيصف نشاطاً ناقصاً.
        //    والتجميعان يقعان في SQL لا في الذاكرة — فالسجلّ ينمو بلا سقف.
        var byUserRaw = await q.Where(a => a.UserId != null)
            .GroupBy(a => a.UserId!.Value)
            .Select(g => new { UserId = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        var byActorRaw = await q
            .Where(a => a.UserId == null && a.EntityType == AuditLabels.UserEntityType && a.EntityId != null)
            .GroupBy(a => a.EntityId!)
            .Select(g => new { EntityId = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        var perUser = new Dictionary<int, int>();
        foreach (var u in byUserRaw)
            perUser[u.UserId] = perUser.GetValueOrDefault(u.UserId) + u.Count;
        foreach (var a in byActorRaw)
            if (int.TryParse(a.EntityId, out var uid))
                perUser[uid] = perUser.GetValueOrDefault(uid) + a.Count;

        var topUsers = perUser.OrderByDescending(kv => kv.Value).Take(20).ToList();

        // أسماء المستخدمين: للسطور والتجميع معاً، بطلبٍ واحد.
        // ⚠️ `IgnoreQueryFilters` مقصود: مستخدمٌ نُقل أو عُطّل يبقى اسمه مقروءاً في سجلٍّ
        //    تاريخيّ — وإلا صار «—» ففُقدت **مَن** وهي نصف المعلومة الأمنية.
        var ids = logs.Select(l => AuditLabels.ActorUserId(l.UserId, l.EntityType, l.EntityId))
            .Where(x => x is not null).Select(x => x!.Value)
            .Concat(topUsers.Select(u => u.Key)).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => ids.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.FullName, ct);

        string NameOf(int? id) => id is not null && names.TryGetValue(id.Value, out var n) ? n : "—";

        var rows = logs.Select(l =>
        {
            var actor = AuditLabels.ActorUserId(l.UserId, l.EntityType, l.EntityId);
            return new ActivityRow(
                l.Timestamp, actor, NameOf(actor),
                l.Action, AuditLabels.Action(l.Action),
                l.EntityType, AuditLabels.Entity(l.EntityType),
                l.EntityId, l.Details);
        }).ToList();

        return new ActivityResult(
            filter.From, filter.To, rows, total,
            byAction.Select(a => new CountRow(AuditLabels.Action(a.Key), a.Count)).ToList(),
            topUsers.Select(u => new CountRow(NameOf(u.Key), u.Value)).ToList());
    }

    public async Task<byte[]> ActivityPdfAsync(ActivityFilter filter, CancellationToken ct = default)
    {
        var r = await ActivityAsync(filter, ct);
        var model = new TableReportModel(
            "تقرير النشاط", await CompanyNameAsync(ct), PeriodLabel(filter.From, filter.To),
            [
                new TableReportColumn("التاريخ والوقت", 2.4f),
                new TableReportColumn("المستخدم", 2.2f),
                new TableReportColumn("العملية", 2.6f),
                new TableReportColumn("النوع", 2.2f),
                new TableReportColumn("المعرّف", 1.2f),
                new TableReportColumn("التفاصيل", 4f),
            ],
            r.Rows.Select(x => (IReadOnlyList<string>)new[]
            {
                LocalStamp(x.Timestamp), x.UserName, x.ActionLabel, x.EntityLabel,
                x.EntityId ?? "—", x.Details ?? "—",
            }).ToList(),
            SummaryLines(r));
        return TableReportPdf.Generate(model);
    }

    public async Task<byte[]> ActivityExcelAsync(ActivityFilter filter, CancellationToken ct = default)
    {
        var r = await ActivityAsync(filter, ct);
        var headers = new[] { "التاريخ والوقت", "المستخدم", "العملية", "النوع", "المعرّف", "التفاصيل" };
        var rows = r.Rows.Select(x => (IReadOnlyList<string>)new[]
        {
            LocalStamp(x.Timestamp), x.UserName, x.ActionLabel, x.EntityLabel,
            x.EntityId ?? "", x.Details ?? "",
        }).ToList();
        return ExcelExporter.Create("تقرير النشاط", headers, rows);
    }

    // ══════════════════ التقرير التفصيلي للصادر ══════════════════
    //
    // 🔴 **بلا قاعدة رؤيةٍ خاصة**: ينادي `outgoing.Query()` كالتقرير المالي وكالشاشة —
    //    فما يُطبَع هو **عين ما يُرى** (ADR-030). أي شرطِ رؤيةٍ يُكتب هنا يتباعد عند أول تغيير.
    //
    // 🔴 **والمسودّات تُعدّ ولا تُجمع**: خلطُ المسودّة بالمعتمد في مجموعٍ واحد هو بعينه عطل
    //    ADR-029 («إجمالي السنة» كان يجمع المسودّات مع المُسدَّد). فالمجموع هنا **للمعتمد
    //    وحده**، وعدد المسودّات يُعرض **بجانبه رقماً مستقلاً**.

    public async Task<OutgoingDetailResult> OutgoingDetailAsync(
        OutgoingDetailFilter f, CancellationToken ct = default)
    {
        var q = outgoing.Query();
        if (f.From is not null) q = q.Where(b => b.Date >= f.From.Value.Date);
        if (f.To is not null) q = q.Where(b => b.Date < f.To.Value.Date.AddDays(1));
        if (f.EntityId is not null) q = q.Where(b => b.EntityId == f.EntityId);
        if (f.Status is not null) q = q.Where(b => b.Status == f.Status);

        var books = await q.OrderByDescending(b => b.Date)
            .Select(b => new
            {
                b.OutgoingId, b.Number, b.Date, b.Subject, EntityName = b.Entity!.Name,
                b.Status, b.CreatedByUserId, b.ApprovedByUserId, b.ApprovedAt,
                b.Amount, b.Currency, b.AmountInIqd,
            })
            .ToListAsync(ct);

        var ids = books.SelectMany(b => new[] { (int?)b.CreatedByUserId, b.ApprovedByUserId })
            .Where(x => x is not null).Select(x => x!.Value).Distinct().ToList();
        var names = await db.Users.IgnoreQueryFilters()
            .Where(u => ids.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.FullName, ct);
        string NameOf(int? id) => id is not null && names.TryGetValue(id.Value, out var n) ? n : "—";

        var rows = books.Select(b => new OutgoingDetailRow(
            b.OutgoingId, b.Number ?? "— مسودّة —", b.Date, b.Subject, b.EntityName,
            b.Status, StatusLabel(b.Status), NameOf(b.CreatedByUserId),
            b.ApprovedByUserId is null ? null : NameOf(b.ApprovedByUserId),
            b.ApprovedAt, b.Amount, b.Currency, b.AmountInIqd)).ToList();

        var approved = rows.Where(r => r.Status == BookStatus.Final).ToList();
        return new OutgoingDetailResult(
            rows, rows.Count, rows.Count - approved.Count, approved.Count,
            approved.Sum(r => r.AmountInIqd ?? 0m));
    }

    public async Task<byte[]> OutgoingDetailPdfAsync(OutgoingDetailFilter f, CancellationToken ct = default)
    {
        var r = await OutgoingDetailAsync(f, ct);
        var model = new TableReportModel(
            "تقرير الصادر التفصيلي", await CompanyNameAsync(ct), PeriodLabel(f.From, f.To),
            [
                new TableReportColumn("الرقم", 2.2f),
                new TableReportColumn("التاريخ", 1.6f),
                new TableReportColumn("الموضوع", 4.5f),
                new TableReportColumn("الجهة", 2.6f),
                new TableReportColumn("الحالة", 1.4f),
                new TableReportColumn("أنشأه", 2f),
                new TableReportColumn("اعتمده", 2f),
                new TableReportColumn("المبلغ بالدينار", 2f),
            ],
            r.Rows.Select(x => (IReadOnlyList<string>)new[]
            {
                x.Number, x.Date.ToString("yyyy-MM-dd"), x.Subject, x.EntityName,
                x.StatusLabel, x.CreatedBy, x.ApprovedBy ?? "—",
                x.AmountInIqd?.ToString("#,0.##", CultureInfo.InvariantCulture) ?? "—",
            }).ToList(),
            [
                $"عدد الكتب: {r.Count}",
                $"معتمدة: {r.Approved} · مسودّات: {r.Drafts}",
                $"إجمالي المعتمد: {r.ApprovedTotalIqd.ToString("#,0.##", CultureInfo.InvariantCulture)} د.ع",
            ]);
        return TableReportPdf.Generate(model);
    }

    public async Task<byte[]> OutgoingDetailExcelAsync(OutgoingDetailFilter f, CancellationToken ct = default)
    {
        var r = await OutgoingDetailAsync(f, ct);
        var headers = new[] { "الرقم", "التاريخ", "الموضوع", "الجهة", "الحالة", "أنشأه", "اعتمده", "المبلغ", "العملة", "بالدينار" };
        var rows = r.Rows.Select(x => (IReadOnlyList<string>)new[]
        {
            x.Number, x.Date.ToString("yyyy-MM-dd"), x.Subject, x.EntityName, x.StatusLabel,
            x.CreatedBy, x.ApprovedBy ?? "",
            x.Amount?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
            CurrencyLabel(x.Currency),
            x.AmountInIqd?.ToString("0.##", CultureInfo.InvariantCulture) ?? "",
        }).ToList();

        // الإجمالي **للمعتمد وحده** ومُعلَنٌ كذلك في نصّه — لا مجموعَ يخلط الحالتين (ADR-029).
        rows.Add(["إجمالي المعتمد", "", "", "", "", "", "", "", "", r.ApprovedTotalIqd.ToString("0.##", CultureInfo.InvariantCulture)]);
        return ExcelExporter.Create("الصادر التفصيلي", headers, rows);
    }

    // ══════════════════ التقرير التفصيلي للأرشيف ══════════════════
    //
    // 🔴 **ينادي `archive.LensAsync` نفسها التي تغذّي الشاشة** — لا نسخةً منها. ولهذا نُقلت
    //    العدسة من الـcontroller إلى الخدمة: تقريرٌ يجمع غيرَ ما تعرضه الشاشة هو العطل الذي
    //    أُغلق في ADR-030، وإعادتُه هنا كانت ستكون تكراراً للخطأ نفسه بعد يومٍ واحد.

    public async Task<ArchiveDetailResult> ArchiveDetailAsync(ArchiveLensFilter f, CancellationToken ct = default)
    {
        var lens = await archive.LensAsync(f, ct);
        var rows = lens.Select(r => new ArchiveDetailRow(
            r.IsIncoming, r.IsIncoming ? "وارد مؤرشف" : "أضبارة ورقية",
            r.Number, r.ArchivedAt, r.Title, r.EntityName, r.DocumentTypeName,
            r.Departments.Count == 0 ? "—" : string.Join(" · ", r.Departments),
            r.AmountInIqd)).ToList();

        return new ArchiveDetailResult(
            rows, rows.Count,
            rows.Count(r => r.IsIncoming), rows.Count(r => !r.IsIncoming),
            rows.Sum(r => r.AmountInIqd ?? 0m));
    }

    public async Task<byte[]> ArchiveDetailPdfAsync(ArchiveLensFilter f, CancellationToken ct = default)
    {
        var r = await ArchiveDetailAsync(f, ct);

        // 🔴 **بلا عمود مبالغ (قرار المالك 2026-08-12)** — المبالغ تُسجَّل في الصادر وحده،
        //    وعمودٌ فارغٌ دائماً يوحي بنقصٍ في الإدخال لا بغياب المعنى. والحقل باقٍ في العقد.
        var model = new TableReportModel(
            "تقرير الأرشيف التفصيلي", await CompanyNameAsync(ct), LensPeriodLabel(f),
            [
                new TableReportColumn("المصدر", 1.8f),
                new TableReportColumn("الرقم", 2.2f),
                new TableReportColumn("التاريخ", 1.6f),
                new TableReportColumn("العنوان", 5.5f),
                new TableReportColumn("الجهة", 2.6f),
                new TableReportColumn("النوع", 2.2f),
                new TableReportColumn("القسم", 2.4f),
            ],
            r.Rows.Select(x => (IReadOnlyList<string>)new[]
            {
                x.SourceLabel, x.Number, x.Date.ToString("yyyy-MM-dd"), x.Title,
                x.EntityName ?? "—", x.DocumentType ?? "—", x.Departments,
            }).ToList(),
            [
                $"عدد السجلات: {r.Count}",
                $"وارد مؤرشف: {r.IncomingCount} · أضابير: {r.PaperCount}",
            ]);
        return TableReportPdf.Generate(model);
    }

    public async Task<byte[]> ArchiveDetailExcelAsync(ArchiveLensFilter f, CancellationToken ct = default)
    {
        var r = await ArchiveDetailAsync(f, ct);
        var headers = new[] { "المصدر", "الرقم", "التاريخ", "العنوان", "الجهة", "النوع", "القسم" };
        var rows = r.Rows.Select(x => (IReadOnlyList<string>)new[]
        {
            x.SourceLabel, x.Number, x.Date.ToString("yyyy-MM-dd"), x.Title,
            x.EntityName ?? "", x.DocumentType ?? "", x.Departments,
        }).ToList();
        return ExcelExporter.Create("الأرشيف التفصيلي", headers, rows);
    }

    private static string StatusLabel(BookStatus s) => s switch
    {
        BookStatus.Draft => "مسودّة",
        BookStatus.Final => "معتمد",
        _ => s.ToString(),
    };

    /// <summary>عنوان فترة عدسة الأرشيف — محورُها السنة والشهر لا مدى تاريخين (ADR-021).</summary>
    private static string LensPeriodLabel(ArchiveLensFilter f)
    {
        if (f.Year is null && f.Month is null) return "كل الفترات";
        if (f.Month is null) return $"سنة {f.Year}";
        return f.Year is null ? $"شهر {f.Month}" : $"{f.Year}-{f.Month:D2}";
    }

    private IQueryable<AuditLog> FilteredLogs(ActivityFilter f)
    {
        var q = db.AuditLogs.AsQueryable();
        if (f.From is not null) q = q.Where(a => a.Timestamp >= f.From.Value.Date);

        // ⚠️ «إلى» يومٌ لا لحظة: `to = 2026-08-11` يجب أن يشمل عمل ذلك اليوم كلَّه،
        //    وإلا اختفى نشاطُ اليوم المُختار كلُّه إلا ما وقع في منتصف ليله بالضبط.
        if (f.To is not null) q = q.Where(a => a.Timestamp < f.To.Value.Date.AddDays(1));

        // 🔴 **الفلترة بالمستخدم تشمل أحداث مصادقته** — نظير `AuditLabels.ActorUserId` تماماً.
        //    بدونها: يُعرض سطر «تسجيل دخول — أحمد»، فإذا فُلتِر بأحمد اختفى. وتناقضٌ كهذا
        //    يُفقد التقريرَ ثقتَه كلَّها لا سطراً واحداً منه.
        if (f.UserId is not null)
        {
            var actorId = f.UserId.Value.ToString();
            q = q.Where(a => a.UserId == f.UserId
                          || (a.UserId == null && a.EntityType == AuditLabels.UserEntityType && a.EntityId == actorId));
        }
        if (!string.IsNullOrWhiteSpace(f.Action)) q = q.Where(a => a.Action == f.Action);
        if (!string.IsNullOrWhiteSpace(f.EntityType)) q = q.Where(a => a.EntityType == f.EntityType);
        return q;
    }

    private static List<string> SummaryLines(ActivityResult r)
    {
        var lines = new List<string> { $"عدد العمليات: {r.TotalCount}" };
        if (r.Rows.Count < r.TotalCount) lines.Add($"المعروض: {r.Rows.Count}");
        if (r.ByAction.Count > 0) lines.Add($"الأكثر: {r.ByAction[0].Label} ({r.ByAction[0].Count})");
        if (r.ByUser.Count > 0) lines.Add($"الأنشط: {r.ByUser[0].Label} ({r.ByUser[0].Count})");
        return lines;
    }

    /// <summary>وقتٌ محليّ للقارئ — السجلّ يُخزَّن UTC، والمالك يقرأ بتوقيت بغداد.</summary>
    /// <remarks>
    /// إزاحةٌ ثابتة ‎+03:00‎ لأن العراق **بلا توقيت صيفي منذ 2015**، وقاعدةُ مناطق زمنية قد
    /// تغيب عن جهازٍ نظيف. (القرار نفسه المتّخذ في خطة وحدة المهام — D1.)
    /// </remarks>
    private static string LocalStamp(DateTime utc)
        => DateTime.SpecifyKind(utc, DateTimeKind.Utc).AddHours(3).ToString("yyyy-MM-dd HH:mm");

    private async Task<string> CompanyNameAsync(CancellationToken ct)
    {
        if (current.ActiveCompanyId is null) return "كل الشركات";
        return await db.Companies.Where(c => c.CompanyId == current.ActiveCompanyId)
            .Select(c => c.Name).FirstOrDefaultAsync(ct) ?? "—";
    }

    private static string PeriodLabel(DateTime? from, DateTime? to)
    {
        if (from is null && to is null) return "كل الفترات";
        var f = from?.ToString("yyyy-MM-dd") ?? "البداية";
        var t = to?.ToString("yyyy-MM-dd") ?? "النهاية";
        return $"من {f} إلى {t}";
    }

    private static string Money(decimal? amount, Currency? currency)
        => amount is null ? "—" : $"{amount.Value.ToString("#,0.##", CultureInfo.InvariantCulture)} {CurrencyLabel(currency)}";

    private static string CurrencyLabel(Currency? c) => c switch
    {
        Currency.USD => "دولار",
        Currency.IQD => "دينار",
        _ => "",
    };
}
