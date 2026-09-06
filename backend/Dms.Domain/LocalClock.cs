namespace Dms.Domain;

/// <summary>
/// ساعة التوقيت المحلّي — **مصدرٌ واحد** لسؤال «ما اليوم عند المستخدم؟» (ADR-037).
/// </summary>
/// <remarks>
/// 🔴 **السبب الأصلي:** <c>DueDate &lt; DateTime.UtcNow</c> يجعل مهمةً موعدها 15 آب
/// **متأخرةً الساعة 3:00 فجراً من يوم 15 نفسه** — فيرى المستخدم مهمّته حمراء في يومٍ ما زال
/// أمامه كلُّه. وهو صنف العطل الذي كلّف المشروع مرّتين: حسابُ شباط (سقفٌ يحمي من الأعلى لا
/// من الأسفل) وانعكاسُ تاريخ الإيصال.
///
/// ⚠️ **ولماذا إزاحةٌ ثابتة لا <c>TimeZoneInfo</c>؟** العراق ألغى التوقيت الصيفي منذ 2015
/// فالإزاحة +03:00 دائمة، و<c>FindSystemTimeZoneById</c> يعتمد قاعدة مناطق النظام — تختلف
/// بين ويندوز ولينكس وقد تُحدَّث تحت أقدامنا. والقيمة **معزولةٌ هنا** فرفعُها إلى الإعدادات
/// لاحقاً تعديلُ سطر.
///
/// ⚠️ **ولا يُستعمل هذا لختم اللحظات**: <c>CreatedAt</c> و<c>UpdatedAt</c> تبقى
/// <c>DateTime.UtcNow</c> كبقيّة النظام، والعميل يحوّلها بـ<c>parseInstant</c>. هذا الصنف
/// **لسؤال اليوم وحده** — خلطُ الاثنين هو عين عطل ADR-032 معكوساً.
/// </remarks>
public static class LocalClock
{
    /// <summary>إزاحة بغداد عن UTC — ثابتة (لا توقيت صيفي في العراق منذ 2015).</summary>
    public static readonly TimeSpan Offset = TimeSpan.FromHours(3);

    /// <summary>الساعة الحائطية الآن في بغداد — **<c>Unspecified</c> لا <c>Utc</c>**.</summary>
    /// <remarks>
    /// 🔴 **الـ<c>Kind</c> جزءٌ من الصحّة لا تفصيلٌ داخليّ.** <c>DateTime.UtcNow + Offset</c>
    /// يرث <c>Kind = Utc</c>، فيصير الناتج **وقتَ بغداد موسوماً بأنه UTC** — وهو كذبٌ يظهر
    /// على السلك: يُسلسَل بلاحقة <c>Z</c> فيقرؤه العميل لحظةً في غرينتش ويزيحها ثلاث ساعات.
    /// </remarks>
    public static DateTime Now => DateTime.SpecifyKind(DateTime.UtcNow + Offset, DateTimeKind.Unspecified);

    /// <summary>اليوم الحالي في بغداد — عند 00:00 و**بلا منطقةٍ زمنية**.</summary>
    /// <remarks>
    /// 🔴 **تاريخٌ تقويميّ لا لحظة.** وقاعدة المشروع صريحة: **التواريخ التقويمية لا تُمسّ**
    /// (ADR-032 · G18) — لأن تحويل **يومٍ** بالمنطقة الزمنية يُنقصه يوماً عند إزاحةٍ سالبة.
    /// ولذلك <c>Kind = Unspecified</c>: هكذا يُسلسَل **بلا `Z`**، وهكذا تعيده SQL من
    /// <c>datetime2</c> — فلا تختلف صيغةُ الحقل الواحد بين مسار الكتابة ومسار القراءة.
    ///
    /// ⚠️ **وقد وقع هذا فعلاً**: `StartDate` عاد `...T00:00:00Z` بعد الكتابة و`...T00:00:00`
    /// بعد القراءة — كشفه `tasks-e2e` بمقارنة القيمتين.
    /// </remarks>
    public static DateTime Today => Now.Date;

    /// <summary>
    /// يُطبّع أي تاريخٍ **تقويميّ** قبل تخزينه: يومٌ عند 00:00 و<c>Kind = Unspecified</c>.
    /// </summary>
    /// <remarks>
    /// 🔴 **لأن مصدر التاريخ لا يُوثَق به**: العميل قد يرسل <c>2026-09-13T00:00:00Z</c> أو
    /// <c>...+03:00</c> أو بلا لاحقة، فيصل الخادمَ بـ<c>Kind</c> مختلف في كل مرّة — ويعود
    /// إليه بصيغةٍ تخالف ما أُرسل. والتطبيع في **موضعٍ واحد** يمنع ذلك عند حدود النظام.
    ///
    /// ⚠️ **ولا يُستعمل هذا مع اللحظات** (<c>CreatedAt</c> · <c>UpdatedAt</c>): تلك
    /// <c>DateTime.UtcNow</c> بـ<c>Kind = Utc</c> وتُسلسَل بـ<c>Z</c> عن حقّ، والعميل
    /// يحوّلها بـ<c>parseInstant</c>. **تاريخٌ تقويميّ ولحظةٌ، ولا يُخلطان.**
    /// </remarks>
    public static DateTime CalendarDate(DateTime value)
        => DateTime.SpecifyKind(value.Date, DateTimeKind.Unspecified);

    /// <inheritdoc cref="CalendarDate(DateTime)"/>
    public static DateTime? CalendarDate(DateTime? value)
        => value is { } v ? CalendarDate(v) : null;

    /// <summary>عدد الأيام التي تأخّرها موعدٌ ما — **0 يعني ليس متأخراً بعد**.</summary>
    /// <remarks>
    /// موعدُ اليوم يُرجع 0 لا 1: اليوم **لم ينتهِ**. وموعدُ الأمس يُرجع 1.
    /// </remarks>
    public static int DaysOverdue(DateTime dueDate) =>
        Math.Max(0, (Today - dueDate.Date).Days);
}
