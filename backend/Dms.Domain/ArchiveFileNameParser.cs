using System.Text.RegularExpressions;

namespace Dms.Domain;

/// <summary>ما استُخلص من اسم ملف عند الاستيراد بالجملة.</summary>
/// <param name="Title">العنوان المستخلص، أو <c>null</c> إن كان الاسم بلا معنى.</param>
/// <param name="Date">تاريخ الكتاب إن ظهر في الاسم.</param>
public readonly record struct ParsedFileName(string? Title, DateTime? Date)
{
    /// <summary>اسم بلا معنى (IMG_0234 وأمثاله) — يحتاج عنواناً يدوياً لاحقاً.</summary>
    public bool NeedsTitle => Title is null;
}

/// <summary>
/// يستخلص عنوان الكتاب وتاريخه من **اسم الملف** عند استيراد الأرشيف الورقي بالجملة.
/// </summary>
/// <remarks>
/// ⚠️ **لماذا يوجد هذا أصلاً:** أرشيف الشركة الورقي ~80 غيغا ≈ **6,500 كتاب**. إدخالها
/// يدوياً بدقيقتين للكتاب = **٢٧ يوم عمل** — وهو ما لا يكتمل عملياً، فينتهي الأمر بأرشيف
/// نصفه في النظام ونصفه على أجهزة الموظفين، وهو أسوأ من الحالتين.
///
/// الأسماء عند المالك **مختلطة**: منها المفيد (`وزارة الكهرباء - طلب تجهيز - 2023-05-12.pdf`)
/// ومنها الأعمى (`IMG_0234.pdf`). فالمحلّل يأخذ ما يستطيع ويعترف بما لا يستطيع:
/// <see cref="ParsedFileName.NeedsTitle"/> تُعلّم الصفوف التي تحتاج عنواناً، فتُعرض للمالك
/// **قائمةً محدّدة** يُحسّنها على مهل — بدل أن يُخمّن النظام عنواناً كاذباً.
///
/// **المبدأ:** لا نخترع بيانات. اسمٌ أعمى يبقى بلا عنوان معلَّماً، لا يُترجم إلى «مستند 234».
/// </remarks>
public static class ArchiveFileNameParser
{
    /// <summary>أنماط أسماء لا تحمل معنى — نواتج الماسحات والكاميرات.</summary>
    private static readonly Regex[] Meaningless =
    [
        new(@"^img[\s_\-]*\d+$", RegexOptions.IgnoreCase),
        new(@"^scan(ned)?[\s_\-]*\d*$", RegexOptions.IgnoreCase),
        new(@"^doc(ument)?[\s_\-]*\d+$", RegexOptions.IgnoreCase),
        new(@"^image[\s_\-]*\d+$", RegexOptions.IgnoreCase),
        new(@"^\d+$"),
        new(@"^(new|untitled|بلا عنوان)[\s_\-]*\d*$", RegexOptions.IgnoreCase),
    ];

    // yyyy-MM-dd أو yyyy_MM_dd أو yyyy.MM.dd
    private static readonly Regex Ymd = new(@"(?<y>(19|20)\d{2})[-_.](?<m>\d{1,2})[-_.](?<d>\d{1,2})");
    // dd-MM-yyyy وأخواتها
    private static readonly Regex Dmy = new(@"(?<d>\d{1,2})[-_.](?<m>\d{1,2})[-_.](?<y>(19|20)\d{2})");
    // yyyyMMdd ملتصقة
    private static readonly Regex Ymd8 = new(@"(?<!\d)(?<y>(19|20)\d{2})(?<m>0[1-9]|1[0-2])(?<d>0[1-9]|[12]\d|3[01])(?!\d)");

    public static ParsedFileName Parse(string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName)) return new ParsedFileName(null, null);

        var stem = Path.GetFileNameWithoutExtension(fileName).Trim();
        if (stem.Length == 0) return new ParsedFileName(null, null);

        var date = ExtractDate(stem, out var withoutDate);

        // ننظّف الفواصل: الشرطة السفلية والنقاط تُستعمل بدل المسافة في أسماء الملفات.
        // ⚠️ **لا نمسّ الشرطة `-`**: محاولة «توحيدها» بإضافة مسافات حولها تُفسد الأرقام
        //    المركّبة داخل العنوان (`كتاب 2023-13-45` صارت `كتاب 2023 - 13 - 45`).
        //    الأسماء الحقيقية تحمل مسافاتها أصلاً، فالتوحيد كان تجميلاً بثمنٍ حقيقي.
        var title = Regex.Replace(withoutDate, @"[_\.]+", " ");
        title = Regex.Replace(title, @"\s{2,}", " ").Trim(' ', '-', '–', '—');

        if (title.Length == 0 || Meaningless.Any(r => r.IsMatch(title)))
            return new ParsedFileName(null, date);

        return new ParsedFileName(title, date);
    }

    /// <summary>يستخرج أول تاريخ صالح ويزيله من النصّ (ليبقى الباقي عنواناً).</summary>
    private static DateTime? ExtractDate(string stem, out string rest)
    {
        foreach (var rx in new[] { Ymd, Dmy, Ymd8 })
        {
            var m = rx.Match(stem);
            if (!m.Success) continue;

            var y = int.Parse(m.Groups["y"].Value);
            var mo = int.Parse(m.Groups["m"].Value);
            var d = int.Parse(m.Groups["d"].Value);

            // Hint: نتحقّق قبل البناء — «2023-13-45» يطابق النمط ولا يصلح تاريخاً،
            //       وبناؤه مباشرةً يرمي استثناءً يُفشل استيراد الدفعة كلها بسبب ملف واحد.
            if (mo is < 1 or > 12 || d < 1 || d > DateTime.DaysInMonth(y, mo)) continue;

            rest = stem.Remove(m.Index, m.Length);
            return new DateTime(y, mo, d);
        }

        rest = stem;
        return null;
    }
}
