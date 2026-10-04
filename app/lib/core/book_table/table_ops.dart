import 'book_table.dart';
import 'table_formulas.dart';

/// عمليات الجدول (ADR-057) — **كلُّها نقيّة**: تأخذ جدولاً وتعيد نسخةً معدّلة، والأصل لا يُمسّ (فالتراجع حفظُ السابقة).
///
/// 🔑 **القاعدة التي تحرسها كل عملية: كل خانةٍ تملكها خليةٌ واحدة بالضبط** — بلا تداخلٍ ولا ثقوب، وهي عينُ قاعدة الخادم
/// (`BookTableRules`). فإضافةُ صفٍّ يعبر دمجاً عمودياً تمدّ الدمج، وحذفُ صفٍّ تبدأ فيه خليةٌ مدموجة ينقلها إلى الصفّ التالي.
class BtOps {
  BtOps._();

  // ─────────────────────────── الإنشاء ───────────────────────────

  /// جدولٌ فارغ: صفّ عناوين عريضٌ في الوسط ثم صفوف.
  static BtTable blank(int rows, int cols, {bool header = true}) {
    rows = rows.clamp(1, 600);
    cols = cols.clamp(1, 30);
    return BtTable(
      id: btNewId('t'),
      headerRows: header && rows > 1 ? 1 : 0,
      cols: [for (var i = 0; i < cols; i++) BtCol(id: btNewId('k'))],
      rows: [
        for (var r = 0; r < rows; r++)
          BtRow(id: btNewId('r'), cells: [
            for (var c = 0; c < cols; c++)
              header && rows > 1 && r == 0 ? textCell('', bold: true, align: 'center') : BtCell(id: btNewId('c'))
          ]),
      ],
    );
  }

  /// **جدول فاتورة جاهز** بشكل نموذج المالك («فاتورة رقم 7»): أعمدته الستّة بأوزان Word نفسها · عناوين رمادية ·
  /// ترقيمٌ تلقائيّ · وصفّ مجموعٍ مدموج: «المجموع» · Σ للسعر الكلي · والمبلغ كتابةً.
  static BtTable invoice() {
    const grey = '#AEAAAA';
    const titles = ['ت', 'المادة بالإنجليزي', 'المادة بالعربي', 'الكمية', 'سعر المفرد', 'السعر الكلي'];
    const weights = [876.0, 2977.0, 2410.0, 834.0, 1559.0, 1712.0];
    final sum = textCell('', bold: true, size: 14, align: 'center', bg: grey)
      ..colSpan = 2
      ..formula = BtFormula(col: 5);
    final words = textCell('', bold: true, size: 14, align: 'center', bg: grey)
      ..colSpan = 2
      ..words = BtWords(sourceCellId: sum.id);
    final total = textCell('المجموع', bold: true, size: 14, align: 'center', bg: grey)..colSpan = 2;

    BtRow item(int n) => BtRow(id: btNewId('r'), cells: [
          textCell('$n', bold: true, align: 'center'),
          textCell('', bold: true, align: 'right'),
          textCell('', bold: true, align: 'justify'),
          for (var i = 0; i < 3; i++) textCell('', bold: true, align: 'center'),
        ]);

    return BtTable(
      id: btNewId('t'),
      headerRows: 1,
      numberingCol: 0,
      cols: [for (final w in weights) BtCol(id: btNewId('k'), weight: w)],
      rows: [
        BtRow(id: btNewId('r'), cells: [for (final t in titles) textCell(t, bold: true, size: 14, align: 'center', bg: grey)]),
        item(1),
        item(2),
        item(3),
        BtRow(id: btNewId('r'), cells: [total, null, sum, null, words, null]),
      ],
    );
  }

  /// خليةٌ بنصٍّ وتنسيقٍ موحّد — تنسيقُ النصّ في الـDelta (عريض · حجم) والمحاذاة على سطرها.
  static BtCell textCell(String text, {bool bold = false, int? size, String? align, String? bg}) {
    final attrs = <String, dynamic>{if (bold) 'bold': true, if (size != null) 'size': '$size'};
    return BtCell(
      id: btNewId('c'),
      bg: bg,
      textStyle: attrs.isEmpty ? null : attrs,   // يبقى ولو فرغت الخلية
      delta: [
        if (text.isNotEmpty) {'insert': text, if (attrs.isNotEmpty) 'attributes': attrs},
        {'insert': '\n', if (align != null) 'attributes': {'align': align}},
      ],
    );
  }

