using System.Text.RegularExpressions;

namespace Dms.Domain.BookTables;

/// <summary>
/// قواعد الجدول (ADR-057) — **الخادم هو الحَكَم**: ما يمرّ هنا يُرسم، وما لا يمرّ يُرفض برسالةٍ عربية (400).
/// </summary>
/// <remarks>
/// ⚖️ **الحدود التقنية واسعةٌ عمداً** (قرار المالك: «تحكّمٌ حرّ بلا رقمٍ معيّن») — هي حمايةٌ للخادم من الشاذّ
/// لا قيدٌ على العمل: فاتورة المالك 6 أعمدة و74 صفّاً، والحدّ 30 و600.
/// <para>
/// 🔐 **نصُّ الخلية HTML بقائمةٍ بيضاء من الوسوم** — يُرسم PDF وWord لا في متصفّح، فالخطر ليس سكربتاً يعمل بل
/// محتوىً لا يفهمه الراسم أو يُثقله. ومحرّك الفقرات نفسه لا يفسّر إلا ما يعرفه.
/// </para>
/// </remarks>
public static partial class BookTableRules
{
    public const int MaxTables = 25;
    public const int MaxColumns = 30;
    public const int MaxRows = 600;
    public const int MaxCellHtmlChars = 20_000;
    public const int MaxWordsAffixChars = 200;
    public const double MaxBorderPt = 6;

    private static readonly HashSet<string> AllowedTags = new(StringComparer.OrdinalIgnoreCase)
    {
        "p", "br", "span", "strong", "b", "em", "i", "u", "s", "div", "ol", "ul", "li",
    };

    private static readonly HashSet<string> Dirs = ["rtl", "ltr"];
    private static readonly HashSet<string> Aligns = ["center", "start", "end"];
    private static readonly HashSet<string> VAligns = ["top", "middle", "bottom"];
    private static readonly HashSet<string> Currencies = ["IQD", "USD"];

    [GeneratedRegex("^#[0-9A-Fa-f]{6}$")]
    private static partial Regex HexColor();

    [GeneratedRegex(@"<\s*/?\s*([a-zA-Z][a-zA-Z0-9]*)")]
    private static partial Regex TagName();

    /// <summary>يقرأ جداول المتن كلَّها ويفحصها — ويعيدها بترتيبها. الخطأ ⟵ <see cref="ValidationException"/>.</summary>
    public static IReadOnlyList<BookTable> ValidateBody(string? bodyHtml)
    {
        var tables = BookTableCodec.ReadAll(bodyHtml);
        if (tables.Count > MaxTables)
            throw new ValidationException($"عدد الجداول في الكتاب ({tables.Count}) أكبر من الحدّ ({MaxTables}).");

        for (var i = 0; i < tables.Count; i++) Validate(tables[i], i + 1);

        var dup = tables.GroupBy(t => t.Id).FirstOrDefault(g => g.Count() > 1);
        if (dup is not null)
            throw new ValidationException("جدولان في الكتاب بالمعرّف نفسه — أعد إدراج أحدهما.");
        return tables;
    }

