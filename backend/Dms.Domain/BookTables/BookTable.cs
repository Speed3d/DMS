using System.Text.Json;
using System.Text.Json.Serialization;

namespace Dms.Domain.BookTables;

/// <summary>
/// جدولٌ داخل متن الكتاب الصادر (ADR-057) — **النموذج البنيويّ الواحد** الذي يكتبه المحرّر ويقرؤه الخادم.
/// </summary>
/// <remarks>
/// 🔑 **لماذا نموذجٌ لا HTML جداول؟** HTML الحرّ (colspan/rowspan/style) يُكتب بأشكالٍ لا تُحصى، ومطابقتُه بين
/// المحرّر والطباعة وWord ثلاثةُ محلّلاتٍ تتباعد. هنا شكلٌ واحدٌ مُعرَّف، يُفحص بقواعد صريحة (<see cref="BookTableRules"/>)،
/// ويُرسم كما هو. ونصُّ كل خلية وحده HTML — يقرؤه محرّك الفقرات القائم نفسه.
/// <para>
/// 📦 **أين يُخزَّن؟** في <c>BodyJson</c> (داخل Delta المحرّر) وفي <c>BodyHtml</c> كوسمٍ واحد
/// <c>&lt;div data-dms-table="…"&gt;&lt;/div&gt;</c> — فلا عمودَ جديد ولا مهاجرة للمتن.
/// </para>
/// <para>
/// ⚠️ **الخادم لا يعيد كتابة النموذج المخزَّن** — يقرؤه ليفحصه ويرسمه، ويعيد حساب الصيغ عند الطباعة فقط
/// (<see cref="TableFormulas"/>)، فلا يضيع حقلٌ لا يعرفه إصدارٌ أقدم.
/// </para>
/// </remarks>
public sealed record BookTable
{
    public string Id { get; init; } = "";
    public int V { get; init; } = 1;

    /// <summary>اتجاه الجدول — <c>rtl</c> (العمود الأوّل يميناً) أو <c>ltr</c>.</summary>
    public string Dir { get; init; } = "rtl";

    /// <summary>عرض الجدول نسبةً من عرض المتن (30–100).</summary>
    public int WidthPct { get; init; } = 100;

    /// <summary>محاذاة الجدول الأضيق من المتن — <c>center</c> · <c>start</c> · <c>end</c>.</summary>
    public string Align { get; init; } = "center";

    public TableBorder Border { get; init; } = new();

    /// <summary>عدد صفوف العناوين في أعلى الجدول.</summary>
    public int HeaderRows { get; init; }

    /// <summary>تكرار صفوف العناوين في أعلى كل صفحة (وإلا تظهر في البداية فقط).</summary>
    public bool RepeatHeader { get; init; } = true;

    /// <summary>عمود الترقيم التلقائي («ت») — أو <c>null</c>.</summary>
    public int? NumberingCol { get; init; }

    public List<TableColumn> Cols { get; init; } = [];
    public List<TableRow> Rows { get; init; } = [];
}

public sealed record TableBorder
{
    /// <summary>سُمك الشبكة بالنقاط (0 = بلا حدود).</summary>
    public double WidthPt { get; init; } = 0.75;
    public string Color { get; init; } = "#000000";
}

public sealed record TableColumn
{
    public string Id { get; init; } = "";

    /// <summary>عرضٌ نسبيّ — يُوزَّع عرض الجدول على مجموع الأوزان.</summary>
    public double Weight { get; init; } = 1;
}

public sealed record TableRow
{
    public string Id { get; init; } = "";

    /// <summary>خانةٌ لكل عمود — و<c>null</c> خانةٌ يغطّيها دمجٌ من خليةٍ قبلها.</summary>
    public List<TableCell?> Cells { get; init; } = [];
}

public sealed record TableCell
{
    public string Id { get; init; } = "";
    public int RowSpan { get; init; } = 1;
    public int ColSpan { get; init; } = 1;

    /// <summary>لون الخلفية <c>#RRGGBB</c> أو <c>null</c>.</summary>
    public string? Bg { get; init; }

    /// <summary>المحاذاة العمودية — <c>top</c> · <c>middle</c> · <c>bottom</c>.</summary>
    public string VAlign { get; init; } = "middle";

    /// <summary>نصّ الخلية HTML (تنسيقٌ مختلط) — يولّده المحرّر من Delta الخلية.</summary>
    public string Html { get; init; } = "";

    /// <summary>جمعٌ حيّ — يُعاد حسابه عند كل طباعة.</summary>
    public CellFormula? Formula { get; init; }

    /// <summary>المبلغ كتابةً من خليةٍ أخرى — يُعاد توليده عند كل طباعة.</summary>
    public CellWords? Words { get; init; }
}

/// <summary>صيغة الخلية — اليوم <c>sum</c> وحدها: كل رقمٍ فوقها في العمود <see cref="Col"/> حتى العناوين.</summary>
public sealed record CellFormula
{
    public string Type { get; init; } = "sum";
    public int Col { get; init; }
}

/// <summary>«كتابة بالحروف»: نصٌّ مولَّد من رقم خليةٍ أخرى، بين «قبل» و«بعد» يكتبهما المستخدم.</summary>
public sealed record CellWords
{
    public string SourceCellId { get; init; } = "";
    public string Currency { get; init; } = "IQD";
    public string? Prefix { get; init; }
    public string? Suffix { get; init; }
}

/// <summary>خيارات JSON الموحَّدة للجدول (camelCase — كما يكتبها المحرّر).</summary>
public static class BookTableJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        MaxDepth = 32,
    };
}
