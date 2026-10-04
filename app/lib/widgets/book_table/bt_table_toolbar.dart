import 'package:flutter/material.dart';

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_ops.dart';
import '../../core/theme.dart';
import 'bt_dialogs.dart';
import 'bt_editor_hub.dart';
import 'bt_rich_text.dart';

/// ألوان الخلايا — رماديّ نموذج المالك أوّلاً (`#AEAAAA`)، ثم ألوان Word الفاتحة.
const kBtCellColors = ['#AEAAAA', '#D9D9D9', '#F2F2F2', '#FFF2CC', '#FCE4D6', '#E2EFDA', '#DDEBF7', '#FFFF00'];

/// ألوان النصّ والحدود.
const kBtInkColors = ['#000000', '#404040', '#808080', '#C00000', '#0070C0', '#00B050', '#7030A0', '#ED7D31'];

/// شريط الجدول (ADR-057) — يظهر ما دام جدولٌ نشطاً، وكل زرٍّ يعمل على **المحدّد** (خليةٌ أو مستطيل).
///
/// ⚠️ تنسيق النصّ هنا للتحديد كلِّه (عدّة خلايا) — والخلية المفتوحة للكتابة ينسّقها شريط المحرّر نفسه بالتنسيق المختلط.
class BtTableToolbar extends StatelessWidget {
  const BtTableToolbar({super.key, required this.hub});
  final BtEditorHub hub;

  @override
  Widget build(BuildContext context) {
    final t = hub.activeTable;
    final s = hub.sel;
    final head = hub.headSlot;
    if (t == null || s == null || head == null) return const SizedBox.shrink();
    final rtl = t.rtl;
    final canMerge = BtOps.canMerge(t, s.top, s.left, s.bottom, s.right) == null;
    final spans = head.cell.rowSpan > 1 || head.cell.colSpan > 1;
    final action = AppColors.action(context);
    final theme = Theme.of(context);

    Widget btn(String key, IconData icon, String tip, VoidCallback? onPressed, {Color? color}) => IconButton(
          key: Key(key),
          tooltip: tip,
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: onPressed == null ? null : color),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: const EdgeInsets.all(4),
        );

    Widget gap() => const SizedBox(width: 8);

