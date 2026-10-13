/// معادلات الجداول (ADR-060) — **مرآةُ `Rational` و`TableExpression` في الخادم سطراً بسطر**.
///
/// 🔑 المحرّر يحسب ليُري الناتج وهو يُكتب، والخادم يعيد الحساب عند كل طباعة — **ويجب أن يتطابقا رقماً برقم**.
/// لذلك الحساب **بكسرٍ دقيق** (`BigInt` هنا ⟷ `BigInteger` هناك) لا بـ`double`، والتقريب مرّةً واحدة عند حدود الخلية،
/// والأمثلة المشتركة (`backend/Dms.Tests/Fixtures/table-calc-vectors.json`) يمرّ بها الطرفان.
library;

// ─────────────────────────── رموز الأخطاء ───────────────────────────
// ثابتةٌ يتطابق عليها الخادم والمحرّر.

const kCalcErrDivZero = 'div0';
const kCalcErrText = 'text';
const kCalcErrRef = 'ref';
const kCalcErrCycle = 'cycle';
const kCalcErrWords = 'words';
const kCalcErrBig = 'big';

/// ما يُعرض ويُطبع في خليةٍ معادلتُها خاطئة.
const kCalcErrorText = '#خطأ';

String calcErrorMessage(String code) => switch (code) {
      kCalcErrDivZero => 'قسمة على صفر',
      kCalcErrText => 'مرجعٌ إلى خليةٍ فيها نصٌّ لا رقم',
      kCalcErrRef => 'مرجعٌ إلى خليةٍ أو عمودٍ لم يعد موجوداً',
      kCalcErrCycle => 'معادلةٌ دائرية (تعتمد على نفسها)',
      kCalcErrWords => 'مرجعٌ إلى خلية «كتابة بالحروف»',
      kCalcErrBig => 'الناتج أكبر من الحدّ المسموح',
      _ => 'خطأ في المعادلة',
    };

/// حرف العمود — `A` · `B` · … · `Z` · `AA` (من بداية الجدول).
String btColumnLetter(int index) {
  var s = '';
  for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
  }
  return s;
}

/// أكبر ناتجٍ مقبول لمعادلة (بالقيمة المطلقة) — ألف تريليون.
final kCalcMax = BigInt.from(10).pow(15);

// ─────────────────────────── الكسر الدقيق ───────────────────────────

/// عددٌ كسريٌّ دقيق — بسطٌ ومقامٌ صحيحان، مختزَلٌ دائماً والمقام موجب.
class BtRational {
  factory BtRational(BigInt n, BigInt d) {
    if (d == BigInt.zero) throw UnsupportedError('مقامٌ صفر');
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.abs().gcd(d);
    if (g > BigInt.one) {
      n = n ~/ g;
      d = d ~/ g;
    }
    return BtRational._(n, d);
  }

  const BtRational._(this.n, this.d);

  final BigInt n;
  final BigInt d;

  static final zero = BtRational._(BigInt.zero, BigInt.one);

  factory BtRational.integer(int v) => BtRational._(BigInt.from(v), BigInt.one);

  /// من نصٍّ عشريٍّ نظيف (`-12.50`) — بلا فواصل ولا أرقامٍ هندية (تُوحَّد قبله).
  static BtRational? tryParseDecimal(String s) {
    final m = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(s);
    if (m == null) return null;
    final whole = m.group(2)!;
    final frac = m.group(3) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    // decimal في الخادم 28–29 رقماً — وما فوقه لا يُقرأ رقماً هناك فلا يُقرأ هنا
    if ((whole + frac).replaceFirst(RegExp(r'^0+'), '').length > 28) return null;
    var n = BigInt.parse('${whole.isEmpty ? '0' : whole}$frac');
    if (m.group(1) == '-') n = -n;
    return BtRational(n, BigInt.from(10).pow(frac.length));
  }

  bool get isZero => n == BigInt.zero;
  bool get isInteger => d == BigInt.one;

  BtRational operator +(BtRational b) => BtRational(n * b.d + b.n * d, d * b.d);
  BtRational operator -(BtRational b) => BtRational(n * b.d - b.n * d, d * b.d);
  BtRational operator *(BtRational b) => BtRational(n * b.n, d * b.d);
  BtRational operator /(BtRational b) => BtRational(n * b.d, d * b.n);
  BtRational operator -() => BtRational._(-n, d);

  /// تقريبٌ إلى منزلتين — **النصف بعيداً عن الصفر** (`2.345 ⟵ 2.35` · `-2.345 ⟵ -2.35`)، كالخادم والإكسل.
  BtRational roundCents() {
    final scaled = n * BigInt.from(100);
    var q = scaled.abs() ~/ d;
    final rem = scaled.abs().remainder(d);
    if (rem * BigInt.two >= d) q += BigInt.one;
    return BtRational(scaled.isNegative ? -q : q, BigInt.from(100));
  }

