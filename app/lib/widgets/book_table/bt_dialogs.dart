import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_formulas.dart';
import '../../core/book_table/table_ops.dart';
import '../../core/theme.dart';
import 'bt_editor_hub.dart';

/// نافذة «إدراج جدول» (ADR-057): شبكةٌ لاختيار الصفوف × الأعمدة — أو **جدول فاتورة جاهز** بشكل نموذج المالك.
Future<BtTable?> showBtInsertDialog(BuildContext context) => showDialog<BtTable>(context: context, builder: (_) => const _InsertDialog());

class _InsertDialog extends StatefulWidget {
  const _InsertDialog();
  @override
  State<_InsertDialog> createState() => _InsertDialogState();
}

class _InsertDialogState extends State<_InsertDialog> {
  static const _gridCols = 10, _gridRows = 8;
  int _rows = 3, _cols = 3;
  int? _hoverR, _hoverC;
  bool _header = true;
  late final _rowsField = TextEditingController(text: '$_rows');
  late final _colsField = TextEditingController(text: '$_cols');

  @override
  void dispose() {
    _rowsField.dispose();
    _colsField.dispose();
    super.dispose();
  }

  void _pick(int r, int c) => setState(() {
        _rows = r;
        _cols = c;
        _rowsField.text = '$r';
        _colsField.text = '$c';
      });

  @override
  Widget build(BuildContext context) {
    final action = AppColors.action(context);
    final showR = _hoverR ?? _rows, showC = _hoverC ?? _cols;
    return AlertDialog(
      title: const Text('إدراج جدول'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$showR صفوف × $showC أعمدة', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Center(
              child: MouseRegion(
                onExit: (_) => setState(() => _hoverR = _hoverC = null),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 1; r <= _gridRows; r++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var c = 1; c <= _gridCols; c++)
                            MouseRegion(
                              onEnter: (_) => setState(() {
                                _hoverR = r;
                                _hoverC = c;
                              }),
                              child: GestureDetector(
                                key: ValueKey('bt-pick-$r-$c'),
                                onTap: () => _pick(r, c),
                                child: Container(
                                  width: 24,
                                  height: 20,
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: r <= showR && c <= showC ? action.withValues(alpha: 0.25) : null,
                                    border: Border.all(color: r <= showR && c <= showC ? action : Colors.grey.shade400),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _number('الصفوف', _rowsField, 600, (v) => setState(() => _rows = v))),
              const SizedBox(width: 12),
              Expanded(child: _number('الأعمدة', _colsField, 30, (v) => setState(() => _cols = v))),
            ]),
            CheckboxListTile(
              key: const Key('bt-insert-header'),
              contentPadding: EdgeInsets.zero,
              value: _header,
              onChanged: (v) => setState(() => _header = v ?? true),
              title: const Text('الصفّ الأوّل عناوين'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(),
            OutlinedButton.icon(
              key: const Key('bt-insert-invoice'),
              onPressed: () => Navigator.pop(context, BtOps.invoice()),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('جدول فاتورة جاهز'),
            ),
            const SizedBox(height: 4),
            Text('ت · المادة بالإنجليزي · المادة بالعربي · الكمية · سعر المفرد · السعر الكلي — وصفّ مجموعٍ بالجمع والمبلغ كتابةً.',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          key: const Key('bt-insert-ok'),
          onPressed: () => Navigator.pop(context, BtOps.blank(_rows, _cols, header: _header)),
          child: const Text('إدراج'),
        ),
      ],
    );
  }

  Widget _number(String label, TextEditingController c, int max, ValueChanged<int> onChanged) => TextField(
        controller: c,
        decoration: InputDecoration(labelText: label, helperText: 'حتى $max', isDense: true),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) onChanged(n.clamp(1, max));
        },
      );
}

/// اسم العمود للمستخدم: نصّ صفّ العناوين فوقه — وإلا رقمه.
String btColumnLabel(BtTable t, int col) {
  for (var r = 0; r < t.headerRows; r++) {
    final o = t.ownerOf(r, col);
    if (o != null && o.cell.colSpan == 1 && o.cell.text.isNotEmpty) return o.cell.text.replaceAll('\n', ' ');
  }
  return 'العمود ${col + 1}';
}

/// نافذة Σ: **أيُّ عمودٍ يُجمع** — مقترَحاً عمودُ الخلية نفسها (في الفاتورة خليةُ المجموع تحت عمودٍ آخر، فالاختيار لازم).
Future<int?> showBtSumDialog(BuildContext context, BtTable t, int suggested) {
  var col = suggested.clamp(0, t.colCount - 1);
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('جمعٌ حيّ (Σ)'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<int>(
              key: const Key('bt-sum-col'),
              initialValue: col,
              decoration: const InputDecoration(labelText: 'اجمع العمود'),
              items: [for (var i = 0; i < t.colCount; i++) DropdownMenuItem(value: i, child: Text(btColumnLabel(t, i), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => col = v ?? col),
            ),
            const SizedBox(height: 10),
            Text('يُجمع كل رقمٍ فوق الخلية في هذا العمود حتى صفّ العناوين — وتُتخطّى الخلايا الفارغة والنصّية والمجاميع الأخرى. '
                'ويتحدّث وحده مع كل تعديل.',
                style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(key: const Key('bt-sum-ok'), onPressed: () => Navigator.pop(c, col), child: const Text('تطبيق')),
        ],
      ),
    ),
  );
}

