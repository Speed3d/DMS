using System.Globalization;
using System.Text;

namespace Dms.Domain.BookTables;

/// <summary>
/// الجمع الحيّ والمبلغ كتابةً (ADR-057) — **يُعاد حسابهما عند كل طباعة**، فالخادم لا يثق برقمٍ أرسله العميل.
/// </summary>
/// <remarks>
/// 🔑 **قاعدة الجمع مستخلصةٌ من فاتورة المالك**: خليةُ المجموع فيها مدموجةٌ تحت عمودَي «المادة بالعربي»
/// و«الكمية» بينما ما يُجمع هو «السعر الكلي» — فالعمود المجموع **يُختار** (<see cref="CellFormula.Col"/>)
/// ولا يُستنتج من موضع الخلية.
/// <list type="bullet">
/// <item>يُجمع كل رقمٍ <b>فوق</b> الخلية في ذلك العمود حتى صفوف العناوين.</item>
/// <item>تُتخطّى الخلايا الفارغة والنصّية (كصفّ «17 — مواد احتياطية» بخلاياه الفارغة).</item>
/// <item>وتُتخطّى <b>خلايا الجمع الأخرى</b> — فلا يُحسب مجموعٌ فرعيٌّ مرّتين.</item>
/// <item>والخلية المدموجة عمودياً تُعدّ <b>مرّةً واحدة</b> (في صفّ بدايتها).</item>
/// </list>
/// </remarks>
public static class TableFormulas
{
    /// <summary>القيمة المحسوبة لخليةٍ ذات صيغة أو كتابةٍ بالحروف — النصّ كما يُطبع.</summary>
    public sealed record Computed(string Text, decimal? Value);

    /// <summary>يحسب كل خلايا الجمع ثم كل خلايا «كتابة بالحروف» — مفهرسةً بمعرّف الخلية.</summary>
    /// <param name="words">مولّد الحروف — افتراضاً <see cref="ArabicNumberWords.ToWords"/> (يُستبدل في الاختبار).</param>
    public static IReadOnlyDictionary<string, Computed> Evaluate(BookTable t, Func<decimal, string, string>? words = null)
    {
        words ??= ArabicNumberWords.ToWords;
        var result = new Dictionary<string, Computed>();
        var rows = t.Rows.Count;
        var cols = t.Cols.Count;

        // أين تبدأ كل خليةٍ تغطّي كل خانة؟ (للدمج العمودي: لا تُعدّ إلا في صفّ بدايتها)
        var owner = new (int Row, TableCell Cell)?[rows, cols];
        for (var r = 0; r < rows; r++)
            for (var c = 0; c < cols && c < t.Rows[r].Cells.Count; c++)
                if (t.Rows[r].Cells[c] is { } cell)
                    for (var rr = r; rr < Math.Min(rows, r + cell.RowSpan); rr++)
                        for (var cc = c; cc < Math.Min(cols, c + cell.ColSpan); cc++)
                            owner[rr, cc] = (r, cell);

        // ١) الجمع
        for (var r = 0; r < rows; r++)
            foreach (var cell in t.Rows[r].Cells.OfType<TableCell>().Where(x => x.Formula is not null))
            {
                var col = cell.Formula!.Col;
                decimal sum = 0;
                var decimals = 0;
                for (var i = t.HeaderRows; i < r; i++)
                {
                    if (col < 0 || col >= cols || owner[i, col] is not { } o || o.Row != i) continue;
                    if (o.Cell.Formula is not null || o.Cell.Words is not null) continue;
                    var text = BookTableCodec.PlainText(o.Cell.Html);
                    if (ParseNumber(text) is not { } v) continue;
                    sum += v;
                    if (HasFraction(text)) decimals = 2;
                }
                result[cell.Id] = new Computed(Format(sum, decimals), sum);
            }

        // ٢) المبلغ كتابةً — من خلية جمعٍ محسوبة أو من رقمٍ مكتوب
        var byId = new Dictionary<string, TableCell>();
        foreach (var c in t.Rows.SelectMany(r => r.Cells).OfType<TableCell>()) byId.TryAdd(c.Id, c);
        foreach (var cell in byId.Values.Where(c => c.Words is not null))
        {
            var w = cell.Words!;
            decimal? value = result.TryGetValue(w.SourceCellId, out var computed)
                ? computed.Value
                : byId.TryGetValue(w.SourceCellId, out var src) ? ParseNumber(BookTableCodec.PlainText(src.Html)) : null;

            string core;
            try { core = value is { } v ? words(v, w.Currency) : ""; }
            catch (ValidationException) { core = ""; }   // سالبٌ أو ضخم ⟵ بلا حروف لا انهيار الطباعة
            var text = string.Join(" ", new[] { w.Prefix?.Trim(), core, w.Suffix?.Trim() }.Where(s => !string.IsNullOrEmpty(s)));
            result[cell.Id] = new Computed(text, value);
        }
        return result;
    }

    /// <summary>
    /// يقرأ رقماً من نصّ خلية: بفواصل الآلاف (<c>1,425,000,000</c>) وبالكسر (<c>1,430.33</c>) وبالأرقام الهندية —
    /// و<c>null</c> لأيّ نصٍّ غير رقميٍّ خالص («2 قطعة» · «ـــــ» · فارغ).
    /// </summary>
    public static decimal? ParseNumber(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var sb = new StringBuilder(text.Length);
        foreach (var ch in text.Trim())
        {
            if (ch is >= '٠' and <= '٩') sb.Append((char)('0' + (ch - '٠')));       // ٠–٩
            else if (ch is >= '۰' and <= '۹') sb.Append((char)('0' + (ch - '۰')));  // ۰–۹
            else if (ch == '٫') sb.Append('.');                                               // ٫
            else if (ch is ',' or '٬' or ' ' or ' ') { }                                 // فواصل الآلاف
            else sb.Append(ch);
        }
        var s = sb.ToString();
        if (s.Length == 0 || s.Count(c => c == '.') > 1) return null;
        return decimal.TryParse(s, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign,
            CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    /// <summary>بفواصل الآلاف كما في نموذج المالك — <c>9,450,000,000</c> أو <c>1,430.33</c>.</summary>
    public static string Format(decimal value, int decimals) =>
        value.ToString(decimals > 0 ? "N2" : "N0", CultureInfo.InvariantCulture);

    private static bool HasFraction(string text) => text.Contains('.') || text.Contains('٫');
}