  bool absGreaterThan(BigInt limit) => n.abs() > limit * d;

  /// للعرض والتفقيط — صحيحٌ إن أمكن (فيُكتب `1000` لا `1000.0`).
  num toNum() => isInteger && n.isValidInt ? n.toInt() : n / d;

  /// بفواصل الآلاف كما في نموذج المالك — `9,450,000,000` أو `1,430.33` (يُقرَّب إلى منزلتين أوّلاً).
  String format({required bool decimals}) {
    // التقريب إلى المنازل المطلوبة مباشرةً من القيمة (النصف بعيداً عن الصفر) — كـN0/N2 في الخادم
    final scale = BigInt.from(decimals ? 100 : 1);
    final scaled = n.abs() * scale;
    var q = scaled ~/ d;
    if (scaled.remainder(d) * BigInt.two >= d) q += BigInt.one;
    final whole = q ~/ scale;
    final frac = (q % scale).toInt();
    final neg = n.isNegative && q > BigInt.zero;
    final w = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${neg ? '-' : ''}$w${decimals ? '.${frac.toString().padLeft(2, '0')}' : ''}';
  }

  @override
  bool operator ==(Object other) => other is BtRational && other.n == n && other.d == d;

  @override
  int get hashCode => Object.hash(n, d);

  @override
  String toString() => isInteger ? '$n' : '$n/$d';
}

// ─────────────────────────── المعادلة ───────────────────────────

/// خطأٌ في كتابة المعادلة — رسالته عربية كرسالة الخادم (`ValidationException`).
class BtExprError implements Exception {
  const BtExprError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// نتيجة الحساب: قيمةٌ أو رمزُ خطأ.
class BtCalcResult {
  const BtCalcResult.ok(BtRational this.value) : error = null;
  const BtCalcResult.fail(String this.error) : value = null;
  final BtRational? value;
  final String? error;
}

/// معادلةٌ مخزَّنة: `{c8f2}*{c9a1}+2` — المرجع **معرّفٌ** بين قوسين معقوفين، والعمليات `+ − × ÷` والأقواس.
class BtExpression {
  BtExpression._(this._root, this.refs);

  static const maxLength = 500;
  static const maxRefs = 50;
  static const maxDepth = 20;
  static const maxNumberDigits = 18;
  static const maxIdLength = 64;

  final _Node _root;

  /// المعرّفات المشار إليها — بلا تكرار، بترتيب ظهورها.
  final List<String> refs;

  /// يقرأ معادلةً مخزَّنة — أو يرمي [BtExprError] بالرسالة نفسها التي يردّها الخادم.
  static BtExpression parse(String? text) {
    if (text == null || text.trim().isEmpty) throw const BtExprError('المعادلة فارغة.');
    if (text.length > maxLength) throw const BtExprError('المعادلة أطول من الحدّ ($maxLength حرفاً).');
    final p = _Parser(text);
    final root = p.expression(0);
    p.skipSpaces();
    if (!p.atEnd) throw const BtExprError('المعادلة غير مكتملة أو فيها رمزٌ غير مفهوم.');
    if (p.refs.length > maxRefs) throw const BtExprError('المعادلة تشير إلى خلايا أكثر من الحدّ ($maxRefs).');
    return BtExpression._(root, List.unmodifiable(p.refs));
  }

  static BtExpression? tryParse(String? text) {
    try {
      return parse(text);
    } on BtExprError {
      return null;
    }
  }

  BtCalcResult evaluate(BtCalcResult Function(String id) resolve) => _eval(_root, resolve);

  static BtCalcResult _eval(_Node n, BtCalcResult Function(String id) resolve) {
    switch (n) {
      case _Num():
        return BtCalcResult.ok(n.value);
      case _Ref():
        return resolve(n.id);
      case _Neg():
        final v = _eval(n.inner, resolve);
        return v.error == null ? BtCalcResult.ok(-v.value!) : v;
      case _Bin():
        final l = _eval(n.left, resolve);
        if (l.error != null) return l;
        final r = _eval(n.right, resolve);
        if (r.error != null) return r;
        final x = l.value!, y = r.value!;
        return switch (n.op) {
          '+' => BtCalcResult.ok(x + y),
          '-' => BtCalcResult.ok(x - y),
          '*' => BtCalcResult.ok(x * y),
          _ => y.isZero ? const BtCalcResult.fail(kCalcErrDivZero) : BtCalcResult.ok(x / y),
        };
    }
  }
}

sealed class _Node {}

class _Num extends _Node {
  _Num(this.value);
  final BtRational value;
}

class _Ref extends _Node {
  _Ref(this.id);
  final String id;
}

class _Neg extends _Node {
  _Neg(this.inner);
  final _Node inner;
}

class _Bin extends _Node {
  _Bin(this.op, this.left, this.right);
  final String op;
  final _Node left, right;
}

//  expr  := term  (('+' | '-') term)*
//  term  := unary (('*' | '/') unary)*
//  unary := ('-' | '+') unary | primary
//  primary := number | '{' id '}' | '(' expr ')'
class _Parser {
  _Parser(this.s);
  final String s;
  var _i = 0;
  final refs = <String>[];

