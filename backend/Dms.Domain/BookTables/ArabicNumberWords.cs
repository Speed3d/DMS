namespace Dms.Domain.BookTables;

/// <summary>
/// التفقيط — المبلغ بالحروف العربية (ADR-057). **تطبيقٌ واحد في الخادم**: المحرّر يطلبه، والطباعة تعيد توليده.
/// </summary>
/// <remarks>
/// 📐 **الصيغة كما في نموذج المالك** («تسعة مليارات وأربعمائة وخمسون مليون دينار عراقي»):
/// <list type="bullet">
/// <item>المئات موصولة: <b>أربعمائة · خمسمائة · تسعمائة</b> (قرار المالك 2026-10-04).</item>
/// <item>المراتب: ١ ⟵ «مليون» · ٢ ⟵ «مليونان» · ٣–١٠ ⟵ «ملايين» · وما سواها ⟵ «مليون» (كما في الفواتير العراقية).</item>
/// <item>اسم العملة ثابت بعد العدد («… دينار عراقي» · «… دولار أمريكي») كما كتبه المالك.</item>
/// <item>الكسر: سنتات الدولار (منزلتان) وفلوس الدينار (ثلاث منازل)، بقاعدة العدد والمعدود.</item>
/// </list>
/// والنصّ المولَّد بين «قبل» و«بعد» يكتبهما المستخدم (مثل «فقط … لا غير») — فالصياغة الخاصة لا تحتاج تعديله.
/// </remarks>
public static class ArabicNumberWords
{
    public const decimal Max = 999_999_999_999_999.99m;

    private static readonly string[] Ones =
        ["", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة"];

    private static readonly string[] Teens =
        ["عشرة", "أحد عشر", "اثنا عشر", "ثلاثة عشر", "أربعة عشر", "خمسة عشر", "ستة عشر", "سبعة عشر", "ثمانية عشر", "تسعة عشر"];

    private static readonly string[] Tens =
        ["", "", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون"];

    private static readonly string[] Hundreds =
        ["", "مائة", "مئتان", "ثلاثمائة", "أربعمائة", "خمسمائة", "ستمائة", "سبعمائة", "ثمانمائة", "تسعمائة"];

    /// <summary>(مفرد، مثنّى، جمع) لكل مرتبة — الآلاف فما فوق.</summary>
    private static readonly (string One, string Two, string Plural)[] Scales =
    [
        ("ألف", "ألفان", "آلاف"),
        ("مليون", "مليونان", "ملايين"),
        ("مليار", "ملياران", "مليارات"),
        ("تريليون", "تريليونان", "تريليونات"),
    ];

    /// <summary>
    /// المبلغ بالحروف مع اسم العملة (<c>IQD</c> أو <c>USD</c>). السالب وما فوق <see cref="Max"/> ⟵ <see cref="ValidationException"/>.
    /// </summary>
    public static string ToWords(decimal amount, string currency)
    {
        if (amount < 0) throw new ValidationException("لا يُكتب مبلغٌ سالبٌ بالحروف.");
        if (amount > Max) throw new ValidationException("المبلغ أكبر من أن يُكتب بالحروف.");

        var usd = currency == "USD";
        if (!usd && currency != "IQD") throw new ValidationException("العملة غير معروفة.");

        var whole = decimal.Truncate(amount);
        var fraction = (long)decimal.Round((amount - whole) * (usd ? 100 : 1000), MidpointRounding.AwayFromZero);
        if (fraction == (usd ? 100 : 1000)) { whole += 1; fraction = 0; }   // 0.999 دينار ⟵ دينارٌ كامل

        var name = usd ? "دولار أمريكي" : "دينار عراقي";
        var wholeWords = whole == 0 && fraction > 0 ? null : $"{Integer((long)whole)} {name}";
        if (fraction == 0) return wholeWords!;

        var fractionWords = usd
            ? Counted(fraction, "سنت واحد", "سنتان", "سنتات", "سنتاً")
            : Counted(fraction, "فلس واحد", "فلسان", "فلوس", "فلساً");
        return wholeWords is null ? fractionWords : $"{wholeWords} و{fractionWords}";
    }

    /// <summary>العدد الصحيح بالحروف (بلا عملة) — «صفر» للصفر.</summary>
    public static string Integer(long n)
    {
        if (n == 0) return "صفر";
        var parts = new List<string>();
        var groups = new List<int>();
        for (var x = n; x > 0; x /= 1000) groups.Add((int)(x % 1000));

        for (var i = groups.Count - 1; i >= 0; i--)
        {
            var g = groups[i];
            if (g == 0) continue;
            parts.Add(i == 0 ? Below1000(g) : Scaled(g, Scales[i - 1]));
        }
        return string.Join(" و", parts);
    }

    private static string Scaled(int n, (string One, string Two, string Plural) s) => n switch
    {
        1 => s.One,
        2 => s.Two,
        _ => $"{Below1000(n)} {(n % 100 is >= 3 and <= 10 ? s.Plural : s.One)}",
    };

    private static string Counted(long n, string one, string two, string plural, string many) => n switch
    {
        1 => one,
        2 => two,
        _ => $"{Below1000((int)n)} {(n % 100 is >= 3 and <= 10 ? plural : many)}",
    };

    private static string Below1000(int n)
    {
        var parts = new List<string>();
        var h = n / 100;
        var rest = n % 100;
        if (h > 0) parts.Add(Hundreds[h]);
        if (rest > 0)
        {
            if (rest < 10) parts.Add(Ones[rest]);
            else if (rest < 20) parts.Add(Teens[rest - 10]);
            else
            {
                var o = rest % 10;
                parts.Add(o == 0 ? Tens[rest / 10] : $"{Ones[o]} و{Tens[rest / 10]}");
            }
        }
        return string.Join(" و", parts);
    }
}
