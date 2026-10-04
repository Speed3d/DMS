using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Dms.Domain.BookTables;

/// <summary>
/// قراءة الجداول من <c>BodyHtml</c> — الوسم <c>&lt;div data-dms-table="…"&gt;&lt;/div&gt;</c> يحمل النموذج JSON مُهرَّباً.
/// </summary>
/// <remarks>
/// 🔑 **الوسم نكتبه نحن** (مُسلسِل المحرّر)، فشكله ثابتٌ معروف — والتعبير هنا يقرأ ذلك الشكل وحده.
/// والرسم في <c>Dms.Documents</c> يجد الوسم بمحلّل HTML ويطابقه **بترتيبه** مع ما تعيده <see cref="ReadAll"/>.
/// </remarks>
public static partial class BookTableCodec
{
    [GeneratedRegex("""<div\b[^>]*?\bdata-dms-table\s*=\s*(?:"(?<v>[^"]*)"|'(?<v>[^']*)')[^>]*>\s*</div>""",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, matchTimeoutMilliseconds: 2000)]
    private static partial Regex TableTag();

    /// <summary>هل في المتن جدولٌ واحدٌ على الأقلّ؟</summary>
    public static bool HasTables(string? bodyHtml) => !string.IsNullOrEmpty(bodyHtml) && TableTag().IsMatch(bodyHtml);

    /// <summary>نصوص النماذج JSON بترتيب ظهورها في المتن (بعد فكّ التهريب).</summary>
    public static IReadOnlyList<string> ExtractJson(string? bodyHtml)
    {
        if (string.IsNullOrEmpty(bodyHtml)) return [];
        return TableTag().Matches(bodyHtml).Select(m => WebUtility.HtmlDecode(m.Groups["v"].Value)).ToList();
    }

    /// <summary>يحوّل JSON إلى نموذج — والتالف <see cref="ValidationException"/> برقم الجدول.</summary>
    public static BookTable Parse(string json, int index = 1)
    {
        try
        {
            return JsonSerializer.Deserialize<BookTable>(json, BookTableJson.Options)
                   ?? throw new ValidationException($"الجدول {index} فارغ.");
        }
        catch (JsonException)
        {
            throw new ValidationException($"الجدول {index} تالفٌ ولا يمكن قراءته. أعد إدراجه.");
        }
    }

    /// <summary>كل جداول المتن بترتيبها — بلا فحص القواعد (انظر <see cref="BookTableRules.ValidateBody"/>).</summary>
    public static IReadOnlyList<BookTable> ReadAll(string? bodyHtml) =>
        ExtractJson(bodyHtml).Select((json, i) => Parse(json, i + 1)).ToList();

    /// <summary>المتن بلا وسوم الجداول — لمعرفة هل تغيّر **النصّ خارجها** (سجلّ الحركة).</summary>
    public static string StripTables(string? bodyHtml) =>
        string.IsNullOrEmpty(bodyHtml) ? "" : TableTag().Replace(bodyHtml, "");

    /// <summary>نصٌّ خالص من HTML خلية — للأرقام والمقارنة (الوسوم تُحذف والكيانات تُفكّ والمسافات تُطوى).</summary>
    public static string PlainText(string? html)
    {
        if (string.IsNullOrEmpty(html)) return "";
        var withBreaks = BreakTag().Replace(html, "\n");
        var noTags = AnyTag().Replace(withBreaks, "");
        var decoded = WebUtility.HtmlDecode(noTags);
        return Spaces().Replace(decoded, " ").Trim();
    }

    [GeneratedRegex(@"<\s*(br|/p|/div|/li)\b[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex BreakTag();

    [GeneratedRegex(@"<[^>]*>")]
    private static partial Regex AnyTag();

    [GeneratedRegex(@"[ \t\r\n ]+")]
    private static partial Regex Spaces();
}
