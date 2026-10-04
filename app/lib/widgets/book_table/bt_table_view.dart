import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_formulas.dart';
import '../../core/book_table/table_serializer.dart';
import 'bt_grid.dart';
import 'bt_rich_text.dart';

/// خطّ المتن والجداول وحجمه على الورقة (قرار المالك: Times New Roman 12 — والوحدة نقطة).
const kPaperFont = 'Times New Roman';
const kPaperBase = TextStyle(fontFamily: kPaperFont, fontSize: 12, height: 1.25, color: Color(0xFF111111));

/// جدولٌ مرسومٌ على الورقة (ADR-057) — بعرضه ومحاذاته واتجاهه ودمجه وألوانه وحدوده، كما يطبعه الخادم.
///
/// [words] نصوص «كتابة بالحروف» مفهرسةً بمعرّف الخلية (يولّدها الخادم) — وغيابُها يُظهر علامةً لا فراغاً.
class BtTableView extends StatelessWidget {
  const BtTableView({super.key, required this.table, this.words = const {}, this.cellBuilder});

  final BtTable table;
  final Map<String, String> words;

  /// يستبدل محتوى خلية (المحرّر يرسم الخلية النشطة بمحرّرها — الدفعة ٧).
  final Widget Function(BtSlot slot, Widget content)? cellBuilder;

  @override
  Widget build(BuildContext context) {
    final computed = BtFormulas.evaluate(table);
    final grid = BtGrid(
      weights: [for (final c in table.cols) c.weight],
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

  Widget _cell(BtSlot s, Map<String, BtComputed> computed) {
    final cell = s.cell;
    final style = btSpanStyle(kPaperBase, cell.inlineStyle ?? const {});
    Widget content;
    if (cell.formula != null) {
      content = _single(computed[cell.id]?.text ?? '', style, cell);
    } else if (cell.words != null) {
      final w = cell.words!;
      final core = words[cell.id];
      final text = [w.prefix?.trim(), core ?? '…', w.suffix?.trim()].where((x) => x != null && x.isNotEmpty).join(' ');
      content = _single(text, core == null ? style.copyWith(color: const Color(0xFF888888)) : style, cell);
    } else {
      content = BtRichText(delta: cell.delta, base: kPaperBase);
    }
    final box = Container(
      color: btParseColor(cell.bg),
      padding: const EdgeInsets.all(4),
      alignment: switch (cell.vAlign) {
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        _ => Alignment.center,
      },
      child: content,
    );
    return cellBuilder?.call(s, box) ?? box;
  }

  /// نصٌّ محسوب بتنسيق الخلية ومحاذاة سطرها.
  Widget _single(String text, TextStyle style, BtCell cell) {
    final lines = btDeltaLines(cell.delta);
    final align = switch (lines.isEmpty ? null : lines.first.block['align']) {
      'center' => TextAlign.center,
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.start,
    };
    return SizedBox(width: double.infinity, child: Text(text, style: style, textAlign: align));
  }
}

/// البلوك المضمَّن `dms-table` داخل محرّر Quill — **عرضٌ** في هذه الدفعة (التحرير في الدفعة ٧).
///
/// ⚠️ بلا هذا الباني يرمي Quill عند فتح كتابٍ فيه جدول (نوعُ بلوكٍ لا يعرف رسمه) — فهو شرطٌ لفتح الكتب لا تجميلٌ.
class BtEmbedBuilder extends quill.EmbedBuilder {
  BtEmbedBuilder({this.words = const {}});
  final Map<String, String> words;

  @override
  String get key => kDmsTableEmbed;

  @override
  bool get expanded => true;

  @override
  String toPlainText(quill.Embed node) => '\n';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    BtTable table;
    try {
      table = BtJson.fromEmbedData(embedContext.node.value.data);
    } catch (_) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('⚠️ جدولٌ تالف لا يمكن عرضه', style: TextStyle(color: Colors.red)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: BtTableView(table: table, words: words),
    );
  }
}