/// نافذة «كتابة بالحروف»: الخلية المصدر · العملة · ونصّا «قبل» و«بعد» — **والمعاينة من الخادم** وهي تُكتب.
Future<BtWords?> showBtWordsDialog(BuildContext context, BtEditorHub hub, BtTable t, BtCell target) =>
    showDialog<BtWords>(context: context, builder: (_) => _WordsDialog(hub: hub, table: t, target: target));

class _WordsDialog extends StatefulWidget {
  const _WordsDialog({required this.hub, required this.table, required this.target});
  final BtEditorHub hub;
  final BtTable table;
  final BtCell target;
  @override
  State<_WordsDialog> createState() => _WordsDialogState();
}

class _WordsDialogState extends State<_WordsDialog> {
  late final List<(String, String)> _sources;
  String? _source;
  late String _currency;
  // فارغان افتراضاً كنموذج المالك («تسعة مليارات … دينار عراقي») — والمثال في تلميح الحقل
  late final _prefix = TextEditingController(text: widget.target.words?.prefix ?? '');
  late final _suffix = TextEditingController(text: widget.target.words?.suffix ?? '');
  String? _preview;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.table;
    final computed = BtFormulas.evaluate(t);
    _sources = [
      for (final s in t.masters)
        if (s.cell.id != widget.target.id && s.cell.formula != null)
          (s.cell.id, 'Σ ${btColumnLabel(t, s.cell.formula!.col)} — ${computed[s.cell.id]?.text ?? ''}')
        else if (s.cell.id != widget.target.id && s.cell.words == null && BtFormulas.parseNumber(s.cell.text) != null && s.row >= t.headerRows)
          (s.cell.id, '«${s.cell.text}» — الصفّ ${s.row + 1}'),
    ].take(60).toList();
    _source = widget.target.words?.sourceCellId ?? BtOps.suggestWordsSource(t, widget.target.id) ?? (_sources.isEmpty ? null : _sources.first.$1);
    if (!_sources.any((s) => s.$1 == _source)) _source = _sources.isEmpty ? null : _sources.first.$1;
    _currency = widget.target.words?.currency ?? 'IQD';
    _prefix.addListener(_refresh);
    _suffix.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _prefix.dispose();
    _suffix.dispose();
    super.dispose();
  }

  BtWords? get _value => _source == null
      ? null
      : BtWords(
          sourceCellId: _source!,
          currency: _currency,
          prefix: _prefix.text.trim().isEmpty ? null : _prefix.text.trim(),
          suffix: _suffix.text.trim().isEmpty ? null : _suffix.text.trim(),
        );

  void _refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final w = _value;
      if (w == null) return;
      final v = BtFormulas.wordsSource(widget.table, w);
      final seq = ++_seq;
      final core = v == null ? null : await widget.hub.wordsText(v, w.currency);
      if (!mounted || seq != _seq) return;
      setState(() => _preview = [w.prefix, core ?? (v == null ? '(لا رقم في الخلية المصدر بعد)' : '…'), w.suffix]
          .where((x) => x != null && x.isNotEmpty)
          .join(' '));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('المبلغ كتابةً'),
      content: SizedBox(
        width: 420,
        child: _sources.isEmpty
            ? const Text('لا خلية جمعٍ ولا رقمَ في الجدول بعد — أضِف Σ أولاً ثم اكتب المبلغ بالحروف.')
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String>(
                  key: const Key('bt-words-source'),
                  initialValue: _source,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الرقم المصدر'),
                  items: [for (final s in _sources) DropdownMenuItem(value: s.$1, child: Text(s.$2, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    setState(() => _source = v);
                    _refresh();
                  },
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  key: const Key('bt-words-currency'),
                  segments: const [
                    ButtonSegment(value: 'IQD', label: Text('دينار عراقي')),
                    ButtonSegment(value: 'USD', label: Text('دولار أمريكي')),
                  ],
                  selected: {_currency},
                  onSelectionChanged: (s) {
                    setState(() => _currency = s.first);
                    _refresh();
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('bt-words-prefix'),
                      controller: _prefix,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: 'قبل المبلغ', hintText: 'مثلاً: فقط', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('bt-words-suffix'),
                      controller: _suffix,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: 'بعد المبلغ', hintText: 'مثلاً: لا غير', isDense: true),
                    ),
                  ),
                ]),
                Container(
                  key: const Key('bt-words-preview'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(_preview ?? '…', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                Text('النصّ يتحدّث وحده مع المجموع — والطباعة تولّده من الخادم نفسه.',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        if (_sources.isNotEmpty)
          FilledButton(key: const Key('bt-words-ok'), onPressed: () => Navigator.pop(context, _value), child: const Text('تطبيق')),
      ],
    );
  }
}

/// «إدراجه جدولاً؟» عند لصق جدولٍ في نصٍّ عاديّ.
Future<bool> showBtPasteAsTableDialog(BuildContext context, int rows, int cols) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('لصق جدول'),
        content: Text('في الحافظة جدولٌ من $rows صفوف و$cols أعمدة. هل تريد إدراجه جدولاً في الكتاب؟'),
        actions: [
          TextButton(key: const Key('bt-paste-as-text'), onPressed: () => Navigator.pop(c, false), child: const Text('نصّاً عاديّاً')),
          FilledButton(key: const Key('bt-paste-as-table'), onPressed: () => Navigator.pop(c, true), child: const Text('جدولاً')),
        ],
      ),
    ) ??
    false;
