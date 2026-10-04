import 'dart:math';

/// جدولٌ داخل متن الكتاب الصادر (ADR-057) — **مرآةُ `Dms.Domain.BookTables.BookTable` حقلاً بحقل**.
///
/// 🔑 الشكل نفسه في المحرّر والخادم: الخادم يقرأ هذا النموذج (لا HTML جداول حرّ) فيفحصه بقواعده ويرسمه.
/// والفرق الوحيد أن الخلية هنا تحمل **Delta** (مصدر التحرير بالتنسيق المختلط)، ويُولَّد منها `html` عند الحفظ
/// (`table_serializer.dart`).
///
/// ⚠️ الأسماء ببادئة `Bt` لأن Flutter يملك `Table` و`TableRow` و`TableCell` — والخلط بينها يكسر البناء.
class BtTable {
  BtTable({
    required this.id,
    this.dir = 'rtl',
    this.widthPct = 100,
    this.align = 'center',
    this.borderWidthPt = 0.75,
    this.borderColor = '#000000',
    this.headerRows = 0,
    this.repeatHeader = true,
    this.numberingCol,
    required this.cols,
    required this.rows,
  });

  static const int version = 1;

  final String id;
  String dir;
  int widthPct;
  String align;
  double borderWidthPt;
  String borderColor;
  int headerRows;
  bool repeatHeader;
  int? numberingCol;
  final List<BtCol> cols;
  final List<BtRow> rows;

  int get rowCount => rows.length;
  int get colCount => cols.length;
  bool get rtl => dir != 'ltr';

  /// نسخةٌ عميقة — العمليات تعمل على نسخة وتعيدها (فالتراجع ممكنٌ بحفظ السابقة).
  BtTable copy() => BtTable(
        id: id,
        dir: dir,
        widthPct: widthPct,
        align: align,
        borderWidthPt: borderWidthPt,
        borderColor: borderColor,
        headerRows: headerRows,
        repeatHeader: repeatHeader,
        numberingCol: numberingCol,
        cols: [for (final c in cols) c.copy()],
        rows: [for (final r in rows) r.copy()],
      );

  /// الخلية التي تملك الخانة (r, c) — بدايتها وموضعها — أو `null` إن كانت الخانة خارج الجدول.
  BtSlot? ownerOf(int r, int c) {
    if (r < 0 || c < 0 || r >= rowCount || c >= colCount) return null;
    for (var rr = r; rr >= 0; rr--) {
      for (var cc = c; cc >= 0; cc--) {
        final cell = rows[rr].cells[cc];
        if (cell != null && rr + cell.rowSpan > r && cc + cell.colSpan > c) return BtSlot(rr, cc, cell);
      }
    }
    return null;
  }

  /// كل الخلايا الحقيقية بمواضعها — بترتيب الصفوف ثم الأعمدة.
  Iterable<BtSlot> get masters sync* {
    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < colCount; c++) {
        final cell = rows[r].cells[c];
        if (cell != null) yield BtSlot(r, c, cell);
      }
    }
  }

  BtSlot? findCell(String cellId) {
    for (final s in masters) {
      if (s.cell.id == cellId) return s;
    }
    return null;
  }
}

/// خليةٌ بموضع بدايتها.
class BtSlot {
  const BtSlot(this.row, this.col, this.cell);
  final int row;
  final int col;
  final BtCell cell;
}

class BtCol {
  BtCol({required this.id, this.weight = 1});
  final String id;
  double weight;
  BtCol copy() => BtCol(id: id, weight: weight);
}

class BtRow {
  BtRow({required this.id, required this.cells});
  final String id;

  /// خانةٌ لكل عمود — و`null` خانةٌ يغطّيها دمجٌ من خليةٍ قبلها.
  final List<BtCell?> cells;
  BtRow copy() => BtRow(id: id, cells: [for (final c in cells) c?.copy()]);
}

