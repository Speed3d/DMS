namespace Dms.Documents.Models;

/// <summary>
/// جدولٌ جاهزٌ للرسم (ADR-057) — **نموذج الطباعة** لا نموذج القواعد: فُحص وحُسبت صيغه قبل أن يصل هنا.
/// </summary>
/// <remarks>
/// 🔑 <c>Dms.Documents</c> مستقلٌّ لا يعرف <c>Dms.Domain</c> (حدود الطبقات) — فطبقة البنية تحوّل جدول القواعد إلى هذا
/// النموذج بعد الفحص وإعادة حساب Σ والحروف، والراسم يرسم ما يُعطى بلا قرار.
/// </remarks>
public sealed record PrintTable
{
    /// <summary>العمود الأوّل يميناً (<c>true</c>) أو يساراً.</summary>
    public bool Rtl { get; init; } = true;

    /// <summary>عرض الجدول نسبةً من عرض المتن (30–100).</summary>
    public int WidthPct { get; init; } = 100;

    /// <summary><c>center</c> · <c>start</c> (بداية الاتجاه) · <c>end</c>.</summary>
    public string Align { get; init; } = "center";

    public float BorderPt { get; init; } = 0.75f;
    public string BorderColor { get; init; } = "#000000";

    public int HeaderRows { get; init; }
    public bool RepeatHeader { get; init; } = true;

    public IReadOnlyList<float> ColumnWeights { get; init; } = [];
    public int RowCount { get; init; }

    /// <summary>الخلايا الحقيقية وحدها (لا الخانات التي يغطّيها دمج) بمواضعها من الصفر.</summary>
    public IReadOnlyList<PrintCell> Cells { get; init; } = [];
}

public sealed record PrintCell(int Row, int Col, int RowSpan, int ColSpan, string? Bg, string VAlign, string Html);

/// <summary>في أيّ صفحاتٍ يُطبع التوقيع والختم — نظيرُ <c>SignaturePlacement</c> في المجال.</summary>
public enum PrintSignatureMode
{
    LastPage = 0,
    StampEveryPage = 1,
    EveryPage = 2,
}

/// <summary>
/// قواعد صفحات التوقيع والختم وترقيم الصفحات — **دوالُّ نقيّة** يناديها الراسم وتُختبر وحدها (ADR-057).
/// </summary>
public static class PrintPageRules
{
    /// <summary>المساحة المحجوزة أسفل المتن لكتلة التوقيع والختم (كما كانت قبل ADR-057).</summary>
    public const float SignatureZonePt = 120;

    /// <summary>
    /// هل تُحجز مساحة التوقيع في **كل** صفحة؟ — نعم ما دام شيءٌ منهما يُطبع في كل صفحة. وفي «الأخيرة وحدها»
    /// تُفرَّغ (قرار المالك: «نجرّب التفريغ») وتُحجز كتلةٌ في آخر المتن فقط.
    /// </summary>
    public static bool ReserveEveryPage(PrintSignatureMode mode) => mode != PrintSignatureMode.LastPage;

    public static bool ShowSignature(PrintSignatureMode mode, int page, int? total) =>
        mode == PrintSignatureMode.EveryPage || page == total;

    public static bool ShowStamp(PrintSignatureMode mode, int page, int? total) =>
        mode != PrintSignatureMode.LastPage || page == total;

    /// <summary>
    /// هل انتقلت كتلة التوقيع وحدها إلى صفحةٍ بعد آخر المتن؟ — الصفحة الأخيرة عندئذٍ بلا نصٍّ إطلاقاً (بلاغ المالك).
    /// </summary>
    public static bool SignatureAlone(int bodyEndPage, int totalPages) => bodyEndPage > 0 && totalPages > bodyEndPage;

    /// <summary>«صفحة X من Y» — ولا ترقيم في الكتاب ذي الصفحة الواحدة (قرار المالك).</summary>
    public static bool ShowPageNumber(bool enabled, int? total) => enabled && total is > 1;
}