    /// <summary>يفحص جدولاً واحداً (<paramref name="n"/> رقمه في الكتاب للرسائل).</summary>
    public static void Validate(BookTable t, int n = 1)
    {
        void Fail(string message) => throw new ValidationException($"الجدول {n}: {message}");

        if (t.V != 1) Fail("صيغةٌ لا يعرفها هذا الإصدار من البرنامج.");
        if (string.IsNullOrWhiteSpace(t.Id)) Fail("بلا معرّف.");
        if (!Dirs.Contains(t.Dir)) Fail("اتجاهٌ غير معروف.");
        if (!Aligns.Contains(t.Align)) Fail("محاذاةٌ غير معروفة.");
        if (t.WidthPct is < 30 or > 100) Fail("العرض يجب أن يكون بين 30% و100% من عرض الصفحة.");
        if (t.Border is null || double.IsNaN(t.Border.WidthPt) || t.Border.WidthPt < 0 || t.Border.WidthPt > MaxBorderPt)
            Fail($"سُمك الحدود يجب أن يكون بين 0 و{MaxBorderPt}.");
        if (!HexColor().IsMatch(t.Border!.Color)) Fail("لون الحدود غير صالح.");

        var cols = t.Cols.Count;
        var rows = t.Rows.Count;
        if (cols == 0 || rows == 0) Fail("جدولٌ بلا صفوف أو أعمدة.");
        if (cols > MaxColumns) Fail($"عدد الأعمدة ({cols}) أكبر من الحدّ ({MaxColumns}).");
        if (rows > MaxRows) Fail($"عدد الصفوف ({rows}) أكبر من الحدّ ({MaxRows}).");
        if (t.HeaderRows < 0 || t.HeaderRows > rows) Fail("عدد صفوف العناوين أكبر من عدد الصفوف.");
        if (t.NumberingCol is { } nc && (nc < 0 || nc >= cols)) Fail("عمود الترقيم خارج الجدول.");

        foreach (var c in t.Cols)
            if (string.IsNullOrWhiteSpace(c.Id) || double.IsNaN(c.Weight) || double.IsInfinity(c.Weight) || c.Weight <= 0 || c.Weight > 10_000)
                Fail("عرض عمودٍ غير صالح.");
        if (t.Cols.Select(c => c.Id).Distinct().Count() != cols) Fail("عمودان بالمعرّف نفسه.");
        if (t.Rows.Any(r => string.IsNullOrWhiteSpace(r.Id)) || t.Rows.Select(r => r.Id).Distinct().Count() != rows)
            Fail("صفّان بالمعرّف نفسه أو صفٌّ بلا معرّف.");

        // الشبكة: كل خانةٍ تملكها خليةٌ واحدة بالضبط — بلا تداخلٍ ولا ثقوب.
        var covered = new bool[rows, cols];
        var cellIds = new HashSet<string>();
        for (var r = 0; r < rows; r++)
        {
            var cells = t.Rows[r].Cells;
            if (cells.Count != cols) Fail($"الصفّ {r + 1} لا يطابق عدد الأعمدة.");
            for (var c = 0; c < cols; c++)
            {
                var cell = cells[c];
                if (cell is null)
                {
                    if (!covered[r, c]) Fail($"خانةٌ فارغة لا يغطّيها دمج (الصفّ {r + 1}، العمود {c + 1}).");
                    continue;
                }
                if (covered[r, c]) Fail($"خليةٌ داخل دمجٍ آخر (الصفّ {r + 1}، العمود {c + 1}).");
                if (cell.RowSpan < 1 || cell.ColSpan < 1 || r + cell.RowSpan > rows || c + cell.ColSpan > cols)
                    Fail($"دمجٌ يخرج عن حدود الجدول (الصفّ {r + 1}، العمود {c + 1}).");
                // صفوف العناوين تتكرّر في أعلى كل صفحة كتلةً واحدة — فخليةٌ منها تمتدّ إلى ما تحتها لا تُرسم.
                if (r < t.HeaderRows && r + cell.RowSpan > t.HeaderRows)
                    Fail($"خليةٌ في صفوف العناوين تمتدّ إلى ما تحتها (العمود {c + 1}). زِد عدد صفوف العناوين أو فكّ الدمج.");
                for (var rr = r; rr < r + cell.RowSpan; rr++)
                    for (var cc = c; cc < c + cell.ColSpan; cc++)
                    {
                        if (covered[rr, cc]) Fail($"دمجان متداخلان (الصفّ {rr + 1}، العمود {cc + 1}).");
                        covered[rr, cc] = true;
                    }

                if (string.IsNullOrWhiteSpace(cell.Id) || !cellIds.Add(cell.Id)) Fail("خليتان بالمعرّف نفسه أو خليةٌ بلا معرّف.");
                if (cell.Bg is not null && !HexColor().IsMatch(cell.Bg)) Fail($"لون خلفيةٍ غير صالح (الصفّ {r + 1}).");
                if (!VAligns.Contains(cell.VAlign)) Fail("محاذاةٌ عموديةٌ غير معروفة.");
                ValidateHtml(cell.Html, r, c, Fail);
                if (cell.Formula is { } f && (f.Type != "sum" || f.Col < 0 || f.Col >= cols))
                    Fail($"صيغة جمعٍ غير صالحة (الصفّ {r + 1}).");
                if (cell.Formula is not null && cell.Words is not null)
                    Fail("الخلية لا تكون جمعاً وكتابةً بالحروف معاً.");
            }
        }

        // المبلغ كتابةً: مصدره خليةٌ في الجدول نفسه، وعملةٌ معروفة.
        foreach (var cell in t.Rows.SelectMany(r => r.Cells).OfType<TableCell>().Where(c => c.Words is not null))
        {
            var w = cell.Words!;
            if (!cellIds.Contains(w.SourceCellId) || w.SourceCellId == cell.Id) Fail("«كتابة بالحروف» تشير إلى خليةٍ غير موجودة.");
            if (!Currencies.Contains(w.Currency)) Fail("عملة «كتابة بالحروف» غير معروفة.");
            if ((w.Prefix?.Length ?? 0) > MaxWordsAffixChars || (w.Suffix?.Length ?? 0) > MaxWordsAffixChars)
                Fail("نصّ «قبل» أو «بعد» المبلغ كتابةً أطول من اللازم.");
        }
    }

    private static void ValidateHtml(string html, int r, int c, Action<string> fail)
    {
        if (html.Length > MaxCellHtmlChars) fail($"نصّ خليةٍ أطول من الحدّ (الصفّ {r + 1}، العمود {c + 1}).");
        foreach (Match m in TagName().Matches(html))
            if (!AllowedTags.Contains(m.Groups[1].Value))
                fail($"تنسيقٌ غير مدعوم «{m.Groups[1].Value}» (الصفّ {r + 1}، العمود {c + 1}).");
    }
}