class BtCell {
  BtCell({
    required this.id,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.bg,
    this.vAlign = 'middle',
    List<Map<String, dynamic>>? delta,
    this.formula,
    this.words,
    this.textStyle,
  }) : delta = delta ?? emptyDelta();

  final String id;
  int rowSpan;
  int colSpan;
  String? bg;
  String vAlign;

  /// نصّ الخلية بتنسيقٍ مختلط (Quill Delta) — ينتهي دائماً بسطرٍ جديد كما يشترط Quill.
  List<Map<String, dynamic>> delta;
  BtFormula? formula;
  BtWords? words;

  /// تنسيق النصّ للخلية الفارغة (عريض · حجم · خط …) — يُطبَّق على ما يُكتب أو يُلصق فيها.
  ///
  /// 🐛 **Quill لا يحفظ تنسيقاً بلا نصّ**: خليةُ بندٍ عريضة في جدول الفاتورة كانت تفقد عريضها حين تفرغ، فيُلصق فيها
  /// نصٌّ رفيع (كشفته معاينةُ عقد الواجهة). Word يحفظه على علامة الفقرة؛ هنا يُحفظ على الخلية. **للمحرّر وحده** —
  /// لا يُرسَل للطباعة (الخادم يقرأ `html` الخلية).
  Map<String, dynamic>? textStyle;

  static List<Map<String, dynamic>> emptyDelta() => [
        {'insert': '\n'}
      ];

  BtCell copy() => BtCell(
        id: id,
        rowSpan: rowSpan,
        colSpan: colSpan,
        bg: bg,
        vAlign: vAlign,
        delta: [for (final op in delta) _deepCopy(op)],
        formula: formula?.copy(),
        words: words?.copy(),
        textStyle: textStyle == null ? null : Map<String, dynamic>.from(textStyle!),
      );

  /// تنسيق أوّل جزءٍ نصّيّ — أو المحفوظ للخلية الفارغة.
  Map<String, dynamic>? get inlineStyle {
    for (final op in delta) {
      final ins = op['insert'];
      final a = op['attributes'];
      if (ins is String && ins.trim().isNotEmpty) return a is Map ? Map<String, dynamic>.from(a) : textStyle;
    }
    return textStyle;
  }

  /// النصّ الخالص (بلا تنسيق) — للأرقام والجمع والترقيم والمقارنة.
  String get text {
    final b = StringBuffer();
    for (final op in delta) {
      final ins = op['insert'];
      if (ins is String) b.write(ins);
    }
    return b.toString().replaceAll(RegExp(r'\n+$'), '').trim();
  }

  bool get isEmpty => text.isEmpty;
}

/// صيغة الخلية — `sum`: كل رقمٍ فوقها في العمود [col] حتى صفوف العناوين.
class BtFormula {
  BtFormula({this.type = 'sum', required this.col});
  final String type;
  int col;
  BtFormula copy() => BtFormula(type: type, col: col);
}

/// «كتابة بالحروف»: نصٌّ يولّده الخادم من رقم خليةٍ أخرى، بين «قبل» و«بعد» يكتبهما المستخدم.
class BtWords {
  BtWords({required this.sourceCellId, this.currency = 'IQD', this.prefix, this.suffix});
  String sourceCellId;
  String currency;
  String? prefix;
  String? suffix;
  BtWords copy() => BtWords(sourceCellId: sourceCellId, currency: currency, prefix: prefix, suffix: suffix);
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) => {
      for (final e in m.entries)
        e.key: e.value is Map<String, dynamic>
            ? _deepCopy(e.value as Map<String, dynamic>)
            : e.value is Map
                ? _deepCopy(Map<String, dynamic>.from(e.value as Map))
                : e.value,
    };

final _rand = Random();
var _seq = 0;

/// معرّفٌ قصيرٌ فريد — المطابقة في سجلّ الحركة وفي «كتابة بالحروف» بالمعرّفات لا بالمواضع.
String btNewId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';
