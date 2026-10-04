import 'package:flutter/material.dart';

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_formulas.dart';
import 'bt_grid.dart';
import 'bt_rich_text.dart';

/// خطّ المتن والجداول وحجمه على الورقة (قرار المالك: Times New Roman 12 — والوحدة نقطة).
const kPaperFont = 'Times New Roman';
const kPaperBase = TextStyle(fontFamily: kPaperFont, fontSize: 12, height: 1.25, color: Color(0xFF111111));

/// حشوة الخلية على الورقة — والطباعة بالقيمة نفسها.
const kCellPadding = EdgeInsets.all(4);

/// جدولٌ مرسومٌ على الورقة (ADR-057) — بعرضه ومحاذاته واتجاهه ودمجه وألوانه وحدوده، كما يطبعه الخادم.
///
/// [words] نصوص «كتابة بالحروف» مفهرسةً بمعرّف الخلية (يولّدها الخادم) — وغيابُها يُظهر علامةً لا فراغاً.
class BtTableView extends StatelessWidget {
  const BtTableView({
    super.key,
    required this.table,
    this.words = const {},
    this.weights,
    this.contentBuilder,
    this.cellBuilder,
    this.gridWrapper,
  });

  final BtTable table;
  final Map<String, String> words;

  /// أوزان أعمدةٍ بدل أوزان الجدول — **سحبُ الحدّ يُرى وهو يُسحب** ولا يُكتب في المستند إلا عند الإفلات.
  final List<double>? weights;

  /// يستبدل **محتوى** خلية (المحرّر يضع محرّر الخلية النشطة مكان نصّها) — والخلفية والحشوة كما هي.
  final Widget? Function(BtSlot slot)? contentBuilder;

  /// يلفّ **الخلية كلَّها** (التحديد · النقر).
  final Widget Function(BtSlot slot, Widget box)? cellBuilder;

  /// يلفّ الشبكة داخل إطار عرضها (مقابض سحب حدود الأعمدة).
  final Widget Function(Widget grid)? gridWrapper;

  @override
  Widget build(BuildContext context) {
    final computed = BtFormulas.evaluate(table);
    final grid = BtGrid(
      weights: weights ?? [for (final c in table.cols) c.weight],
      rowCount: table.rowCount,
      rtl: table.rtl,
      borderWidth: table.borderWidthPt,
      borderColor: btParseColor(table.borderColor) ?? Colors.black,
      children: [
        for (final s in table.masters)
          BtGridCell(
            row: s.row,
            col: s.col,
            rowSpan: s.cell.rowSpan,
            colSpan: s.cell.colSpan,
            child: _cell(s, computed),
          ),
      ],
    );
    return btTableFrame(table, gridWrapper?.call(grid) ?? grid);
  }

  Widget _cell(BtSlot s, Map<String, BtComputed> computed) {
    final cell = s.cell;
    final style = btSpanStyle(kPaperBase, cell.inlineStyle ?? const {});
    Widget? content = contentBuilder?.call(s);
    if (content == null) {
      if (cell.formula != null) {
        content = _single(computed[cell.id]?.text ?? '', style, cell, number: true);
      } else if (cell.words != null) {
        final w = cell.words!;
        final core = words[cell.id];
        final text = [w.prefix?.trim(), core ?? '…', w.suffix?.trim()].where((x) => x != null && x.isNotEmpty).join(' ');
        content = _single(text, core == null ? style.copyWith(color: const Color(0xFF888888)) : style, cell);
      } else if (_isNumber(cell)) {
        content = _single(cell.text, style, cell, number: true);
      } else {
        content = BtRichText(delta: cell.delta, base: kPaperBase);
      }
    }
    final box = Container(
      color: btParseColor(cell.bg),
      padding: kCellPadding,
      alignment: switch (cell.vAlign) {
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        _ => Alignment.center,
      },
      child: content,
    );
    return cellBuilder?.call(s, box) ?? box;
  }

  /// رقمٌ خالصٌ في سطرٍ واحد — يُرسم بلا التفاف.
  static bool _isNumber(BtCell cell) {
    final t = cell.text;
    return t.isNotEmpty && !t.contains('\n') && BtFormulas.parseNumber(t) != null;
  }

  /// نصٌّ محسوب بتنسيق الخلية ومحاذاة سطرها.
  ///
  /// [number]: **الرقم لا ينكسر أبداً** (قرار المالك) — إن ضاق العمود صغُر قليلاً، كما تفعل الطباعة (`ScaleToFit`).
  Widget _single(String text, TextStyle style, BtCell cell, {bool number = false}) {
    final lines = btDeltaLines(cell.delta);
    final a = lines.isEmpty ? null : lines.first.block['align'];
    final align = switch (a) {
      'center' => TextAlign.center,
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.start,
    };
    if (!number) return SizedBox(width: double.infinity, child: Text(text, style: style, textAlign: align));
    final box = switch (a) {
      'center' => Alignment.center,
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => AlignmentDirectional.centerStart,
    };
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: box,
        child: Text(text, style: style, softWrap: false, maxLines: 1),
      ),
    );
  }
}

/// عرض الجدول ومحاذاته في الصفحة — مشتركٌ بين العرض والمحرّر.
Widget btTableFrame(BtTable table, Widget grid) {
  final factor = table.widthPct.clamp(30, 100) / 100;
  if (factor >= 1) return grid;
  // «بداية» السطر في المستند العربيّ يمين
  final align = switch (table.align) {
    'start' => Alignment.centerRight,
    'end' => Alignment.centerLeft,
    _ => Alignment.center,
  };
  return Align(alignment: align, child: FractionallySizedBox(widthFactor: factor, child: grid));
}
