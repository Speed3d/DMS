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
    /// <summary>
    /// القيمة المحسوبة لخليةٍ ذات صيغة أو معادلة أو كتابةٍ بالحروف — النصّ كما يُطبع.
    /// و<paramref name="Error"/> رمزُ خطأٍ في معادلة (<see cref="ErrorMessage"/>) — والنصّ عندها <see cref="ErrorText"/>.
    /// </summary>
    public sealed record Computed(string Text, decimal? Value, string? Error = null);

    // ─────────────────────────── أخطاء المعادلات (ADR-060) ───────────────────────────
    // رموزٌ ثابتة يتطابق عليها الخادم والمحرّر — والرسالة العربية من ErrorMessage.

    public const string ErrDivZero = "div0";
    public const string ErrText = "text";
    public const string ErrRef = "ref";
    public const string ErrCycle = "cycle";
    public const string ErrWords = "words";
    public const string ErrBig = "big";

    /// <summary>ما يُطبع ويُعرض في خليةٍ معادلتُها خاطئة — والاعتماد يُمنع حتى تُصحَّح (<see cref="BookTableRules.EnsureNoFormulaErrors"/>).</summary>
    public const string ErrorText = "#خطأ";

    /// <summary>أكبر ناتجٍ مقبول لمعادلة (بالقيمة المطلقة) — ألف تريليون.</summary>
    public static readonly System.Numerics.BigInteger MaxCalcValue = System.Numerics.BigInteger.Pow(10, 15);

    public static string ErrorMessage(string code) => code switch
    {
        ErrDivZero => "قسمة على صفر",
        ErrText => "مرجعٌ إلى خليةٍ فيها نصٌّ لا رقم",
        ErrRef => "مرجعٌ إلى خليةٍ أو عمودٍ لم يعد موجوداً",
        ErrCycle => "معادلةٌ دائرية (تعتمد على نفسها)",
        ErrWords => "مرجعٌ إلى خلية «كتابة بالحروف»",
        ErrBig => "الناتج أكبر من الحدّ المسموح",
        _ => "خطأ في المعادلة",
    };

    /// <summary>
    /// يحسب كل الخلايا المحسوبة — **الجمع · المعادلات · الأعمدة المحسوبة · المبلغ كتابةً** — مفهرسةً بمعرّف الخلية.
    /// </summary>
    /// <param name="words">مولّد الحروف — افتراضاً <see cref="ArabicNumberWords.ToWords"/> (يُستبدل في الاختبار).</param>
    /// <remarks>
    /// 🔑 **ترتيبٌ بالاعتماد لا بالموضع** (ADR-060): معادلةٌ قد تشير إلى جمعٍ، وجمعٌ قد يجمع عموداً محسوباً — فكلُّ خليةٍ تُحسب
    /// حين يُطلب أوّل مرّة وتُحفظ، **والدائرةُ خطأٌ** لا تكرارٌ لا ينتهي.
    /// ⚠️ **وجدولٌ بلا معادلات يُحسب كما كان حرفاً** — الجمع بـ<c>decimal</c> والكسر من نصّ الخلية (حارسٌ في الاختبارات).
    /// </remarks>
    public static IReadOnlyDictionary<string, Computed> Evaluate(BookTable t, Func<decimal, string, string>? words = null)
        => new Evaluator(t, words ?? ArabicNumberWords.ToWords).Run();

    /// <summary>حرف العمود كما يعرضه المحرّر — <c>A</c> · <c>B</c> · … · <c>Z</c> · <c>AA</c> (من بداية الجدول).</summary>
    public static string ColumnLetter(int index)
    {
        var s = "";
        for (var n = index + 1; n > 0; n = (n - 1) / 26) s = (char)('A' + (n - 1) % 26) + s;
        return s;
    }

    private sealed class Evaluator
    {
        private readonly BookTable _t;
        private readonly Func<decimal, string, string> _words;
        private readonly int _rows, _cols;
        private readonly (int Row, int Col, TableCell Cell)?[,] _owner;
        private readonly Dictionary<string, (int Row, int Col, TableCell Cell)> _byId = [];
        private readonly Dictionary<string, int> _colIndex = [];
        private readonly Dictionary<string, Cv> _memo = [];
        private readonly HashSet<string> _visiting = [];

        /// <summary>خلايا العمود المحسوب: معرّف الخلية ⟵ (الصفّ · معادلة العمود أو خطأ قراءتها).</summary>
        private readonly Dictionary<string, (int Row, TableExpression? Expr)> _colTargets = [];
        private readonly Dictionary<string, TableExpression?> _cellExprs = [];

        /// <summary>قيمةٌ داخلية: كسرٌ دقيق أو خطأ — و<c>Blank</c> لعمودٍ محسوبٍ مراجعُه في صفّه فارغةٌ كلُّها.</summary>
        private readonly record struct Cv(Rational? Value, string? Error, bool Blank, Computed Out);

        public Evaluator(BookTable t, Func<decimal, string, string> words)
        {
            _t = t;
            _words = words;
            _rows = t.Rows.Count;
            _cols = t.Cols.Count;
            _owner = new (int, int, TableCell)?[_rows, _cols];
            for (var i = 0; i < _cols; i++) _colIndex.TryAdd(t.Cols[i].Id, i);

            for (var r = 0; r < _rows; r++)
                for (var c = 0; c < _cols && c < t.Rows[r].Cells.Count; c++)
                    if (t.Rows[r].Cells[c] is { } cell)
                    {
                        _byId.TryAdd(cell.Id, (r, c, cell));
                        for (var rr = r; rr < Math.Min(_rows, r + cell.RowSpan); rr++)
                            for (var cc = c; cc < Math.Min(_cols, c + cell.ColSpan); cc++)
                                _owner[rr, cc] = (r, c, cell);
                    }

            foreach (var (id, (_, _, cell)) in _byId)
                if (cell.Calc is { } calc) _cellExprs[id] = TryParse(calc.Expr);

            // الأعمدة المحسوبة: كلُّ صفّ بندٍ مؤهَّل يأخذ معادلة عموده.
            for (var c = 0; c < _cols; c++)
            {
                if (t.Cols[c].Calc is not { } calc) continue;
                var expr = TryParse(calc.Expr);
                for (var r = t.HeaderRows; r < _rows; r++)
                    if (ColumnTarget(r, c, expr) is { } cell) _colTargets[cell.Id] = (r, expr);
            }
        }

        private static TableExpression? TryParse(string expr)
        {
            try { return TableExpression.Parse(expr); }
            catch (ValidationException) { return null; }   // الفحص (BookTableRules) يرفضها قبل الحفظ — وهنا لا تُسقط الطباعة
        }

        /// <summary>
        /// خلية العمود المحسوب في الصفّ <paramref name="r"/> — أو <c>null</c> إن لم يكن صفَّ بند: خليةٌ مفردةٌ تبدأ هنا بلا صيغةٍ
        /// ولا حروفٍ ولا معادلة · والصفّ ليس صفَّ مجموع · وكلُّ عمودٍ تشير إليه المعادلة خليةٌ مفردةٌ تبدأ في الصفّ نفسه
        /// (فصفُّ عنوانٍ مدموجٍ كـ«17 — مواد احتياطية» يُتخطّى ولا يصير خطأً).
        /// </summary>
        private TableCell? ColumnTarget(int r, int c, TableExpression? expr)
        {
            if (_owner[r, c] is not { } o || o.Row != r || o.Col != c) return null;
            var cell = o.Cell;
            if (cell.RowSpan != 1 || cell.ColSpan != 1 || cell.Formula is not null || cell.Words is not null || cell.Calc is not null) return null;
            if (_t.Rows[r].Cells.Any(x => x is not null && (x.Formula is not null || x.Words is not null))) return null;
            if (expr is null) return cell;   // معادلةٌ لا تُقرأ ⟵ خطأٌ ظاهر في كل صفّ بند
            foreach (var id in expr.Refs)
            {
                if (!_colIndex.TryGetValue(id, out var rc)) continue;   // عمودٌ حُذف ⟵ خطأ «مرجع» يظهر
                if (_owner[r, rc] is not { } ro || ro.Row != r || ro.Col != rc || ro.Cell.RowSpan != 1 || ro.Cell.ColSpan != 1)
                    return null;
            }
            return cell;
        }

        private bool IsComputed(TableCell cell) =>
            cell.Formula is not null || cell.Words is not null || cell.Calc is not null || _colTargets.ContainsKey(cell.Id);

        public IReadOnlyDictionary<string, Computed> Run()
        {
            var result = new Dictionary<string, Computed>();
            foreach (var (id, (_, _, cell)) in _byId)
                if (IsComputed(cell)) result[id] = Value(id).Out;
            return result;
        }

        private Cv Value(string id)
        {
            if (_memo.TryGetValue(id, out var hit)) return hit;
            if (!_visiting.Add(id)) return Err(TableFormulas.ErrCycle);
            var (row, col, cell) = _byId[id];
            Cv v;
            if (cell.Formula is not null) v = Sum(row, cell);
            else if (cell.Words is not null) v = Words(cell);
            else if (cell.Calc is not null) v = Calc(_cellExprs[id], CellRef, blankable: false);
            else v = Calc(_colTargets[id].Expr, colId => ColumnRef(colId, row), blankable: true);
            _visiting.Remove(id);
            _memo[id] = v;
            return v;
        }

        private static Cv Err(string code) => new(null, code, false, new Computed(TableFormulas.ErrorText, null, code));

        /// <summary>الجمع — **كما كان حرفاً** (decimal · الكسر من نصّ الخلية)، ومعه قيم الخلايا المحسوبة فوقه.</summary>
        private Cv Sum(int r, TableCell cell)
        {
            var col = cell.Formula!.Col;
            decimal sum = 0;
            var decimals = 0;
            for (var i = _t.HeaderRows; i < r; i++)
            {
                if (col < 0 || col >= _cols || _owner[i, col] is not { } o || o.Row != i) continue;
                if (o.Cell.Formula is not null || o.Cell.Words is not null) continue;
                if (o.Cell.Calc is not null || _colTargets.ContainsKey(o.Cell.Id))
                {
                    var cv = Value(o.Cell.Id);
                    if (cv.Error is not null) return Err(cv.Error);
                    if (cv.Value is not { } rv) continue;   // صفٌّ محسوبٌ فارغ
                    sum += rv.ToDecimal();
                    if (!rv.IsInteger) decimals = 2;
                    continue;
                }
                var text = BookTableCodec.PlainText(o.Cell.Html);
                if (ParseNumber(text) is not { } v) continue;
                sum += v;
                if (HasFraction(text)) decimals = 2;
            }
            return new Cv(Rational.FromDecimal(sum), null, false, new Computed(Format(sum, decimals), sum));
        }

        /// <summary>المبلغ كتابةً — من خليةٍ محسوبة أو من رقمٍ مكتوب. ومصدرٌ خاطئ يجعلها خاطئة (فيُمنع الاعتماد).</summary>
        private Cv Words(TableCell cell)
        {
            var w = cell.Words!;
            decimal? value = null;
            if (_byId.TryGetValue(w.SourceCellId, out var src))
            {
                if (IsComputed(src.Cell))
                {
                    var cv = Value(w.SourceCellId);
                    if (cv.Error is not null) return Err(cv.Error);
                    value = cv.Out.Value;
                }
                else value = ParseNumber(BookTableCodec.PlainText(src.Cell.Html));
            }

            string core;
            try { core = value is { } v ? _words(v, w.Currency) : ""; }
            catch (ValidationException) { core = ""; }   // سالبٌ أو ضخم ⟵ بلا حروف لا انهيار الطباعة
            var text = string.Join(" ", new[] { w.Prefix?.Trim(), core, w.Suffix?.Trim() }.Where(x => !string.IsNullOrEmpty(x)));
            return new Cv(value is { } d ? Rational.FromDecimal(d) : null, null, false, new Computed(text, value));
        }

        /// <summary>المعادلة: الناتج يُقرَّب إلى منزلتين **عند حدود الخلية** — وما يعتمد عليها يقرأ الرقم الذي يراه الإنسان.</summary>
        /// <param name="blankable">عمودٌ محسوب: صفٌّ مراجعُه فارغةٌ كلُّها يبقى فارغاً لا «0». ومعادلة الخلية تحسب الفارغة صفراً.</param>
        private Cv Calc(TableExpression? expr, Func<string, Operand> resolve, bool blankable)
        {
            if (expr is null) return Err(TableFormulas.ErrRef);
            var allBlank = expr.Refs.Count > 0;
            var r = expr.Evaluate(id =>
            {
                var o = resolve(id);
                if (!o.Blank) allBlank = false;
                return o.Result;
            });
            if (r.Error is not null) return Err(r.Error);
            // عمودٌ محسوبٌ مراجعُه في صفّه فارغةٌ كلُّها ⟵ فارغٌ لا «0» (صفٌّ لم يُكتب بعد)
            if (blankable && allBlank)
                return new Cv(null, null, true, new Computed("", null));
            var value = r.Value!.Value.RoundCents();
            if (value.AbsGreaterThan(MaxCalcValue)) return Err(TableFormulas.ErrBig);
            var d = value.ToDecimal();
            return new Cv(value, null, false, new Computed(Format(d, value.IsInteger ? 0 : 2), d));
        }

        /// <summary>قيمةُ مرجعٍ في معادلة — و<c>Blank</c> للخلية الفارغة (تُحسب صفراً).</summary>
        private readonly record struct Operand(TableExpression.Result Result, bool Blank);

        private Operand CellRef(string id) =>
            _byId.TryGetValue(id, out var x) ? Read(x.Cell) : new Operand(TableExpression.Result.Fail(TableFormulas.ErrRef), false);

        private Operand ColumnRef(string colId, int row)
        {
            if (!_colIndex.TryGetValue(colId, out var c) || _owner[row, c] is not { } o)
                return new Operand(TableExpression.Result.Fail(TableFormulas.ErrRef), false);
            return Read(o.Cell);
        }

        private Operand Read(TableCell cell)
        {
            if (cell.Words is not null) return new Operand(TableExpression.Result.Fail(TableFormulas.ErrWords), false);
            if (IsComputed(cell))
            {
                var cv = Value(cell.Id);
                if (cv.Error is not null) return new Operand(TableExpression.Result.Fail(cv.Error), false);
                return cv.Value is { } v ? new Operand(TableExpression.Result.Ok(v), false) : new Operand(TableExpression.Result.Ok(Rational.Zero), true);
            }
            var text = BookTableCodec.PlainText(cell.Html);
            if (string.IsNullOrWhiteSpace(text)) return new Operand(TableExpression.Result.Ok(Rational.Zero), true);   // الفارغة صفر (قرار المالك)
            return ParseNumber(text) is { } n
                ? new Operand(TableExpression.Result.Ok(Rational.FromDecimal(n)), false)
                : new Operand(TableExpression.Result.Fail(TableFormulas.ErrText), false);
        }
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

    /// <summary>
    /// نصُّ الخلية بقيمةٍ محسوبة **مع إبقاء تنسيقها** — يُستبدل أوّلُ نصٍّ فيها وتُفرَّغ البقيّة، فخليةُ مجموعٍ
    /// عريضةٌ بحجم 14 تبقى عريضةً بحجم 14 بالرقم الجديد.
    /// </summary>
    public static string WithText(string? html, string text)
    {
        var encoded = System.Net.WebUtility.HtmlEncode(text);
        if (string.IsNullOrEmpty(html)) return $"<p>{encoded}</p>";

        var replaced = false;
        var result = System.Text.RegularExpressions.Regex.Replace(html, @">([^<]*)<", m =>
        {
            if (m.Groups[1].Value.Trim().Length == 0) return m.Value;
            if (replaced) return "><";
            replaced = true;
            return $">{encoded}<";
        });
        if (replaced) return result;

        // خليةٌ بلا نصّ: يُدرج **داخل أعمق وسمٍ فارغ** — قبل أوّل وسمِ إغلاق — فيرث تنسيقه كاملاً
        // (<p><strong><span style="font-size: 14pt"></span></strong></p> ⟵ الرقم عريضٌ بحجم 14). ويُحذف السطر الفارغ.
        // 🐛 كان يُدرج بعد وسم الفقرة **خارج** <strong>/<span> فخرج المجموع رفيعاً صغيراً (كشفته طباعة فاتورة المالك).
        var cleaned = System.Text.RegularExpressions.Regex.Replace(html, @"<br\s*/?>", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var close = cleaned.IndexOf("</", StringComparison.Ordinal);
        return close > 0 ? cleaned.Insert(close, encoded) : $"<p>{encoded}</p>";
    }
}
