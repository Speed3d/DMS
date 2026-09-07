namespace Dms.Domain;

/// <summary>
/// سُلّم تصعيد المهمة المتأخّرة — **منطقٌ نقيّ** (ADR-039).
/// </summary>
/// <remarks>
/// **ثلاثة مستويات لا أكثر**، وكلٌّ يوسّع دائرة مَن يعلم:
/// <list type="number">
/// <item><b>المسؤول</b> (أو موظفو القسم) — تأخّرٌ يوم فأكثر.</item>
/// <item><b>كل مديري الشركة</b> — ثلاثة أيام فأكثر.</item>
/// <item><b>الرئاسة</b> — سبعة أيام فأكثر.</item>
/// </list>
///
/// 🔴 **وإشعارٌ واحد لكل (مهمة × مستوى) لا تذكيرٌ يوميّ** (قرار مُعلَّل): مهمةٌ متأخرة
/// أسبوعين × خمسة مديرين = **70 إشعاراً بلا معلومةٍ جديدة**. والتصعيد يقول «ساءت الحال»،
/// **والحال لا تسوء كل يوم** — إنما تسوء حين تعبر عتبة.
/// ⚠️ **ولو أُريد التذكير اليوميّ لاحقاً فهو سطران** (`LastEscalatedAt.Date < today`)
/// والعمودان موجودان أصلاً.
/// </remarks>
public static class TaskEscalation
{
    /// <summary>عتبة المستوى الثاني — كل مديري الشركة.</summary>
    public const int ManagersThresholdDays = 3;

    /// <summary>عتبة المستوى الثالث — الرئاسة.</summary>
    public const int PresidencyThresholdDays = 7;

    /// <summary>
    /// مستوى التصعيد لعدد أيام التأخّر — **<c>0</c> يعني لا تصعيد**.
    /// </summary>
    /// <remarks>
    /// ⚠️ **صفرٌ لِما لم يتأخّر بعد**: مهمةٌ موعدها اليوم ليست متأخرة (قاعدة
    /// <see cref="LocalClock"/>)، وتصعيدُها إزعاجٌ يعلّم المستخدم تجاهل التصعيد.
    /// </remarks>
    public static int LevelFor(int daysOverdue) => daysOverdue switch
    {
        >= PresidencyThresholdDays => 3,
        >= ManagersThresholdDays => 2,
        >= 1 => 1,
        _ => 0,
    };

    /// <summary>هل يستحقّ هذا المستوى إشعاراً جديداً؟</summary>
    /// <remarks>
    /// 🔴 **المقارنة بـ«أكبر من» لا «لا يساوي»**: مهمةٌ صُعِّدت إلى 3 ثم مُدّد موعدها قليلاً
    /// فصار تأخّرها يوماً **لا تُصعَّد إلى 1 ثانيةً** — فذلك تراجعٌ يُنتج إشعاراً يقول
    /// «ساءت الحال» وقد تحسّنت. والتصفير يقع عند **تأجيل الموعد وإعادة الإسناد وإعادة
    /// الفتح** صراحةً، لا هنا.
    /// </remarks>
    public static bool ShouldEscalate(int level, int lastEscalatedLevel)
        => level > 0 && level > lastEscalatedLevel;

    /// <summary>عنوانٌ عربيٌّ للإشعار بحسب المستوى.</summary>
    public static string TitleFor(int level) => level switch
    {
        3 => "🔴 مهمة متأخرة — تصعيد للرئاسة",
        2 => "🔴 مهمة متأخرة — تصعيد للإدارة",
        _ => "⚠️ مهمة متأخرة",
    };
}