    return Container(
      key: const Key('bt-toolbar'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: action.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: action.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        runSpacing: 0,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 6),
            child: Text('الجدول', style: TextStyle(fontWeight: FontWeight.bold, color: action, fontSize: 12.5)),
          ),
          // ── الصفوف والأعمدة ──
          btn('bt-row-above', Icons.vertical_align_top_rounded, 'صفٌّ فوق', () => hub.applyRect((t, top, l, b, r) => BtOps.insertRow(t, top))),
          btn('bt-row-below', Icons.vertical_align_bottom_rounded, 'صفٌّ تحت',
              () => hub.applyRect((t, top, l, b, r) => BtOps.insertRow(t, b + 1))),
          btn('bt-col-right', Icons.border_right_rounded, 'عمودٌ يميناً',
              () => hub.applyRect((t, top, l, b, r) => BtOps.insertCol(t, rtl ? l : r + 1))),
          btn('bt-col-left', Icons.border_left_rounded, 'عمودٌ يساراً',
              () => hub.applyRect((t, top, l, b, r) => BtOps.insertCol(t, rtl ? r + 1 : l))),
          btn('bt-del-row', Icons.playlist_remove_rounded, 'حذف الصفوف المحدّدة', () => _deleteRows(t, s)),
          btn('bt-del-col', Icons.view_column_outlined, 'حذف الأعمدة المحدّدة', () => _deleteCols(t, s)),
          gap(),
          // ── الدمج ──
          btn('bt-merge', Icons.call_merge_rounded, 'دمج الخلايا (حدّد عدّة خلايا بـShift+نقر)',
              canMerge ? () => hub.applyRect(BtOps.merge) : null),
          btn('bt-unmerge', Icons.call_split_rounded, 'فكّ الدمج',
              spans ? () => hub.apply((t, s) => BtOps.unmerge(t, head.row, head.col)) : null),
          gap(),
          // ── شكل الخلايا ──
          _colorMenu('bt-bg', Icons.format_color_fill_rounded, 'لون الخلية', kBtCellColors, noneLabel: 'بلا لون',
              onPick: (hex) => hub.applyRect((t, top, l, b, r) => BtOps.editCells(t, top, l, b, r, (c) => c.bg = hex))),
          _menu<String>('bt-valign', Icons.vertical_align_center_rounded, 'المحاذاة العمودية', {
            'top': 'أعلى الخلية',
            'middle': 'وسط الخلية',
            'bottom': 'أسفل الخلية',
          }, current: head.cell.vAlign, onPick: (v) => hub.applyRect((t, top, l, b, r) => BtOps.editCells(t, top, l, b, r, (c) => c.vAlign = v))),
          if (!hub.editing) ...[
            btn('bt-bold', Icons.format_bold_rounded, 'عريض (للمحدّد كلّه)', () => _toggle(t, 'bold')),
            btn('bt-italic', Icons.format_italic_rounded, 'مائل', () => _toggle(t, 'italic')),
            btn('bt-underline', Icons.format_underlined_rounded, 'تسطير', () => _toggle(t, 'underline')),
            _menu<String>('bt-size', Icons.format_size_rounded, 'حجم الخط', {
              for (final n in ['8', '9', '10', '11', '12', '14', '16', '18', '20', '24', '28', '36']) n: n,
            }, onPick: (v) => _format({'size': v})),
            _colorMenu('bt-color', Icons.format_color_text_rounded, 'لون النصّ', kBtInkColors, noneLabel: 'الافتراضي',
                onPick: (hex) => _format({'color': hex})),
            _menu<String>('bt-align', Icons.format_align_center_rounded, 'محاذاة النصّ', {
              'right': 'يمين',
              'center': 'وسط',
              'left': 'يسار',
              'justify': 'ضبط',
            }, onPick: (v) => _format({'align': v})),
          ],
          gap(),
          // ── الجدول ──
          _bordersMenu(t),
          _menu<String>('bt-widths', Icons.width_normal_rounded, 'عرض الأعمدة (أو اسحب حدود الأعمدة)', {
            'auto': 'توزيع تلقائي بحسب المحتوى',
            'even': 'أعمدة متساوية',
          }, onPick: (v) => hub.apply((t, _) => v == 'auto' ? BtOps.autoFit(t) : BtOps.distributeEvenly(t))),
          _headerMenu(t, s),
          btn('bt-dir', rtl ? Icons.format_textdirection_r_to_l_rounded : Icons.format_textdirection_l_to_r_rounded,
              rtl ? 'الاتجاه: من اليمين (اضغط لليسار)' : 'الاتجاه: من اليسار (اضغط لليمين)',
              () => hub.apply((t, _) => t.copy()..dir = t.rtl ? 'ltr' : 'rtl')),
          _widthMenu(t),
          _menu<int>('bt-numbering', Icons.format_list_numbered_rtl_rounded, 'الترقيم التلقائيّ', {
            s.left: 'هذا العمود للترقيم (${t.numberingCol == s.left ? 'مفعَّل' : 'الصفّ الجديد يأخذ التالي'})',
            -1: 'إيقاف الترقيم',
          }, current: t.numberingCol ?? -1, onPick: (v) => hub.apply((t, _) => BtOps.setNumberingCol(t, v < 0 ? null : v))),
          gap(),
          // ── الجمع والحروف ──
          Builder(
            builder: (context) => btn('bt-sum', Icons.functions_rounded, head.cell.formula != null ? 'تغيير الجمع أو إزالته' : 'جمعٌ حيّ (Σ)',
                hub.sel!.single ? () => _sum(context, t, head) : null,
                color: head.cell.formula != null ? action : null),
          ),
          Builder(
            builder: (context) => btn('bt-words', Icons.spellcheck_rounded, head.cell.words != null ? 'تعديل المبلغ كتابةً أو إزالته' : 'المبلغ كتابةً بالحروف',
                hub.sel!.single ? () => _words(context, t, head) : null,
                color: head.cell.words != null ? action : null),
          ),
          gap(),
          Builder(
            builder: (context) =>
                btn('bt-delete-table', Icons.delete_forever_rounded, 'حذف الجدول', () => _deleteTable(context), color: AppColors.danger),
          ),
          btn('bt-done', Icons.check_rounded, 'إنهاء تحرير الجدول (Esc)', hub.exit, color: theme.colorScheme.primary),
        ],
      ),
    );
  }

  // ─────────────────────────── العمليات ───────────────────────────

  void _deleteRows(BtTable t, BtSelection s) {
    if (s.top == 0 && s.bottom >= t.rowCount - 1) {
      hub.onMessage?.call('لا تُحذف كلُّ الصفوف من هنا — لحذف الجدول استعمل «حذف الجدول».');
      return;
    }
    hub.apply((t, s) {
      var x = t;
      for (var r = s.bottom; r >= s.top; r--) {
        x = BtOps.deleteRow(x, r);
      }
      return x;
    });
  }

  void _deleteCols(BtTable t, BtSelection s) {
    if (s.left == 0 && s.right >= t.colCount - 1) {
      hub.onMessage?.call('لا تُحذف كلُّ الأعمدة من هنا — لحذف الجدول استعمل «حذف الجدول».');
      return;
    }
    hub.apply((t, s) {
      var x = t;
      for (var c = s.right; c >= s.left; c--) {
        x = BtOps.deleteCol(x, c);
      }
      return x;
    });
  }

  void _format(Map<String, Object?> attrs) => hub.applyRect((t, top, l, b, r) => BtOps.formatCells(t, top, l, b, r, attrs));

  /// مفتاحٌ يُبدَّل: إن كان المحدّد كلُّه عريضاً أُزيل، وإلا صار كلُّه عريضاً (كما في Word).
  void _toggle(BtTable t, String key) {
    final s = hub.sel!;
    final cells = [
      for (final m in t.masters)
        if (m.row >= s.top && m.row <= s.bottom && m.col >= s.left && m.col <= s.right) m.cell
    ];
    final all = cells.isNotEmpty && cells.every((c) => c.inlineStyle?[key] == true);
    _format({key: all ? null : true});
  }

  Future<void> _sum(BuildContext context, BtTable t, BtSlot head) async {
    if (head.cell.formula != null) {
      final choice = await _choose(context, 'الجمع الحيّ', {'change': 'تغيير العمود المجموع', 'remove': 'إزالة الجمع'});
      if (choice == 'remove') {
        hub.apply((t, _) => BtOps.setSum(t, head.cell.id, null));
        return;
      }
      if (choice != 'change' || !context.mounted) return;
    }
    final col = await showBtSumDialog(context, t, head.cell.formula?.col ?? head.col);
    if (col != null) hub.apply((t, _) => BtOps.setSum(t, head.cell.id, col));
  }

  Future<void> _words(BuildContext context, BtTable t, BtSlot head) async {
    if (head.cell.words != null) {
      final choice = await _choose(context, 'المبلغ كتابةً', {'edit': 'تعديل', 'remove': 'إزالة'});
      if (choice == 'remove') {
        hub.apply((t, _) => BtOps.setWords(t, head.cell.id, null));
        return;
      }
      if (choice != 'edit' || !context.mounted) return;
    }
    final w = await showBtWordsDialog(context, hub, t, head.cell);
    if (w != null) hub.apply((t, _) => BtOps.setWords(t, head.cell.id, w));
  }

  Future<void> _deleteTable(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الجدول'),
        content: const Text('سيُحذف الجدول كاملاً من الكتاب. يمكنك التراجع بـCtrl+Z.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('bt-delete-table-ok'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) hub.deleteTable();
  }

  static Future<String?> _choose(BuildContext context, String title, Map<String, String> options) => showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(title),
          children: [
            for (final e in options.entries)
              SimpleDialogOption(key: Key('bt-choose-${e.key}'), onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
          ],
        ),
      );

  // ─────────────────────────── القوائم ───────────────────────────

  Widget _menu<T>(String key, IconData icon, String tip, Map<T, String> items, {T? current, required ValueChanged<T> onPick}) =>
      PopupMenuButton<T>(
        key: Key(key),
        tooltip: tip,
        icon: Icon(icon, size: 18),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 160),
        onSelected: onPick,
        itemBuilder: (_) => [
          for (final e in items.entries)
            CheckedPopupMenuItem<T>(value: e.key, checked: current != null && e.key == current, child: Text(e.value)),
        ],
      );

  Widget _colorMenu(String key, IconData icon, String tip, List<String> colors, {required String noneLabel, required ValueChanged<String?> onPick}) =>
      PopupMenuButton<String>(
        key: Key(key),
        tooltip: tip,
        icon: Icon(icon, size: 18),
        padding: const EdgeInsets.all(4),
        onSelected: (v) => onPick(v.isEmpty ? null : v),
        itemBuilder: (_) => [
          PopupMenuItem<String>(value: '', child: Text(noneLabel)),
          for (final hex in colors)
            PopupMenuItem<String>(
              key: Key('$key-$hex'),
              value: hex,
              child: Row(children: [
                Container(width: 22, height: 16, decoration: BoxDecoration(color: btParseColor(hex), border: Border.all(color: Colors.black26))),
                const SizedBox(width: 10),
                Text(hex, textDirection: TextDirection.ltr),
              ]),
            ),
        ],
      );

  Widget _bordersMenu(BtTable t) => PopupMenuButton<String>(
        key: const Key('bt-borders'),
        tooltip: 'حدود الجدول (السُّمك واللون)',
        icon: const Icon(Icons.border_all_rounded, size: 18),
        padding: const EdgeInsets.all(4),
        onSelected: (v) {
          if (v.startsWith('w:')) {
            final w = double.parse(v.substring(2));
            hub.apply((t, _) => t.copy()..borderWidthPt = w);
          } else {
            hub.apply((t, _) => t.copy()..borderColor = v.substring(2));
          }
        },
        itemBuilder: (_) => [
          for (final w in const [0.0, 0.5, 0.75, 1.0, 1.5, 2.25, 3.0])
            CheckedPopupMenuItem(
              value: 'w:$w',
              checked: t.borderWidthPt == w,
              child: Text(w == 0 ? 'بلا حدود' : 'سُمك $w نقطة'),
            ),
          const PopupMenuDivider(),
          for (final hex in kBtInkColors)
            CheckedPopupMenuItem(
              value: 'c:$hex',
              checked: t.borderColor.toUpperCase() == hex,
              child: Row(children: [
                Container(width: 22, height: 4, color: btParseColor(hex)),
                const SizedBox(width: 10),
                const Text('لون الحدود'),
              ]),
            ),
        ],
      );

  Widget _headerMenu(BtTable t, BtSelection s) => PopupMenuButton<String>(
        key: const Key('bt-header'),
        tooltip: 'صفوف العناوين وتكرارها',
        icon: const Icon(Icons.table_rows_rounded, size: 18),
        padding: const EdgeInsets.all(4),
        onSelected: (v) {
          switch (v) {
            case 'upto':
              final n = s.bottom + 1;
              final problem = BtOps.headerRowsProblem(t, n);
              if (problem != null) {
                hub.onMessage?.call(problem);
              } else {
                hub.apply((t, _) => BtOps.setHeaderRows(t, n));
              }
            case 'none':
              hub.apply((t, _) => BtOps.setHeaderRows(t, 0));
            case 'repeat':
              hub.apply((t, _) => t.copy()..repeatHeader = !t.repeatHeader);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'upto', child: Text('العناوين: الصفوف حتى الصفّ ${s.bottom + 1}')),
          CheckedPopupMenuItem(value: 'none', checked: t.headerRows == 0, child: const Text('بلا صفّ عناوين')),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            key: const Key('bt-header-repeat'),
            value: 'repeat',
            checked: t.repeatHeader,
            enabled: t.headerRows > 0,
            child: const Text('تكرار العناوين في كل صفحة'),
          ),
        ],
      );

  Widget _widthMenu(BtTable t) => PopupMenuButton<String>(
        key: const Key('bt-width'),
        tooltip: 'عرض الجدول ومحاذاته',
        icon: const Icon(Icons.fit_screen_rounded, size: 18),
        padding: const EdgeInsets.all(4),
        onSelected: (v) {
          if (v.startsWith('p:')) {
            final p = int.parse(v.substring(2));
            hub.apply((t, _) => t.copy()..widthPct = p);
          } else {
            hub.apply((t, _) => t.copy()..align = v.substring(2));
          }
        },
        itemBuilder: (_) => [
          for (final p in const [100, 90, 80, 70, 60, 50, 40])
            CheckedPopupMenuItem(value: 'p:$p', checked: t.widthPct == p, child: Text('العرض $p%')),
          const PopupMenuDivider(),
          for (final a in const {'start': 'إلى اليمين', 'center': 'في الوسط', 'end': 'إلى اليسار'}.entries)
            CheckedPopupMenuItem(value: 'a:${a.key}', checked: t.align == a.key, enabled: t.widthPct < 100, child: Text(a.value)),
        ],
      );
}