  bool get atEnd => _i >= s.length;

  static bool _space(String ch) => ch.trim().isEmpty;

  void skipSpaces() {
    while (_i < s.length && _space(s[_i])) {
      _i++;
    }
  }

  String? _peek() {
    skipSpaces();
    return _i < s.length ? s[_i] : null;
  }

  /// رمز العملية بصيغته الموحّدة — والمحرّر قد يكتب ×/÷/− فتُقبل كذلك.
  static String? _op(String c) => switch (c) {
        '+' => '+',
        '-' || '−' => '-',
        '*' || '×' => '*',
        '/' || '÷' => '/',
        _ => null,
      };

  static Never _depth() => throw const BtExprError('المعادلة متداخلةٌ أكثر من الحدّ (${BtExpression.maxDepth} مستوى).');

  _Node expression(int depth) {
    if (depth > BtExpression.maxDepth) _depth();
    var left = _term(depth);
    for (var c = _peek(); c != null && (_op(c) == '+' || _op(c) == '-'); c = _peek()) {
      _i++;
      left = _Bin(_op(c)!, left, _term(depth));
    }
    return left;
  }

  _Node _term(int depth) {
    var left = _unary(depth);
    for (var c = _peek(); c != null && (_op(c) == '*' || _op(c) == '/'); c = _peek()) {
      _i++;
      left = _Bin(_op(c)!, left, _unary(depth));
    }
    return left;
  }

  _Node _unary(int depth) {
    if (depth > BtExpression.maxDepth) _depth();
    final c = _peek();
    if (c != null && (_op(c) == '+' || _op(c) == '-')) {
      _i++;
      final inner = _unary(depth + 1);
      return _op(c) == '-' ? _Neg(inner) : inner;
    }
    return _primary(depth);
  }

  _Node _primary(int depth) {
    final c = _peek() ?? (throw const BtExprError('المعادلة تنتهي قبل أن تكتمل.'));
    if (c == '(') {
      _i++;
      final inner = expression(depth + 1);
      if (_peek() != ')') throw const BtExprError('قوسٌ مفتوح لم يُغلق في المعادلة.');
      _i++;
      return inner;
    }
    if (c == '{') {
      final end = s.indexOf('}', _i + 1);
      if (end < 0) throw const BtExprError('مرجعٌ غير مكتمل في المعادلة.');
      final id = s.substring(_i + 1, end);
      if (id.isEmpty || id.length > BtExpression.maxIdLength || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
        throw const BtExprError('مرجعٌ غير صالح في المعادلة.');
      }
      _i = end + 1;
      if (!refs.contains(id)) refs.add(id);
      return _Ref(id);
    }
    if (_digit(c) != null || c == '.' || c == '٫') return _Num(_number());
    throw BtExprError('رمزٌ غير مفهوم في المعادلة «$c».');
  }

  static int? _digit(String ch) {
    final u = ch.codeUnitAt(0);
    if (u >= 0x30 && u <= 0x39) return u - 0x30; // 0–9
    if (u >= 0x660 && u <= 0x669) return u - 0x660; // ٠–٩
    if (u >= 0x6F0 && u <= 0x6F9) return u - 0x6F0; // ۰–۹
    return null;
  }

  BtRational _number() {
    final digits = StringBuffer();
    var scale = -1;
    while (_i < s.length) {
      final ch = s[_i];
      final d = _digit(ch);
      if (d != null) {
        digits.write(d);
        if (scale >= 0) scale++;
      } else if (ch == '.' || ch == '٫') {
        if (scale >= 0) throw const BtExprError('رقمٌ فيه فاصلتان عشريتان في المعادلة.');
        scale = 0;
      } else if (ch == ',' || ch == '٬') {
        // فاصل آلاف
      } else {
        break;
      }
      _i++;
    }
    if (digits.isEmpty) throw const BtExprError('رقمٌ غير صالح في المعادلة.');
    if (digits.length > BtExpression.maxNumberDigits) {
      throw const BtExprError('رقمٌ أطول من الحدّ (${BtExpression.maxNumberDigits} رقماً) في المعادلة.');
    }
    return BtRational(BigInt.parse(digits.toString()), BigInt.from(10).pow(scale < 0 ? 0 : scale));
  }
}
