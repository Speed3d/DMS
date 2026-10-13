import 'dart:math';

import 'book_table.dart';
import 'table_calc.dart';

export 'table_calc.dart';

/// الجمع الحيّ والمعادلات (ADR-060) والترقيم في المحرّر (ADR-057) — **مرآةُ `TableFormulas` في الخادم**.
///
/// ⚠️ المحرّر يحسب ليُري المستخدم الرقم وهو يكتب، **والخادم يعيد الحساب عند كل طباعة** ولا يثق برقمٍ أرسله العميل —
/// فاختلافٌ بينهما يُصحَّح في الطباعة لا يُطبع خطأً. والحرّاس هنا بالقيم نفسها في اختبارات الخادم، **والأمثلة المشتركة**
/// (`backend/Dms.Tests/Fixtures/table-calc-vectors.json`) يمرّ بها الطرفان.
class BtFormulas {
  BtFormulas._();

  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// رقمٌ من نصّ خلية: بفواصل الآلاف (`1,425,000,000`) وبالكسر (`1,430.33`) وبالأرقام الهندية —
  /// و`null` لأيّ نصٍّ غير رقميٍّ خالص («2 قطعة» · «ـــــ» · فارغ).
  static num? parseNumber(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final s = _normalize(text);
    if (s.isEmpty || '.'.allMatches(s).length > 1 || !RegExp(r'^-?\d*\.?\d+$').hasMatch(s)) return null;
    return num.tryParse(s);
  }

  /// رقمٌ دقيق من نصّ خلية — **مرآةُ `TableFormulas.ParseNumber` في الخادم** (`decimal.TryParse`: إشارةٌ في أوّله وفاصلةٌ
  /// عشرية واحدة) بالتوحيد نفسه للأرقام الهندية والفواصل. الحساب يستعمله لا [parseNumber].
  static BtRational? parseExact(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return BtRational.tryParseDecimal(_normalize(text));
  }

