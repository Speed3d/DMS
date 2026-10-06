using System.Text.RegularExpressions;

namespace Dms.Domain;

/// <summary>
/// ملفاتُ نسخٍ على القرص **لا يعرفها النظام** (ADR-059) — قواعد نقيّة يناديها الخادم وتُختبر وحدها.
/// </summary>
/// <remarks>
/// 🔑 **لماذا توجد ملفاتٌ بلا سجلّ؟** (أ) **الاستعادة تستبدل القاعدة كلَّها** فتختفي سجلّات كل نسخةٍ أُخذت بعد تاريخ النسخة
/// المُستعادة — **وقد تكون نسخاً حقيقية** · (ب) خادمٌ آخر (اختبار) يكتب في المجلد نفسه ويسجّل في قاعدته هو. والتقليم
/// (`PruneAsync`) يحذف ما يعرفه وحده، فتتراكم بلا حدّ (وُجد منها 108 بـ19 غيغابايت — 2026-10-06).
/// ⟵ **تُعرض ولا تُحذف تلقائياً**: الإعادة إلى القائمة أوّلاً (قد تكون نسخةً حقيقية)، والحذف بقرار السوبر أدمن.
/// </remarks>
public static class BackupFiles
{
    /// <summary>أسماء ما يكتبه النظام وحده: <c>backup-yyyyMMdd-HHmmss.zip</c> (نسخة) و<c>uploaded-…</c> (مرفوعة من جهاز).</summary>
    private static readonly Regex Name = new(@"^(backup|uploaded)-\d{8}-\d{6}\.zip$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>
    /// 🔐 **الاسم يدخل في مسار ملف** — فلا يُقبل إلا نمط النظام نفسه: لا مجلدات ولا `..` ولا امتدادٌ آخر.
    /// </summary>
    public static bool IsBackupFileName(string? name) => name is not null && Name.IsMatch(name);

    /// <summary>
    /// ملفٌّ أحدث من هذا قد يكون **نسخةً تُكتب الآن** (يُنشأ الملف قبل سجلّه) — فلا يُعرض ولا يُمسّ.
    /// </summary>
    public static readonly TimeSpan MinAge = TimeSpan.FromMinutes(15);

    /// <summary>هل الملف «بلا سجلّ» فعلاً؟ — اسمٌ بنمط النظام · غيرُ مسجَّل · وأقدم من <see cref="MinAge"/>.</summary>
    public static bool IsUnrecorded(string name, DateTime modifiedUtc, ISet<string> recorded, DateTime nowUtc) =>
        IsBackupFileName(name) && !recorded.Contains(name) && nowUtc - modifiedUtc >= MinAge;
}