  /// يستبدل نصّ الخلية **ويُبقي تنسيقها** (تنسيقُ أوّل جزءٍ ومحاذاةُ السطر) — للصق والترقيم.
  static void setText(BtCell cell, String text) {
    final inline = cell.inlineStyle;   // تنسيق نصّها — أو المحفوظ لها إن كانت فارغة
    if (inline != null) cell.textStyle = inline;
    Map<String, dynamic>? block;
    for (final op in cell.delta) {
      final ins = op['insert'];
      final a = op['attributes'];
      if (ins is String && ins.endsWith('\n') && a is Map) block = Map<String, dynamic>.from(a);
    }
    final lines = text.replaceAll('\r', '').split('\n');
    cell.delta = [
      for (var i = 0; i < lines.length; i++) ...[
        if (lines[i].isNotEmpty) {'insert': lines[i], if (inline != null) 'attributes': inline},
        {'insert': '\n', if (block != null) 'attributes': block},
      ],
    ];
  }

  // ─────────────────────────── الصفوف ───────────────────────────

  /// يُدرج صفّاً عند الموضع [at] (0 … عدد الصفوف). الخليةُ المدموجة عمودياً التي يعبرها تمتدّ، وصفّ البيانات
  /// الجديد يأخذ **الترقيم التالي** في عمود «ت».
  static BtTable insertRow(BtTable src, int at) {
    final t = src.copy();
    at = at.clamp(0, t.rowCount);
    final cells = List<BtCell?>.filled(t.colCount, null);
    var c = 0;
    while (c < t.colCount) {
      final crossing = at > 0 && at < t.rowCount ? t.ownerOf(at, c) : null;
      if (crossing != null && crossing.row < at) {
        crossing.cell.rowSpan++;
        c = crossing.col + crossing.cell.colSpan;   // خاناته في الصفّ الجديد تبقى null
      } else {
        // يرث شكل الخلية فوقه (اللون والمحاذاة والتنسيق) بلا نصّها — كما يفعل Word
        final above = at > 0 ? t.ownerOf(at - 1, c)?.cell : null;
        cells[c] = _styledLike(above);
        c++;
      }
    }
    final inHeader = at < t.headerRows;
    t.rows.insert(at, BtRow(id: btNewId('r'), cells: cells));
    if (inHeader) t.headerRows++;

    final nc = t.numberingCol;
    if (!inHeader && nc != null && cells[nc] != null) setText(cells[nc]!, BtFormulas.nextNumber(t, at));
    return t;
  }

  /// يحذف الصفّ [r] — وخليةٌ مدموجة تبدأ فيه **تنتقل إلى الصفّ التالي بمحتواها** (لا يضيع نصٌّ يغطّي صفّين).
  static BtTable deleteRow(BtTable src, int r) {
    if (src.rowCount <= 1 || r < 0 || r >= src.rowCount) return src;
    final t = src.copy();
    final removed = <String>{};
    // المالكون أوّلاً (قبل أيّ تعديل) — فتعديلُ امتدادٍ لا يغيّر جواب «مَن يملك الخانة» لعمودٍ تالٍ.
    final owners = <BtSlot>[];
    for (var c = 0; c < t.colCount; c++) {
      final o = t.ownerOf(r, c);
      if (o != null && o.col == c) owners.add(o);
    }
    for (final o in owners) {
      if (o.row < r) {
        o.cell.rowSpan--;                       // دمجٌ من فوق يعبر الصفّ
      } else if (o.cell.rowSpan > 1) {
        o.cell.rowSpan--;                       // يبدأ هنا ويمتدّ ⟵ ينتقل إلى ما تحته بمحتواه
        t.rows[r + 1].cells[o.col] = o.cell;
      } else {
        removed.add(o.cell.id);
      }
    }
    t.rows.removeAt(r);
    if (r < t.headerRows) t.headerRows--;
    _dropDanglingWords(t, removed);
    return t;
  }

  // ─────────────────────────── الأعمدة ───────────────────────────

