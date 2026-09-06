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

    /// <summary>اللحظة الحالية بتوقيت بغداد.</summary>
    public static DateTime Now => DateTime.UtcNow + Offset;

    /// <summary>اليوم الحالي بتوقيت بغداد — عند 00:00.</summary>
    public static DateTime Today => Now.Date;

    /// <summary>عدد الأيام التي تأخّرها موعدٌ ما — **0 يعني ليس متأخراً بعد**.</summary>
    /// <remarks>
    /// موعدُ اليوم يُرجع 0 لا 1: اليوم **لم ينتهِ**. وموعدُ الأمس يُرجع 1.
    /// </remarks>
    public static int DaysOverdue(DateTime dueDate) =>
        Math.Max(0, (Today - dueDate.Date).Days);
}
