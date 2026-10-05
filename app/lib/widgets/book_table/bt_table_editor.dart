import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_formulas.dart';
import '../../core/book_table/table_serializer.dart';
import 'bt_editor_hub.dart';
import 'bt_rich_text.dart';
import 'bt_table_view.dart';

/// لون التحديد وحدّ الخلية النشطة — والورقة بيضاء في الوضعين فاللون ثابت.
const _selectionFill = Color(0x2E2563EB);
const _selectionEdge = Color(0xFF2563EB);

/// البلوك المضمَّن `dms-table` داخل محرّر Quill (ADR-057).
///
/// ⚠️ بلا هذا الباني يرمي Quill عند فتح كتابٍ فيه جدول (نوعُ بلوكٍ لا يعرف رسمه) — فهو شرطٌ لفتح الكتب لا تجميلٌ.
/// و[hub] غائبٌ ⟵ عرضٌ للقراءة (كما سيُطبع) بلا تحرير.
class BtEmbedBuilder extends quill.EmbedBuilder {
  BtEmbedBuilder({this.hub});
  final BtEditorHub? hub;

  @override
  String get key => kDmsTableEmbed;

  @override
  bool get expanded => true;

  @override
  String toPlainText(quill.Embed node) => '\n';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    final h = hub;
    if (h != null && !embedContext.readOnly) return BtTableEditor(hub: h, data: data);
    BtTable table;
    try {
      table = BtJson.fromEmbedData(data);
    } catch (_) {
      return const _Broken();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: BtTableView(table: table, words: h?.wordsFor(table) ?? const {}),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('⚠️ جدولٌ تالف لا يمكن عرضه', style: TextStyle(color: Colors.red)),
      );
}

/// الجدول قابلاً للتحرير على الورقة: النقر يفتح الخلية للكتابة · **السحب بالفأرة** أو Shift+نقر يحدّد عدّة خلايا ·
/// حدود الأعمدة تُسحب.
///
/// 🔑 **كلُّ الحالة في [BtEditorHub]** — هذه الودجة تُبنى من جديد مع كل تغييرٍ في المستند ولا تحفظ شيئاً.
class BtTableEditor extends StatelessWidget {
  const BtTableEditor({super.key, required this.hub, required this.data});

  final BtEditorHub hub;
  final Object? data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        BtTable stored;
        try {
          // 🔴 **من المستند لا من نسخة البناء**: Quill لا يعيد بناء المتن مع تغييرٍ بلا تركيز (`ignoreFocus`) — فجدولٌ يقرأ
          //    ما التُقط عند بنائه يبقى قديماً على الشاشة (كشفه الحارس: الجمع أظهر 2,500 والمستند فيه 3,500).
          final initial = hub.parse(data);
          final loc = hub.locate(initial.id);
          if (loc == null) return const SizedBox.shrink();   // حُذف ولم يُعِد Quill بناء السطر بعد
          stored = loc.table;
        } catch (_) {
          return const _Broken();
        }
        final table = hub.current(stored);
        final active = hub.sel?.tableId == table.id;
        final view = BtTableView(
          key: ValueKey('bt-table-${table.id}'),
          table: table,
          words: hub.wordsFor(table),
          weights: active && hub.dragTableId == table.id ? hub.dragWeights : null,
          contentBuilder: active && hub.editing ? (s) => s.cell.id == hub.editingCellId ? hub.buildCellEditor() : null : null,
          cellBuilder: (s, box) => _cell(table, s, box, active),
          gridWrapper: active ? (grid) => _ColumnHandles(hub: hub, table: table, child: grid) : null,
        );
        Widget body = Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: view);
        if (active) {
          body = Focus(
            focusNode: hub.tableFocus,
            onKeyEvent: hub.onTableKey,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(border: Border.all(color: _selectionEdge.withValues(alpha: 0.35))),
              child: body,
            ),
          );
        }
        // 🔴 المؤشّر على الجدول للجدول وحده (بلاغ المالك 2026-10-05): `Listener` يرى الحدث **قبل** مُميِّزات الإيماءة،
        //    فيُعلم المحرّك أن الضغطة هنا — ومحرّر المتن يتخلّى عنها — ويحدّد النقرةَ من السحب بنفسه.
        //    ⚠️ **وهو الأبعد في الشجرة دائماً**: الجدول يصير نشطاً أثناء السحب فيُلفّ بـ`Focus` — ولو كان الـ`Listener` داخله
        //    لأُعيد إنشاؤه وانقطع السحب عن عنصرٍ جديد.
        return Listener(
          onPointerDown: (e) {
            hub.tablePointerDown();
            if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;   // الزرّ الأيمن لا يفتح خلية
            final at = _cellAt(context, e.position);
            if (at != null && at.tableId == table.id) {
              hub.pressCell(table.id, at.row, at.col, e.position, touch: e.kind != PointerDeviceKind.mouse);
            }
          },
          onPointerMove: (e) => hub.pressMove(e.position, _cellAt(context, e.position)),
          onPointerUp: (_) {
            hub.pressUp(extend: HardwareKeyboard.instance.isShiftPressed);
            hub.tablePointerUp();
          },
          onPointerCancel: (_) {
            hub.pressCancel();
            hub.tablePointerUp();
          },
          child: body,
        );
      },
    );
  }

  Widget _cell(BtTable table, BtSlot s, Widget box, bool active) {
    final editingThis = active && hub.editingCellId == s.cell.id;
    final selected = active && hub.inSelection(table.id, s);
    final head = active && hub.isHead(table.id, s);
    final multi = active && !(hub.sel?.single ?? true);
    Widget w = box;
    // علامة الجمع والحروف — في المحرّر وحده، لا تُطبع
    if (s.cell.formula != null || s.cell.words != null) {
      w = Stack(children: [
        w,
        PositionedDirectional(
          top: 0,
          start: 1,
          child: Text(s.cell.formula != null ? 'Σ' : 'حروف',
              style: const TextStyle(fontSize: 6, color: Color(0xFF2563EB), fontWeight: FontWeight.bold, height: 1)),
        ),
      ]);
    }
    if (selected || head) {
      w = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: multi && selected ? _selectionFill : null,
          border: head ? Border.all(color: _selectionEdge, width: editingThis ? 1.2 : 1.6) : null,
        ),
        child: w,
      );
    }
    if (!editingThis) {
      // النقر والسحب يعالجهما `Listener` الجدول — وهنا **تُكسب الضغطة بالفأرة فوراً** (`EagerGestureRecognizer`) فيخسر
      // سحبُ تحديد النصّ في محرّر المتن ولا يغطّي الجدول. والخلية المفتوحة بلا هذا: النقر والسحب فيها لنصّها.
      w = MouseRegion(
        cursor: s.cell.formula != null || s.cell.words != null ? SystemMouseCursors.basic : SystemMouseCursors.text,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: _eager,
          child: w,
        ),
      );
    }
    w = MetaData(metaData: BtCellRef(table.id, s.row, s.col), behavior: HitTestBehavior.translucent, child: w);
    return KeyedSubtree(key: ValueKey('bt-cell-${s.row}-${s.col}'), child: w);
  }
}

