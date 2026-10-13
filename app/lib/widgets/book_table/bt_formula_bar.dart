import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/book_table/table_formula_text.dart';
import '../../core/book_table/table_formulas.dart';
import '../../core/theme.dart';
import 'bt_editor_hub.dart';

/// شريط المعادلة (ADR-060) — يظهر تحت شريط الجدول ما دامت معادلةٌ تُكتب.
///
/// اكتب `=` في خلية (أو زرّ «معادلة») ⟵ اكتب المعادلة أو **انقر الخلايا لإدراجها** ⟵ أزرار `+ − × ÷ ( )` ⟵ **الناتج يظهر
/// وأنت تكتب** ⟵ «تطبيق» (Enter) أو «إلغاء» (Esc). و«للعمود كلّه» يجعلها معادلةً لكل صفوف البند في العمود.
class BtFormulaBar extends StatelessWidget {
  const BtFormulaBar({super.key, required this.hub});
  final BtEditorHub hub;

  @override
  Widget build(BuildContext context) {
    final f = hub.formula;
    final t = f == null ? null : hub.locate(f.tableId)?.table;
    if (f == null || t == null) return const SizedBox.shrink();
    final action = AppColors.action(context);
    final target = f.column
        ? 'العمود ${btColumnLetter(f.col)} — كلُّ صفوف البنود'
        : 'الخلية ${BtFormulaText.address(f.row, f.col)}';

    Widget op(String label, String insert, String key) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: OutlinedButton(
            key: Key('bt-formula-op-$key'),
            onPressed: () => hub.formulaInsert(insert),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(34, 30),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        );

    return Container(
      key: const Key('bt-formula-bar'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: action.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: action.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('معادلة', style: TextStyle(fontWeight: FontWeight.bold, color: action, fontSize: 12.5)),
              Text(target, key: const Key('bt-formula-target'), style: const TextStyle(fontSize: 12.5)),
              FilterChip(
                key: const Key('bt-formula-column'),
                label: const Text('للعمود كلّه', style: TextStyle(fontSize: 12)),
                tooltip: 'معادلةٌ واحدة لكل صفوف البنود في هذا العمود — والصفّ الجديد يأخذها تلقائياً',
                selected: f.column,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => hub.toggleFormulaColumn(),
              ),
              Text(
                f.column ? 'انقر عموداً لإدراجه (مثل C × D)' : 'انقر خليةً لإدراجها (مثل C2 × D2)',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): hub.closeFormula,
            },
            child: TextField(
              key: const Key('bt-formula-input'),
              controller: f.text,
              focusNode: f.focus,
              // المعادلة تُقرأ من اليسار كالإكسل — حروف الأعمدة والأرقام والعمليات لاتينية
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              onSubmitted: (_) => hub.applyFormula(),
              // 🔴 النقر على خليةٍ يُدرج مرجعها — فلا يفقد الحقل تركيزه بالنقر خارجه
              onTapOutside: (_) {},
              decoration: InputDecoration(
                isDense: true,
                prefixText: '= ',
                hintText: f.column ? 'C × D' : 'C2 × D2',
                border: const OutlineInputBorder(),
                errorText: f.error,
                errorMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              op('+', '+', 'plus'),
              op('−', '-', 'minus'),
              op('×', '×', 'times'),
              op('÷', '÷', 'divide'),
              op('(', '(', 'open'),
              op(')', ')', 'close'),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: f.text,
                builder: (context, v, _) => _Preview(hub: hub, text: v.text),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: [
              if (f.existing)
                TextButton.icon(
                  key: const Key('bt-formula-remove'),
                  onPressed: hub.removeFormula,
                  icon: const Icon(Icons.backspace_outlined, size: 16),
                  label: Text(f.column ? 'إزالة معادلة العمود' : 'إزالة المعادلة'),
                ),
              TextButton(key: const Key('bt-formula-cancel'), onPressed: hub.closeFormula, child: const Text('إلغاء')),
              FilledButton.icon(
                key: const Key('bt-formula-apply'),
                onPressed: hub.applyFormula,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('تطبيق'),
                style: FilledButton.styleFrom(
                  backgroundColor: action,
                  foregroundColor: AppColors.onAction(context),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// الناتج قبل التطبيق — أو سبب عدم صلاحية المعادلة.
class _Preview extends StatelessWidget {
  const _Preview({required this.hub, required this.text});
  final BtEditorHub hub;
  final String text;

  @override
  Widget build(BuildContext context) {
    final f = hub.formula;
    final t = f == null ? null : hub.locate(f.tableId)?.table;
    if (f == null || t == null || text.trim().isEmpty || text.trim() == '=') return const SizedBox.shrink();
    String shown;
    var bad = false;
    try {
      final stored = BtFormulaText.toStorage(hub.current(t), text, column: f.column);
      final c = BtFormulaText.preview(hub.current(t), stored, cellId: f.column ? null : f.cellId, col: f.column ? f.col : null, row: f.row);
      if (c == null) {
        shown = 'لا صفوف بنودٍ في هذا العمود بعد';
      } else if (c.isError) {
        shown = '${c.text} — ${calcErrorMessage(c.error!)}';
        bad = true;
      } else {
        shown = '= ${c.text.isEmpty ? '(فارغ حتى تُكتب الأرقام)' : c.text}';
      }
    } on BtExprError catch (e) {
      shown = e.message;
      bad = true;
    }
    return Text(
      shown,
      key: const Key('bt-formula-preview'),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: bad ? AppColors.danger : AppColors.action(context),
      ),
    );
  }
}