  /// يُدرج عموداً عند الموضع [at] (منطقياً: 0 = العمود الأوّل). الدمج الأفقيّ الذي يعبره يمتدّ، وصيغ الجمع وعمود
  /// الترقيم التي بعده تُزاح.
  static BtTable insertCol(BtTable src, int at) {
    final t = src.copy();
    at = at.clamp(0, t.colCount);
    final neighbour = t.cols[at < t.colCount ? at : at - 1];
    t.cols.insert(at, BtCol(id: btNewId('k'), weight: neighbour.weight));
    for (var r = 0; r < t.rowCount; r++) {
      final crossing = at > 0 && at < src.colCount ? src.ownerOf(r, at) : null;
      if (crossing != null && crossing.col < at) {
        // خانةٌ داخل دمجٍ أفقيّ يعبر الموضع ⟵ يمتدّ الدمج (مرّةً واحدة لكل خلية: عند صفّ بدايتها)
        if (crossing.row == r) t.rows[r].cells[crossing.col]!.colSpan++;
        t.rows[r].cells.insert(at, null);
      } else {
        // لا دمجَ أفقيٌّ يعبر الموضع ⟵ خليةٌ جديدة مستقلّة في كل صفّ — ولو كان تحتها دمجٌ عموديّ يبدأ في العمود
        // الذي يليها (ذاك الدمج انزاح يميناً مع عموده، فخانتُه الجديدة ليست تحته).
        final beside = at > 0 ? t.ownerOf(r, at - 1)?.cell : null;
        t.rows[r].cells.insert(at, _styledLike(beside));
      }
    }
    _fillHoles(t);   // حارسٌ أخير: لا خانةَ null بلا مالك
    for (final s in t.masters) {
      final f = s.cell.formula;
      if (f != null && f.col >= at) f.col++;
    }
    if (t.numberingCol != null && t.numberingCol! >= at) t.numberingCol = t.numberingCol! + 1;
    return t;
  }

  /// يحذف العمود [c] — وخليةٌ مدموجة تبدأ فيه **تنتقل إلى العمود التالي بمحتواها**؛ وجمعٌ كان يجمعه يُزال.
  static BtTable deleteCol(BtTable src, int c) {
    if (src.colCount <= 1 || c < 0 || c >= src.colCount) return src;
    final t = src.copy();
    final removed = <String>{};
    for (var r = 0; r < t.rowCount; r++) {
      final o = t.ownerOf(r, c);
      if (o == null || o.row != r) continue;
      if (o.col < c) {
        o.cell.colSpan--;
      } else if (o.cell.colSpan > 1) {
        o.cell.colSpan--;
        t.rows[r].cells[c + 1] = o.cell;
      } else {
        removed.add(o.cell.id);
      }
    }
    for (final row in t.rows) {
      row.cells.removeAt(c);
    }
    t.cols.removeAt(c);
    for (final s in t.masters.toList()) {
      final f = s.cell.formula;
      if (f == null) continue;
      if (f.col == c) {
        s.cell.formula = null;
      } else if (f.col > c) {
        f.col--;
      }
    }
    if (t.numberingCol == c) {
      t.numberingCol = null;
    } else if (t.numberingCol != null && t.numberingCol! > c) {
      t.numberingCol = t.numberingCol! - 1;
    }
    _dropDanglingWords(t, removed);
    return t;
  }

  // ─────────────────────────── الدمج ───────────────────────────

  /// هل يمكن دمج المستطيل؟ — `null` إن أمكن، وإلا السبب بالعربية.
  static String? canMerge(BtTable t, int r1, int c1, int r2, int c2) {
    final (top, left, bottom, right) = _norm(r1, c1, r2, c2);
    if (top == bottom && left == right) return 'حدّد أكثر من خليةٍ للدمج.';
    if (top < 0 || left < 0 || bottom >= t.rowCount || right >= t.colCount) return 'التحديد خارج الجدول.';
    for (final s in t.masters) {
      final inside = s.row >= top && s.col >= left && s.row + s.cell.rowSpan - 1 <= bottom && s.col + s.cell.colSpan - 1 <= right;
      final overlaps = s.row <= bottom && s.row + s.cell.rowSpan - 1 >= top && s.col <= right && s.col + s.cell.colSpan - 1 >= left;
      if (overlaps && !inside) return 'التحديد يقطع خليةً مدموجة — وسّعه ليشملها كلَّها.';
    }
    if (top < t.headerRows && bottom >= t.headerRows) return 'لا تُدمج خلايا العناوين مع ما تحتها.';
    return null;
  }

