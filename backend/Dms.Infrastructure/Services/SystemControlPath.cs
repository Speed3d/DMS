namespace Dms.Infrastructure.Services;

/// <summary>
/// مسار ملفّ حالة النظام (ADR-050) — **قاعدةٌ واحدة** يقرؤها الخادم وأمرُ الطوارئ معاً،
/// وإلا كتب الأمرُ ملفّاً لا يقرؤه الخادم.
/// </summary>
/// <remarks>
/// 🔴 **بجوار مجلد التخزين لا داخل مجلد البرنامج**: التحديث يستبدل ملفات
/// <c>C:\DMS\api</c>، فملفٌّ هناك قد يُمحى **في منتصف التحديث نفسه** — أي في اللحظة الوحيدة
/// التي وُجد الإيقاف لأجلها. أما <c>C:\DMS\data</c> فلا يمسّه النشر (دليل النشر §الهيكل).
/// </remarks>
public static class SystemControlPath
{
    public const string ConfigKey = "SystemControl:StateFile";
    public const string FileName = "system-control.json";

    /// <param name="configured">قيمة <see cref="ConfigKey"/> — والفارغة غيابُ إعداد (قاعدة الإعدادات).</param>
    /// <param name="storageRoot">مجلد التخزين الفعليّ.</param>
    public static string Resolve(string? configured, string storageRoot)
    {
        if (!string.IsNullOrWhiteSpace(configured)) return Path.GetFullPath(configured);

        var root = Path.GetFullPath(storageRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var parent = Path.GetDirectoryName(root) ?? root;
        return Path.Combine(parent, FileName);
    }
}