final _eager = <Type, GestureRecognizerFactory>{
  EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
    () => EagerGestureRecognizer(supportedDevices: const {PointerDeviceKind.mouse}),
    (_) {},
  ),
};

/// الخلية تحت نقطةٍ من الشاشة — من علامة `MetaData` التي تحملها كل خلية.
BtCellRef? _cellAt(BuildContext context, Offset global) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, global, View.of(context).viewId);
  for (final e in result.path) {
    final target = e.target;
    if (target is RenderMetaData && target.metaData is BtCellRef) return target.metaData as BtCellRef;
  }
  return null;
}

/// مقابض سحب حدود الأعمدة — **والسحب يُرى وهو يحدث** ولا يُكتب في المستند إلا عند الإفلات (خطوة تراجعٍ واحدة).
class _ColumnHandles extends StatelessWidget {
  const _ColumnHandles({required this.hub, required this.table, required this.child});

  final BtEditorHub hub;
  final BtTable table;
  final Widget child;

  /// أضيق عمودٍ يُسمح به بالسحب (نقطة).
  static const minWidth = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final weights = hub.dragTableId == table.id && hub.dragWeights != null ? hub.dragWeights! : [for (final k in table.cols) k.weight];
      final total = weights.fold<double>(0, (a, b) => a + b);
      if (total <= 0 || weights.length < 2 || !width.isFinite) return child;
      final edges = <double>[];
      var acc = 0.0;
      for (var i = 0; i < weights.length - 1; i++) {
        acc += weights[i];
        final x = width * acc / total;
        edges.add(table.rtl ? width - x : x);
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          for (var i = 0; i < edges.length; i++)
            Positioned(
              key: ValueKey('bt-col-edge-$i'),
              top: 0,
              bottom: 0,
              left: edges[i] - 3,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => hub.dragStart(table.id, weights),
                  onHorizontalDragUpdate: (d) => _drag(i, d.delta.dx, width, total),
                  onHorizontalDragEnd: (_) => _end(context, i, width),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      );
    });
  }

  void _drag(int i, double dx, double width, double total) {
    final w = List<double>.of(hub.dragWeights ?? [for (final k in table.cols) k.weight]);
    // الحدّ بين العمود i والعمود i+1: في الجدول العربيّ العمود i على يمين الحدّ
    final dw = dx / width * total * (table.rtl ? -1 : 1);
    final min = minWidth / width * total;
    final a = w[i] + dw, b = w[i + 1] - dw;
    if (a < min || b < min) return;
    w[i] = a;
    w[i + 1] = b;
    hub.dragUpdate(w);
  }

  void _end(BuildContext context, int i, double width) {
    final w = hub.dragWeights;
    hub.dragEnd();
    if (w == null) return;
    // الأرقام لا تنكسر — تصغر (كما في الطباعة). يُنبَّه المستخدم إن صغُر رقمٌ بالسحب.
    final total = w.fold<double>(0, (a, b) => a + b);
    for (final col in [i, i + 1]) {
      final colWidth = width * w[col] / total - 8;
      for (final s in table.masters) {
        if (s.col != col || s.cell.colSpan != 1) continue;
        final text = s.cell.text;
        if (text.contains('\n') || BtFormulas.parseNumber(text) == null) continue;
        final tp = TextPainter(
          text: TextSpan(text: text, style: btSpanStyle(kPaperBase, s.cell.inlineStyle ?? const {})),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final tooWide = tp.width > colWidth;
        tp.dispose();
        if (tooWide) {
          hub.onMessage?.call('صغُر رقمٌ ليتّسع في العمود — لا ينكسر، وكذلك يُطبع. وسّع العمود إن أردته بحجمه.');
          return;
        }
      }
    }
  }
}
