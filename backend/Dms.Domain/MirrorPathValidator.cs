namespace Dms.Domain;

/// <summary>
/// يتحقّق من صلاحية مسار مرآة النسخ الاحتياطي **قبل** الكتابة عليه.
/// </summary>
/// <remarks>
/// 🔐 **لماذا هذا موجود:** المالك يُدخل المسار بنفسه وقت النسخ (`E:\DMS-Backup` مثلاً)،
/// والخادم يكتب فيه بصلاحياته هو لا بصلاحيات المتصفّح. فمسارٌ غير مفحوص يعني كتابةً
/// عشوائية على قرص السيرفر بامتياز الخدمة — ولو بحسن نيّة (خطأٌ مطبعيّ في `C:\Windows`).
///
/// الفحوص الأربعة كلٌّ منها يمنع عطلاً مختلفاً:
/// 1. **مسار مطلق:** النسبيّ يُحلّ إلى مجلد عمل الخدمة — موضع لا يقصده أحد.
/// 2. **ليس مجلد نظام:** خطأ مطبعي في `C:\Windows` قد يُتلف النظام لا النسخة.
/// 3. **ليس داخل مجلد التخزين:** المرآة تنسخ التخزين، فوضعها داخله = **نسخ لا نهائي**
///    يملأ القرص (نسخةٌ داخل نسخةٍ داخل نسخة).
/// 4. **ليس داخل مجلد النسخ:** يخلط المرآة بالنسخ المُدارة فتُقلّمها سياسة الاحتفاظ.
///
/// منطق نقي في المجال ليُختبَر بلا قرص ولا خادم.
/// </remarks>
public static class MirrorPathValidator
{
    /// <summary>مجلدات النظام التي لا يجوز أن تكون المرآة داخلها.</summary>
    private static readonly string[] ForbiddenRoots =
    [
        @"C:\Windows", @"C:\Program Files", @"C:\Program Files (x86)",
        @"C:\ProgramData", @"C:\Users\Default",
    ];

    /// <summary>
    /// يتحقّق ويُعيد المسار المُطبَّع، أو يرمي <see cref="ValidationException"/> برسالة عربية.
    /// </summary>
    /// <param name="path">المسار كما أدخله المالك.</param>
    /// <param name="storageRoot">جذر تخزين الملفات — لا يجوز أن تكون المرآة داخله.</param>
    /// <param name="backupDir">مجلد النسخ المُدارة — لا يجوز أن تكون المرآة داخله.</param>
    public static string Validate(string? path, string storageRoot, string backupDir)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ValidationException("حدّد مسار المرآة (مثل: E:\\DMS-Backup).");

        var full = path.Trim();

        // ⚠️ **`IsPathFullyQualified` لا `IsPathRooted`:** الأخيرة تقبل `\backup` لأنه «مجذّر»،
        //    لكنه يُحلّ إلى **القرص الحالي للخدمة** — موضعٌ لا يقصده أحد ويتغيّر بتغيّر بيئة
        //    التشغيل. المطلوب مسار لا لبس فيه: حرف قرص صريح أو مسار شبكة UNC.
        if (!Path.IsPathFullyQualified(full))
            throw new ValidationException("مسار المرآة يجب أن يكون مطلقاً بحرف القرص (مثل: E:\\DMS-Backup) أو مسار شبكة.");

        try { full = Path.GetFullPath(full); }
        catch { throw new ValidationException("مسار المرآة غير صالح."); }

        foreach (var root in ForbiddenRoots)
        {
            if (IsInside(full, root))
                throw new ValidationException($"لا يجوز أن تكون المرآة داخل مجلد نظام ({root}). اختر قرصاً أو مجلداً مخصّصاً للنسخ.");
        }

        // ⚠️ المرآة داخل مجلد التخزين تنسخ نفسها في كل مرة — نموّ لا نهائي يملأ القرص.
        if (IsInside(full, storageRoot) || IsInside(storageRoot, full))
            throw new ValidationException("لا يجوز أن تكون المرآة داخل مجلد تخزين الملفات أو أن تحتويه — اختر قرصاً منفصلاً.");

        if (IsInside(full, backupDir))
            throw new ValidationException("لا يجوز أن تكون المرآة داخل مجلد النسخ الاحتياطي المُدار — اختر مساراً مستقلاً.");

        return full;
    }

    /// <summary>هل <paramref name="child"/> داخل <paramref name="parent"/> (أو هو نفسه)؟</summary>
    private static bool IsInside(string child, string parent)
    {
        if (string.IsNullOrWhiteSpace(parent)) return false;
        try
        {
            var c = Path.GetFullPath(child).TrimEnd(Path.DirectorySeparatorChar);
            var p = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar);
            // Hint: المقارنة بفاصل في النهاية تمنع أن يُعدّ `C:\Backup2` داخل `C:\Backup`.
            return c.Equals(p, StringComparison.OrdinalIgnoreCase)
                   || c.StartsWith(p + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }
}