  /// يدمج المستطيل في خليته العليا (بدايةً) — ونصوصُ الخلايا الأخرى تُضاف أسطراً تحت نصّها كما في Word.
  static BtTable merge(BtTable src, int r1, int c1, int r2, int c2) {
    if (canMerge(src, r1, c1, r2, c2) != null) return src;
    final t = src.copy();
    final (top, left, bottom, right) = _norm(r1, c1, r2, c2);
    final master = t.rows[top].cells[left]!;
    final absorbed = <String>{};
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        final cell = t.rows[r].cells[c];
        if (cell == null || identical(cell, master)) continue;
        if (!cell.isEmpty) {
          master.delta = [...master.delta, ...cell.delta];
        }
        absorbed.add(cell.id);
        t.rows[r].cells[c] = null;
      }
    }
    master
      ..rowSpan = bottom - top + 1
      ..colSpan = right - left + 1;
    _dropDanglingWords(t, absorbed);
    return t;
  }

  /// يفكّ دمج الخلية في (r, c) — الخانات تعود خلايا فارغةً بلون الخلية ومحاذاتها.
  static BtTable unmerge(BtTable src, int r, int c) {
    final o = src.ownerOf(r, c);
    if (o == null || (o.cell.rowSpan == 1 && o.cell.colSpan == 1)) return src;
    final t = src.copy();
    final master = t.rows[o.row].cells[o.col]!;
    for (var rr = o.row; rr < o.row + master.rowSpan; rr++) {
      for (var cc = o.col; cc < o.col + master.colSpan; cc++) {
        if (rr == o.row && cc == o.col) continue;
        t.rows[rr].cells[cc] = BtCell(id: btNewId('c'), bg: master.bg, vAlign: master.vAlign);
      }
    }
    master
      ..rowSpan = 1
      ..colSpan = 1;
    return t;
  }

  // ─────────────────────────── الشكل ───────────────────────────

  /// يطبّق [edit] على كل خليةٍ حقيقية تقع (بدايتها) في المستطيل — اللون والمحاذاة العمودية وما شابه.
  static BtTable editCells(BtTable src, int r1, int c1, int r2, int c2, void Function(BtCell cell) edit) {
    final t = src.copy();
    final (top, left, bottom, right) = _norm(r1, c1, r2, c2);
    for (final s in t.masters) {
      if (s.row >= top && s.row <= bottom && s.col >= left && s.col <= right) edit(s.cell);
    }
    return t;
  }

  /// يوزّع العرض بالتساوي.
  static BtTable distributeEvenly(BtTable src) {
    final t = src.copy();
    for (final c in t.cols) {
      c.weight = 1;
    }
    return t;
  }

  /// «توزيع تلقائي»: عرض كل عمودٍ بحسب أطول نصٍّ فيه — **والأرقام بطولها كاملاً** فلا تنكسر (قرار المالك).
  static BtTable autoFit(BtTable src) {
    final t = src.copy();
    final need = List<double>.filled(t.colCount, 3);
    for (final s in t.masters) {
      if (s.cell.colSpan != 1) continue;
      final text = s.cell.text;
      final longest = text.split('\n').fold<int>(0, (m, l) => l.length > m ? l.length : m);
      final numeric = BtFormulas.parseNumber(text) != null;
      // النصّ يلتفّ أسطراً فيُحسب بنصفه (حدّ 30)، والرقم لا يلتفّ فيُحسب بطوله كاملاً.
      final w = numeric ? longest + 1.0 : (longest / 2).clamp(3, 30).toDouble();
      if (w > need[s.col]) need[s.col] = w;
    }
    for (var i = 0; i < t.colCount; i++) {
      t.cols[i].weight = need[i];
    }
    return t;
  }

  // ─────────────────────────── اللصق ───────────────────────────

  /// يلصق شبكة نصوص (من Excel أو Word) **بدءاً من الخلية (r, c)** — ويُضيف الصفوف والأعمدة الناقصة.
  /// الخانة التي يغطّيها دمجٌ تُتخطّى (لا يُكتب فوق خليةٍ مدموجة).
  ///
  /// 🐛 **وصفّ المجموع لا يُكتب فوقه**: لصقُ خمسة بنودٍ في فاتورةٍ فيها ثلاثة كان يكتب فوق صفّ «المجموع» —
  /// الآن يُدرج صفٌّ **قبل** كل صفٍّ فيه جمعٌ أو حروف، فيبقى المجموع آخراً ويستمرّ الترقيم تلقائياً. (كشفه الحارس.)
  static BtTable paste(BtTable src, int r, int c, List<List<String>> grid) {
    if (grid.isEmpty) return src;
    var t = src;
    final width = grid.fold<int>(0, (m, row) => row.length > m ? row.length : m);
    for (var i = 0; i < grid.length; i++) {
      final rr = r + i;
      if (rr >= t.rowCount) {
        t = insertRow(t, t.rowCount);
      } else if (_isTotalRow(t, rr)) {
        t = insertRow(t, rr);
      }
    }
    while (t.colCount < c + width && t.colCount < 30) {
      t = insertCol(t, t.colCount);
    }
    t = t.copy();
    for (var i = 0; i < grid.length; i++) {
      for (var j = 0; j < grid[i].length; j++) {
        final rr = r + i, cc = c + j;
        if (rr >= t.rowCount || cc >= t.colCount) continue;
        final cell = t.rows[rr].cells[cc];
        if (cell == null || cell.formula != null) continue;   // خانةٌ مدموجة أو خلية جمعٍ حيّ
        setText(cell, grid[i][j]);
      }
    }
    return t;
  }

  // ─────────────────────────── مساعدات ───────────────────────────

  /// صفٌّ تبدأ فيه خلية جمعٍ أو «كتابة بالحروف» — صفّ المجموع.
  static bool _isTotalRow(BtTable t, int r) =>
      t.rows[r].cells.any((cell) => cell != null && (cell.formula != null || cell.words != null));

  static (int, int, int, int) _norm(int r1, int c1, int r2, int c2) =>
      (r1 < r2 ? r1 : r2, c1 < c2 ? c1 : c2, r1 < r2 ? r2 : r1, c1 < c2 ? c2 : c1);

  /// خليةٌ فارغة بشكل جارتها: اللون والمحاذاة وتنسيق النصّ — بلا نصٍّ ولا صيغة.
  static BtCell _styledLike(BtCell? like) {
    if (like == null) return BtCell(id: btNewId('c'));
    final cell = BtCell(
      id: btNewId('c'),
      bg: like.bg,
      vAlign: like.vAlign,
      textStyle: like.inlineStyle,   // عريضُ الجارة يبقى للخلية الجديدة ولو بلا نصّ
      delta: [for (final op in like.delta) Map<String, dynamic>.from(op)],
    );
    setText(cell, '');
    return cell;
  }

  static void _fillHoles(BtTable t) {
    for (var r = 0; r < t.rowCount; r++) {
      for (var c = 0; c < t.colCount; c++) {
        if (t.rows[r].cells[c] == null && t.ownerOf(r, c) == null) t.rows[r].cells[c] = BtCell(id: btNewId('c'));
      }
    }
  }

  /// «كتابة بالحروف» تشير إلى خليةٍ حُذفت أو دُمجت ⟵ تُزال (الخادم يرفض مصدراً غير موجود).
  static void _dropDanglingWords(BtTable t, Set<String> removedIds) {
    if (removedIds.isEmpty) return;
    final alive = {for (final s in t.masters) s.cell.id};
    for (final s in t.masters) {
      final w = s.cell.words;
      if (w != null && !alive.contains(w.sourceCellId)) s.cell.words = null;
    }
  }

  /// فحص البنية (مرآة قاعدة الخادم) — `null` إن سلمت، وإلا السبب. للحرّاس وقبل الحفظ.
  static String? validate(BtTable t) {
    if (t.rowCount == 0 || t.colCount == 0) return 'جدولٌ بلا صفوف أو أعمدة.';
    final covered = List.generate(t.rowCount, (_) => List.filled(t.colCount, false));
    for (var r = 0; r < t.rowCount; r++) {
      if (t.rows[r].cells.length != t.colCount) return 'الصفّ ${r + 1} لا يطابق عدد الأعمدة.';
      for (var c = 0; c < t.colCount; c++) {
        final cell = t.rows[r].cells[c];
        if (cell == null) {
          if (!covered[r][c]) return 'خانةٌ فارغة لا يغطّيها دمج (${r + 1}، ${c + 1}).';
          continue;
        }
        if (covered[r][c]) return 'خليةٌ داخل دمجٍ آخر (${r + 1}، ${c + 1}).';
        if (r + cell.rowSpan > t.rowCount || c + cell.colSpan > t.colCount) return 'دمجٌ يخرج عن الجدول.';
        if (r < t.headerRows && r + cell.rowSpan > t.headerRows) return 'خليةُ عناوين تمتدّ إلى ما تحتها.';
        for (var rr = r; rr < r + cell.rowSpan; rr++) {
          for (var cc = c; cc < c + cell.colSpan; cc++) {
            if (covered[rr][cc]) return 'دمجان متداخلان.';
            covered[rr][cc] = true;
          }
        }
      }
    }
    return null;
  }
}
