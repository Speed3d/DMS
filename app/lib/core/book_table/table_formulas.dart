import 'book_table.dart';

/// الجمع الحيّ والترقيم في المحرّر (ADR-057) — **مرآةُ `TableFormulas` في الخادم**.
///
/// ⚠️ المحرّر يحسب ليُري المستخدم الرقم وهو يكتب، **والخادم يعيد الحساب عند كل طباعة** ولا يثق برقمٍ أرسله العميل —
/// فاختلافٌ بينهما يُصحَّح في الطباعة لا يُطبع خطأً. والحرّاس هنا بالقيم نفسها في اختبارات الخادم.
class BtFormulas {
  BtFormulas._();

  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// رقمٌ من نصّ خلية: بفواصل الآلاف (`1,425,000,000`) وبالكسر (`1,430.33`) وبالأرقام الهندية —
  /// و`null` لأيّ نصٍّ غير رقميٍّ خالص («2 قطعة» · «ـــــ» · فارغ).
  static num? parseNumber(String? text) {
    if (text == null || text.trim().isEmpty) return null;
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
    final s = b.toString();
    if (s.isEmpty || '.'.allMatches(s).length > 1 || !RegExp(r'^-?\d*\.?\d+$').hasMatch(s)) return null;
    return num.tryParse(s);
  }

  /// بفواصل الآلاف كما في نموذج المالك — `9,450,000,000` أو `1,430.33`.
  static String format(num value, {required bool decimals}) {
    final neg = value < 0;
    final fixed = value.abs().toStringAsFixed(decimals ? 2 : 0);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${neg ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// قيم خلايا الجمع — مفهرسةً بمعرّف الخلية. القاعدة نفسها في الخادم:
  /// كل رقمٍ **فوق** الخلية في العمود المختار حتى العناوين · تُتخطّى الفارغة والنصّية وخلايا الجمع الأخرى ·
  /// والمدموجة عمودياً تُعدّ مرّةً واحدة.
  static Map<String, BtComputed> evaluate(BtTable t) {
    final out = <String, BtComputed>{};
    for (final s in t.masters) {
      final f = s.cell.formula;
      if (f == null) continue;
      num sum = 0;
      var decimals = false;
      for (var i = t.headerRows; i < s.row; i++) {
        final o = t.ownerOf(i, f.col);
        if (o == null || o.row != i || o.cell.formula != null || o.cell.words != null) continue;
        final text = o.cell.text;
        final v = parseNumber(text);
        if (v == null) continue;
        sum += v;
        if (text.contains('.') || text.contains('٫')) decimals = true;
      }
      out[s.cell.id] = BtComputed(format(sum, decimals: decimals), sum);
    }
    return out;
  }

  /// القيمة المصدر لخلية «كتابة بالحروف» — من خلية جمعٍ محسوبة أو رقمٍ مكتوب.
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

/// قيمةٌ محسوبة — النصّ كما يُعرض ويُطبع.
class BtComputed {
  const BtComputed(this.text, this.value);
  final String text;
  final num value;
}
