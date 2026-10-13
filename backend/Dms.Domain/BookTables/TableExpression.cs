using System.Numerics;
using System.Text;

namespace Dms.Domain.BookTables;

/// <summary>
/// معادلةُ خليةٍ أو عمودٍ في الجدول (ADR-060): <c>+</c> و<c>−</c> و<c>×</c> و<c>÷</c> والأقواس والأرقام، **ومراجعُ بمعرّفاتٍ لا بمواضع**.
/// </summary>
/// <remarks>
/// 📦 **الشكل المخزَّن**: <c>{c8f2}*{c9a1}+2</c> — المرجع معرّفُ الخلية (أو العمود في معادلة العمود) بين قوسين معقوفين، فإدراجُ
/// صفٍّ أو عمودٍ لا يغيّر ما تشير إليه. والمحرّر يعرضها بحروف الأعمدة وأرقام الصفوف (<c>= B3 × C3</c>) ويحوّلها.
/// <para>
/// 🔐 **حدودٌ تحمي الخادم** (<see cref="MaxLength"/> · <see cref="MaxRefs"/> · <see cref="MaxDepth"/> · <see cref="MaxNumberDigits"/>) — المعادلة
/// نصٌّ يصل من العميل، فلا يُقبل شاذٌّ يُثقل الحساب أو يُغرق المكدّس.
/// </para>
/// </remarks>
public sealed class TableExpression
{
    public const int MaxLength = 500;
    public const int MaxRefs = 50;
    public const int MaxDepth = 20;
    public const int MaxNumberDigits = 18;
    public const int MaxIdLength = 64;

    private readonly Node _root;

    /// <summary>المعرّفات المشار إليها — بلا تكرار، بترتيب ظهورها.</summary>
    public IReadOnlyList<string> Refs { get; }

    private TableExpression(Node root, IReadOnlyList<string> refs) { _root = root; Refs = refs; }