  /// الأرقام الهندية والفارسية ⟵ لاتينية · `٫` ⟵ `.` · وتُحذف فواصل الآلاف والمسافات.
  static String _normalize(String text) {
    final b = StringBuffer();
    for (final ch in text.trim().split('')) {
      final a = _arabicDigits.indexOf(ch);
      final p = _persianDigits.indexOf(ch);
      if (a >= 0) {
        b.write(a);
      } else if (p >= 0) {
        b.write(p);
      } else if (ch == '٫') {
        b.write('.');
      } else if (ch == ',' || ch == '٬' || ch == ' ' || ch == ' ') {
        // فاصل آلاف
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  /// بفواصل الآلاف كما في نموذج المالك — `9,450,000,000` أو `1,430.33`.
  static String format(num value, {required bool decimals}) {
    final neg = value < 0;
    final fixed = value.abs().toStringAsFixed(decimals ? 2 : 0);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${neg ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// يحسب كل الخلايا المحسوبة — **الجمع · المعادلات · الأعمدة المحسوبة** (ولخلية «الحروف» قيمتُها المصدر أو خطؤها) —
  /// مفهرسةً بمعرّف الخلية. القواعد نفسها في الخادم (`TableFormulas.Evaluate`):
  /// * الجمع: كل رقمٍ **فوق** الخلية في العمود المختار حتى العناوين · تُتخطّى الفارغة والنصّية وخلايا الجمع الأخرى ·
  ///   والمدموجة عمودياً تُعدّ مرّةً واحدة · **ويجمع ناتج المعادلات فوقه ويحمل خطأها**.
  /// * المعادلة: كسرٌ دقيق ثم تقريبٌ إلى منزلتين عند حدود الخلية · الفارغة صفر · النصّ خطأ · الدائرة خطأ.
  /// * خلية «الحروف»: نصّها يأتي من الخادم — هنا قيمتُها المصدر أو خطؤها (`text` فارغ).
  static Map<String, BtComputed> evaluate(BtTable t) => _Evaluator(t).run();

  /// خلايا الأعمدة المحسوبة — صفوف البند التي تأخذ معادلة عمودها (لا تُحرَّر يدوياً، ونصّها يولّده الحساب).
  static Set<String> columnTargets(BtTable t) => _Evaluator(t).colTargets.keys.toSet();

  /// القيمة المصدر لخلية «كتابة بالحروف» — من خليةٍ محسوبة أو رقمٍ مكتوب. و`null` إن لم يوجد رقمٌ أو كان المصدر خاطئاً.
  static num? wordsSource(BtTable t, BtWords w, [Map<String, BtComputed>? computed]) {
    final c = (computed ?? evaluate(t))[w.sourceCellId];
    if (c != null) return c.value;
    return parseNumber(t.findCell(w.sourceCellId)?.cell.text);
  }

  /// الترقيم التالي لعمود «ت» (قرار المالك): `4 ⟵ 5` · `17.3 ⟵ 17.4` · `17.9 ⟵ 17.10` — من أقرب رقمٍ فوق الصفّ.
  static String nextNumber(BtTable t, int row) {
    final col = t.numberingCol;
    if (col == null) return '';
    for (var r = row - 1; r >= t.headerRows; r--) {
      final o = t.ownerOf(r, col);
      if (o == null || o.row != r) continue;
      final next = increment(o.cell.text);
      if (next != null) return next;
    }
    return '1';
  }

  /// `4 ⟵ 5` · `17.3 ⟵ 17.4` · `17.9 ⟵ 17.10` — و`null` لما ليس ترقيماً.
  static String? increment(String text) {
    final m = RegExp(r'^(\d+(?:\.\d+)*)$').firstMatch(text.trim());
    if (m == null) return null;
    final parts = m.group(1)!.split('.');
    parts[parts.length - 1] = '${int.parse(parts.last) + 1}';
    return parts.join('.');
  }
}

/// قيمةٌ محسوبة — النصّ كما يُعرض ويُطبع. و[error] رمزُ خطأٍ في معادلة (`calcErrorMessage`) والنصّ عندها `#خطأ`.
class BtComputed {
  const BtComputed(this.text, this.value) : error = null;
  const BtComputed.failed(String this.error)
      : text = kCalcErrorText,
        value = null;
  final String text;
  final num? value;
  final String? error;
  bool get isError => error != null;
}

typedef _Owner = ({int row, int col, BtCell cell});

/// قيمةٌ داخلية: كسرٌ دقيق أو خطأ (أو لا قيمة: عمودٌ محسوبٌ مراجعُه في صفّه فارغةٌ كلُّها).
class _Cv {
  const _Cv(this.value, this.error, this.out);
  final BtRational? value;
  final String? error;
  final BtComputed out;
}

class _Operand {
  const _Operand(this.result, this.blank);
  final BtCalcResult result;
  final bool blank;
}

/// مرآةُ `TableFormulas.Evaluator` في الخادم — **ترتيبٌ بالاعتماد لا بالموضع**: كل خليةٍ تُحسب حين تُطلب أوّل مرّة وتُحفظ،
/// والدائرة خطأ لا تكرارٌ لا ينتهي.
class _Evaluator {
  _Evaluator(this.t)
      : _rows = t.rowCount,
        _cols = t.colCount {
    _owner = List.generate(_rows, (_) => List<_Owner?>.filled(_cols, null));
    for (var i = 0; i < _cols; i++) {
      _colIndex.putIfAbsent(t.cols[i].id, () => i);
    }
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols && c < t.rows[r].cells.length; c++) {
        final cell = t.rows[r].cells[c];
        if (cell == null) continue;
        final o = (row: r, col: c, cell: cell);
        _byId.putIfAbsent(cell.id, () => o);
        for (var rr = r; rr < min(_rows, r + cell.rowSpan); rr++) {
          for (var cc = c; cc < min(_cols, c + cell.colSpan); cc++) {
            _owner[rr][cc] = o;
          }
        }
      }
    }
    for (final e in _byId.entries) {
      final calc = e.value.cell.calc;
      if (calc != null) _cellExprs[e.key] = BtExpression.tryParse(calc.expr);
    }
    // الأعمدة المحسوبة: كلُّ صفّ بندٍ مؤهَّل يأخذ معادلة عموده.
    for (var c = 0; c < _cols; c++) {
      final calc = t.cols[c].calc;
      if (calc == null) continue;
      final expr = BtExpression.tryParse(calc.expr);
      for (var r = t.headerRows; r < _rows; r++) {
        final cell = _columnTarget(r, c, expr);
        if (cell != null) colTargets[cell.id] = (row: r, expr: expr);
      }
    }
  }

  final BtTable t;
  final int _rows, _cols;
  late final List<List<_Owner?>> _owner;
  final _byId = <String, _Owner>{};
  final _colIndex = <String, int>{};
  final _memo = <String, _Cv>{};
  final _visiting = <String>{};
  final _cellExprs = <String, BtExpression?>{};
  final colTargets = <String, ({int row, BtExpression? expr})>{};

  /// خلية العمود المحسوب في الصفّ [r] — أو `null` إن لم يكن صفَّ بند (القاعدة نفسها في الخادم `ColumnTarget`):
  /// خليةٌ مفردةٌ تبدأ هنا بلا صيغةٍ ولا حروفٍ ولا معادلة · والصفّ ليس صفَّ مجموع · وكلُّ عمودٍ تشير إليه المعادلة
  /// خليةٌ مفردةٌ تبدأ في الصفّ نفسه (فصفُّ عنوانٍ مدموج يُتخطّى ولا يصير خطأً).
  BtCell? _columnTarget(int r, int c, BtExpression? expr) {
    final o = _owner[r][c];
    if (o == null || o.row != r || o.col != c) return null;
    final cell = o.cell;
    if (cell.rowSpan != 1 || cell.colSpan != 1 || cell.formula != null || cell.words != null || cell.calc != null) return null;
    if (t.rows[r].cells.any((x) => x != null && (x.formula != null || x.words != null))) return null;
    if (expr == null) return cell; // معادلةٌ لا تُقرأ ⟵ خطأٌ ظاهر في كل صفّ بند
    for (final id in expr.refs) {
      final rc = _colIndex[id];
      if (rc == null) continue; // عمودٌ حُذف ⟵ خطأ «مرجع» يظهر
      final ro = _owner[r][rc];
      if (ro == null || ro.row != r || ro.col != rc || ro.cell.rowSpan != 1 || ro.cell.colSpan != 1) return null;
    }
    return cell;
  }

  bool _isComputed(BtCell c) => c.formula != null || c.words != null || c.calc != null || colTargets.containsKey(c.id);

  Map<String, BtComputed> run() => {
        for (final e in _byId.entries)
          if (_isComputed(e.value.cell)) e.key: _value(e.key).out,
      };

  _Cv _value(String id) {
    final hit = _memo[id];
    if (hit != null) return hit;
    if (!_visiting.add(id)) return _err(kCalcErrCycle);
    final o = _byId[id]!;
    final cell = o.cell;
    final _Cv v;
    if (cell.formula != null) {
      v = _sum(o.row, cell);
    } else if (cell.words != null) {
      v = _words(cell);
    } else if (cell.calc != null) {
      v = _calc(_cellExprs[id], _cellRef, blankable: false);
    } else {
      v = _calc(colTargets[id]!.expr, (colId) => _columnRef(colId, o.row), blankable: true);
    }
    _visiting.remove(id);
    _memo[id] = v;
    return v;
  }

  static _Cv _err(String code) => _Cv(null, code, BtComputed.failed(code));

  /// الجمع — كما في الخادم: الكسر من نصّ الخلية أو من معادلةٍ غير صحيحة، والقيمة غير مقرَّبة لمن يعتمد عليها.
  _Cv _sum(int r, BtCell cell) {
    final col = cell.formula!.col;
    var sum = BtRational.zero;
    var decimals = false;
    for (var i = t.headerRows; i < r; i++) {
      if (col < 0 || col >= _cols) continue;
      final o = _owner[i][col];
      if (o == null || o.row != i) continue;
      if (o.cell.formula != null || o.cell.words != null) continue;
      if (o.cell.calc != null || colTargets.containsKey(o.cell.id)) {
        final cv = _value(o.cell.id);
        if (cv.error != null) return _err(cv.error!);
        final rv = cv.value;
        if (rv == null) continue; // صفٌّ محسوبٌ فارغ
        sum = sum + rv;
        if (!rv.isInteger) decimals = true;
        continue;
      }
      final text = o.cell.text;
      final v = BtFormulas.parseExact(text);
      if (v == null) continue;
      sum = sum + v;
      if (text.contains('.') || text.contains('٫')) decimals = true;
    }
    return _Cv(sum, null, BtComputed(sum.format(decimals: decimals), sum.toNum()));
  }

  /// مصدر «الحروف» — من خليةٍ محسوبة أو رقمٍ مكتوب. ومصدرٌ خاطئ يجعلها خاطئة (فيُمنع الاعتماد).
  _Cv _words(BtCell cell) {
    final w = cell.words!;
    BtRational? value;
    final src = _byId[w.sourceCellId];
    if (src != null) {
      if (_isComputed(src.cell)) {
        final cv = _value(w.sourceCellId);
        if (cv.error != null) return _err(cv.error!);
        value = cv.value;
      } else {
        value = BtFormulas.parseExact(src.cell.text);
      }
    }
    return _Cv(value, null, BtComputed('', value?.toNum()));
  }

  /// المعادلة: الناتج يُقرَّب إلى منزلتين **عند حدود الخلية** — وما يعتمد عليها يقرأ الرقم الذي يراه الإنسان.
  /// [blankable]: عمودٌ محسوب — صفٌّ مراجعُه فارغةٌ كلُّها يبقى فارغاً لا «0».
  _Cv _calc(BtExpression? expr, _Operand Function(String id) resolve, {required bool blankable}) {
    if (expr == null) return _err(kCalcErrRef);
    var allBlank = expr.refs.isNotEmpty;
    final r = expr.evaluate((id) {
      final o = resolve(id);
      if (!o.blank) allBlank = false;
      return o.result;
    });
    if (r.error != null) return _err(r.error!);
    if (blankable && allBlank) return const _Cv(null, null, BtComputed('', null));
    final value = r.value!.roundCents();
    if (value.absGreaterThan(kCalcMax)) return _err(kCalcErrBig);
    return _Cv(value, null, BtComputed(value.format(decimals: !value.isInteger), value.toNum()));
  }

  _Operand _cellRef(String id) {
    final x = _byId[id];
    return x != null ? _read(x.cell) : const _Operand(BtCalcResult.fail(kCalcErrRef), false);
  }

  _Operand _columnRef(String colId, int row) {
    final c = _colIndex[colId];
    final o = c == null ? null : _owner[row][c];
    if (o == null) return const _Operand(BtCalcResult.fail(kCalcErrRef), false);
    return _read(o.cell);
  }

  _Operand _read(BtCell cell) {
    if (cell.words != null) return const _Operand(BtCalcResult.fail(kCalcErrWords), false);
    if (_isComputed(cell)) {
      final cv = _value(cell.id);
      if (cv.error != null) return _Operand(BtCalcResult.fail(cv.error!), false);
      final v = cv.value;
      return v != null ? _Operand(BtCalcResult.ok(v), false) : _Operand(BtCalcResult.ok(BtRational.zero), true);
    }
    final text = cell.text;
    if (text.trim().isEmpty) return _Operand(BtCalcResult.ok(BtRational.zero), true); // الفارغة صفر (قرار المالك)
    final n = BtFormulas.parseExact(text);
    return n != null ? _Operand(BtCalcResult.ok(n), false) : const _Operand(BtCalcResult.fail(kCalcErrText), false);
  }
}
