using System.Globalization;
using System.Numerics;

namespace Dms.Domain.BookTables;

/// <summary>
/// عددٌ كسريٌّ دقيق (بسطٌ ومقامٌ صحيحان) — لحساب معادلات الجداول (ADR-060).
/// </summary>
/// <remarks>
/// 🔑 **لماذا لا <c>decimal</c> ولا <c>double</c>؟** المحرّر (Dart) يحسب الناتج نفسه ليُريه وهو يُكتب، والخادم يعيد حسابه عند الطباعة —
/// **ويجب أن يتطابقا رقماً برقم**. <c>double</c> يعطي <c>0.1 + 0.2 = 0.30000000000000004</c>، و<c>decimal</c> يقصّ القسمة عند 28 رقماً
/// بطريقةٍ لا نظير لها في Dart. **الكسر الدقيق لا يقصّ شيئاً**، ويُكتب بالشكل نفسه في الطرفين (<c>BigInteger</c> ⟷ <c>BigInt</c>)،
/// والتقريب يقع مرّةً واحدة عند حدود الخلية (<see cref="RoundCents"/>).
/// </remarks>
public readonly struct Rational : IEquatable<Rational>
{
    public BigInteger Num { get; }
    public BigInteger Den { get; }

    public static readonly Rational Zero = new(0, 1);

    public Rational(BigInteger num, BigInteger den)
    {
        if (den.IsZero) throw new DivideByZeroException();
        if (den.Sign < 0) { num = -num; den = -den; }
        var g = BigInteger.GreatestCommonDivisor(BigInteger.Abs(num), den);
        if (!g.IsZero && !g.IsOne) { num /= g; den /= g; }
        Num = num;
        Den = den.IsZero ? BigInteger.One : den;
    }

    public static Rational FromDecimal(decimal d)
    {
        var bits = decimal.GetBits(d);
        var scale = (bits[3] >> 16) & 0xFF;
        var mantissa = new BigInteger((uint)bits[0]) | (new BigInteger((uint)bits[1]) << 32) | (new BigInteger((uint)bits[2]) << 64);
        if ((bits[3] & int.MinValue) != 0) mantissa = -mantissa;
        return new Rational(mantissa, BigInteger.Pow(10, scale));
    }

    public bool IsZero => Num.IsZero;
    public bool IsInteger => Den.IsOne;

    public static Rational operator +(Rational a, Rational b) => new(a.Num * b.Den + b.Num * a.Den, a.Den * b.Den);
    public static Rational operator -(Rational a, Rational b) => new(a.Num * b.Den - b.Num * a.Den, a.Den * b.Den);
    public static Rational operator *(Rational a, Rational b) => new(a.Num * b.Num, a.Den * b.Den);
    public static Rational operator /(Rational a, Rational b) => new(a.Num * b.Den, a.Den * b.Num);
    public static Rational operator -(Rational a) => new(-a.Num, a.Den);

    /// <summary>
    /// تقريبٌ إلى منزلتين عشريتين — **النصف بعيداً عن الصفر** (<c>2.345 ⟵ 2.35</c> · <c>-2.345 ⟵ -2.35</c>)، كالتقريب المدرسيّ وكالإكسل.
    /// </summary>
    public Rational RoundCents()
    {
        var scaled = Num * 100;
        var q = BigInteger.DivRem(BigInteger.Abs(scaled), Den, out var rem);
        if (rem * 2 >= Den) q += 1;
        return new Rational(scaled.Sign < 0 ? -q : q, 100);
    }

    /// <summary>القيمة <c>decimal</c> — للتنسيق والتفقيط بعد التقريب (المقام 1 أو 100 فلا يضيع شيء).</summary>
    public decimal ToDecimal() => (decimal)Num / (decimal)Den;

    /// <summary>هل القيمة المطلقة أكبر من <paramref name="limit"/>؟</summary>
    public bool AbsGreaterThan(BigInteger limit) => BigInteger.Abs(Num) > limit * Den;

    public bool Equals(Rational other) => Num == other.Num && Den == other.Den;
    public override bool Equals(object? obj) => obj is Rational r && Equals(r);
    public override int GetHashCode() => HashCode.Combine(Num, Den);
    public override string ToString() => IsInteger ? Num.ToString(CultureInfo.InvariantCulture) : $"{Num}/{Den}";
}
