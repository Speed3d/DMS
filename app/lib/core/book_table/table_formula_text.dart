import 'book_table.dart';
import 'table_formulas.dart';
import 'table_ops.dart';

/// المعادلة كما يراها المستخدم ⟷ كما تُخزَّن (ADR-060).
///
/// 📦 **تُخزَّن بالمعرّفات** (`{c8f2}*{c9a1}`) فإدراجُ صفٍّ أو عمودٍ لا يغيّر ما تشير إليه — **وتُعرض بحروف الأعمدة وأرقام
/// الصفوف** كالإكسل (`B3 × C3`)، وفي «العمود المحسوب» بالحرف وحده (`C × D`). الحرف من بداية الجدول (A أوّل عمود — يميناً في
/// الجدول العربيّ) والرقم من أوّل صفّ، والخلية المدموجة باسم ركنها الأوّل.
class BtFormulaText {
  BtFormulaText._();

  /// ما يظهر مكان مرجعٍ حُذفت خليته أو عموده — ولا يُقبل عند الحفظ حتى يُكتب من جديد.
  static const deleted = '#مرجع';

  static final _stored = RegExp(r'\{([A-Za-z0-9_-]+)\}');
  static final _token = RegExp(r'[A-Za-z]+[0-9٠-٩۰-۹]*');

  /// عنوان الخلية — `D5` (العمود D · الصفّ الخامس).
  static String address(int row, int col) => '${btColumnLetter(col)}${row + 1}';

  /// المعادلة المخزَّنة كما تُعرض — `{c1}*{c2}` ⟵ `B3 × C3`.
  static String toDisplay(BtTable t, String expr, {required bool column}) {
    final shown = expr.replaceAllMapped(_stored, (m) {
      final id = m.group(1)!;
      if (column) {
        final i = t.cols.indexWhere((c) => c.id == id);
        return i < 0 ? deleted : btColumnLetter(i);
      }
      final s = t.findCell(id);
      return s == null ? deleted : address(s.row, s.col);
    });
    return shown.replaceAll('*', ' × ').replaceAll('/', ' ÷ ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// المعادلة المكتوبة بالشكل المخزَّن — أو [BtExprError] برسالةٍ عربية تقول ما الخطأ وأين.
  static String toStorage(BtTable t, String display, {required bool column}) {
    var s = display.trim();
    if (s.startsWith('=')) s = s.substring(1).trim();
    if (s.isEmpty) throw const BtExprError('المعادلة فارغة.');
    if (s.contains(deleted)) throw const BtExprError('في المعادلة مرجعٌ إلى خليةٍ أو عمودٍ حُذف — اكتبه من جديد.');
    final out = s.replaceAllMapped(_token, (m) {
      final tok = m.group(0)!.toUpperCase();
      final letters = RegExp(r'^[A-Z]+').firstMatch(tok)!.group(0)!;
      final digits = _latinDigits(tok.substring(letters.length));
      final col = _columnIndex(letters);
      if (column) {
        if (digits.isNotEmpty) throw BtExprError('في معادلة العمود يُكتب حرف العمود وحده ($letters لا $tok).');
        if (col >= t.colCount) throw BtExprError('العمود «$letters» غير موجود في الجدول.');
        return '{${t.cols[col].id}}';
      }
      if (digits.isEmpty) throw BtExprError('اكتب المرجع بحرف العمود ورقم الصفّ (مثل ${letters}2) — أو اختر «للعمود كلّه».');
      final row = int.parse(digits) - 1;
      final owner = row < 0 || col >= t.colCount ? null : t.ownerOf(row, col);
      if (owner == null) throw BtExprError('الخلية «$letters${row + 1}» غير موجودة في الجدول.');
      return '{${owner.cell.id}}';
    });
    final stored = out.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-').replaceAll(RegExp(r'\s+'), '');
    BtExpression.parse(stored);   // الفحص نفسه الذي يجريه الخادم
    return stored;
  }

  /// المراجع في معادلةٍ مكتوبة (ولو لم تكتمل بعد) — معرّفات خلايا، أو معرّفات أعمدة في معادلة العمود. لتلوينها على الجدول.
  static Set<String> refsOf(BtTable t, String display, {required bool column}) {
    final out = <String>{};
    for (final m in _token.allMatches(display)) {
      final tok = m.group(0)!.toUpperCase();
      final letters = RegExp(r'^[A-Z]+').firstMatch(tok)!.group(0)!;
      final digits = _latinDigits(tok.substring(letters.length));
      final col = _columnIndex(letters);
      if (col >= t.colCount) continue;
      if (column) {
        if (digits.isEmpty) out.add(t.cols[col].id);
      } else if (digits.isNotEmpty) {
        final o = t.ownerOf(int.parse(digits) - 1, col);
        if (o != null) out.add(o.cell.id);
      }
    }
    return out;
  }

  /// يحوّل المعادلة المكتوبة بين «خلية» و«عمودٍ محسوب»: `B3 × C3` ⟷ `B × C` (والصفّ في الاتجاه المعاكس صفُّ [row]).
  static String switchMode(String display, {required bool toColumn, required int row}) => toColumn
      ? display.replaceAllMapped(_token, (m) => RegExp(r'^[A-Za-z]+').firstMatch(m.group(0)!)!.group(0)!.toUpperCase())
      : display.replaceAllMapped(_token, (m) {
          final tok = m.group(0)!.toUpperCase();
          return RegExp(r'\d').hasMatch(_latinDigits(tok)) ? tok : '$tok${row + 1}';
        });

  /// ناتج معادلةٍ قبل تطبيقها — للمعاينة الحيّة. و`null` لعمودٍ لا صفوف بنودٍ فيه بعد.
  /// في العمود المحسوب: ناتج صفّ [row] إن كان صفَّ بند، وإلا أوّلُ صفّ بند.
  static BtComputed? preview(BtTable t, String stored, {String? cellId, int? col, int row = 0}) {
    if (col != null) {
      final next = BtOps.setColumnCalc(t, col, stored);
      final targets = BtFormulas.columnTargets(next);
      final computed = BtFormulas.evaluate(next);
      final here = next.ownerOf(row, col);
      if (here != null && targets.contains(here.cell.id)) return computed[here.cell.id];
      for (final s in next.masters) {
        if (s.col == col && targets.contains(s.cell.id)) return computed[s.cell.id];
      }
      return null;
    }
    return BtFormulas.evaluate(BtOps.setCalc(t, cellId!, stored))[cellId];
  }

  static int _columnIndex(String letters) {
    var n = 0;
    for (final u in letters.codeUnits) {
      n = n * 26 + (u - 64);
      if (n > 1000) return 1000;   // أبعد من أيّ جدول — يُرفض «غير موجود» بلا فيض
    }
    return n - 1;
  }

  static String _latinDigits(String s) => String.fromCharCodes(s.runes.map((u) => switch (u) {
        >= 0x660 && <= 0x669 => u - 0x660 + 0x30,
        >= 0x6F0 && <= 0x6F9 => u - 0x6F0 + 0x30,
        _ => u,
      }));
}
