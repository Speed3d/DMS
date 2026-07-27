namespace Dms.Api;

/// <summary>
/// نوع المحتوى الحقيقي حسب امتداد الملف — للعرض داخل البرنامج.
/// </summary>
/// <remarks>
/// Hint: كانت المرفقات تُرسَل دائماً بـ<c>application/octet-stream</c> مع اسم ملف، وهو ما
/// يُنتج <c>Content-Disposition: attachment</c> فيعامل المتصفّح الاستجابةَ تنزيلاً —
/// **ويختطفها مديرو التحميل (IDM وأمثاله) حتى حين نجلبها بـXHR للعرض**. النوع الصحيح
/// بلا اسم ملف يجعلها عرضاً لا تنزيلاً، فلا تُختطف.
/// </remarks>
public static class MimeTypes
{
    private static readonly Dictionary<string, string> Map = new(StringComparer.OrdinalIgnoreCase)
    {
        [".pdf"] = "application/pdf",
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif",
        [".webp"] = "image/webp",
        [".txt"] = "text/plain; charset=utf-8",
        [".docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        [".xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        [".zip"] = "application/zip",
    };

    public static string For(string fileName)
    {
        var ext = Path.GetExtension(fileName);
        return ext is not null && Map.TryGetValue(ext, out var mime) ? mime : "application/octet-stream";
    }
}