    /// <summary>يقرأ معادلةً مخزَّنة — أو يرمي <see cref="ValidationException"/> برسالةٍ عربية.</summary>
    public static TableExpression Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new ValidationException("المعادلة فارغة.");
        if (text.Length > MaxLength) throw new ValidationException($"المعادلة أطول من الحدّ ({MaxLength} حرفاً).");
        var p = new Parser(text);
        var root = p.ParseExpression(0);
        p.SkipSpaces();
        if (!p.AtEnd) throw new ValidationException("المعادلة غير مكتملة أو فيها رمزٌ غير مفهوم.");
        if (p.Refs.Count > MaxRefs) throw new ValidationException($"المعادلة تشير إلى خلايا أكثر من الحدّ ({MaxRefs}).");
        return new TableExpression(root, p.Refs);
    }

    /// <summary>نتيجة الحساب: قيمةٌ أو رمزُ خطأ (<see cref="TableFormulas"/> يحمل رسائلها).</summary>
    public readonly record struct Result(Rational? Value, string? Error)
    {
        public static Result Ok(Rational v) => new(v, null);
        public static Result Fail(string code) => new(null, code);
    }

    /// <summary>يحسب المعادلة — وقيمةُ كل مرجعٍ من <paramref name="resolve"/>. القسمة على صفر خطأ لا انهيار.</summary>
    public Result Evaluate(Func<string, Result> resolve) => Eval(_root, resolve);

    private static Result Eval(Node n, Func<string, Result> resolve)
    {
        switch (n)
        {
            case Num num: return Result.Ok(num.Value);
            case Ref r: return resolve(r.Id);
            case Neg neg:
                var v = Eval(neg.Inner, resolve);
                return v.Error is null ? Result.Ok(-v.Value!.Value) : v;
            case Bin b:
                var l = Eval(b.Left, resolve);
                if (l.Error is not null) return l;
                var rr = Eval(b.Right, resolve);
                if (rr.Error is not null) return rr;
                var x = l.Value!.Value;
                var y = rr.Value!.Value;
                return b.Op switch
                {
                    '+' => Result.Ok(x + y),
                    '-' => Result.Ok(x - y),
                    '*' => Result.Ok(x * y),
                    _ => y.IsZero ? Result.Fail(TableFormulas.ErrDivZero) : Result.Ok(x / y),
                };
            default: throw new InvalidOperationException();
        }
    }

    // ─────────────────────────── الشجرة ───────────────────────────

    private abstract record Node;
    private sealed record Num(Rational Value) : Node;
    private sealed record Ref(string Id) : Node;
    private sealed record Neg(Node Inner) : Node;
    private sealed record Bin(char Op, Node Left, Node Right) : Node;

    // ─────────────────────────── المحلّل ───────────────────────────
    //  expr  := term  (('+' | '-') term)*
    //  term  := unary (('*' | '/') unary)*
    //  unary := ('-' | '+') unary | primary
    //  primary := number | '{' id '}' | '(' expr ')'

    private sealed class Parser(string s)
    {
        private int _i;
        public readonly List<string> Refs = [];
        public bool AtEnd => _i >= s.Length;

        public void SkipSpaces()
        {
            while (_i < s.Length && char.IsWhiteSpace(s[_i])) _i++;
        }

        private char? Peek()
        {
            SkipSpaces();
            return _i < s.Length ? s[_i] : null;
        }

        /// <summary>رمز العملية بصيغته الموحّدة — والمحرّر قد يكتب ×/÷/− فتُقبل كذلك.</summary>
        private static char? Op(char c) => c switch
        {
            '+' => '+',
            '-' or '−' => '-',
            '*' or '×' => '*',
            '/' or '÷' => '/',
            _ => null,
        };

        public Node ParseExpression(int depth)
        {
            if (depth > MaxDepth) throw new ValidationException($"المعادلة متداخلةٌ أكثر من الحدّ ({MaxDepth} مستوى).");
            var left = ParseTerm(depth);
            while (Peek() is { } c && Op(c) is '+' or '-')
            {
                var op = Op(c)!.Value;
                _i++;
                left = new Bin(op, left, ParseTerm(depth));
            }
            return left;
        }

        private Node ParseTerm(int depth)
        {
            var left = ParseUnary(depth);
            while (Peek() is { } c && Op(c) is '*' or '/')
            {
                var op = Op(c)!.Value;
                _i++;
                left = new Bin(op, left, ParseUnary(depth));
            }
            return left;
        }

        private Node ParseUnary(int depth)
        {
            if (depth > MaxDepth) throw new ValidationException($"المعادلة متداخلةٌ أكثر من الحدّ ({MaxDepth} مستوى).");
            if (Peek() is { } c && Op(c) is '+' or '-')
            {
                var op = Op(c)!.Value;
                _i++;
                var inner = ParseUnary(depth + 1);
                return op == '-' ? new Neg(inner) : inner;
            }
            return ParsePrimary(depth);
        }

        private Node ParsePrimary(int depth)
        {
            var c = Peek() ?? throw new ValidationException("المعادلة تنتهي قبل أن تكتمل.");
            if (c == '(')
            {
                _i++;
                var inner = ParseExpression(depth + 1);
                if (Peek() != ')') throw new ValidationException("قوسٌ مفتوح لم يُغلق في المعادلة.");
                _i++;
                return inner;
            }
            if (c == '{')
            {
                var end = s.IndexOf('}', _i + 1);
                if (end < 0) throw new ValidationException("مرجعٌ غير مكتمل في المعادلة.");
                var id = s[(_i + 1)..end];
                if (id.Length == 0 || id.Length > MaxIdLength || !id.All(ch => char.IsAsciiLetterOrDigit(ch) || ch is '_' or '-'))
                    throw new ValidationException("مرجعٌ غير صالح في المعادلة.");
                _i = end + 1;
                if (!Refs.Contains(id)) Refs.Add(id);
                return new Ref(id);
            }
            if (Digit(c) is not null || c is '.' or '٫') return new Num(ParseNumber());
            throw new ValidationException($"رمزٌ غير مفهوم في المعادلة «{c}».");
        }

        private static int? Digit(char ch) => ch switch
        {
            >= '0' and <= '9' => ch - '0',
            >= '٠' and <= '٩' => ch - '٠',
            >= '۰' and <= '۹' => ch - '۰',
            _ => null,
        };

        private Rational ParseNumber()
        {
            var digits = new StringBuilder();
            var scale = -1;
            while (_i < s.Length)
            {
                var ch = s[_i];
                if (Digit(ch) is { } d)
                {
                    digits.Append((char)('0' + d));
                    if (scale >= 0) scale++;
                }
                else if (ch is '.' or '٫')
                {
                    if (scale >= 0) throw new ValidationException("رقمٌ فيه فاصلتان عشريتان في المعادلة.");
                    scale = 0;
                }
                else if (ch is ',' or '٬') { /* فاصل آلاف */ }
                else break;
                _i++;
            }
            if (digits.Length == 0) throw new ValidationException("رقمٌ غير صالح في المعادلة.");
            if (digits.Length > MaxNumberDigits) throw new ValidationException($"رقمٌ أطول من الحدّ ({MaxNumberDigits} رقماً) في المعادلة.");
            return new Rational(BigInteger.Parse(digits.ToString()), BigInteger.Pow(10, Math.Max(scale, 0)));
        }
    }
}
