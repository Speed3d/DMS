import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../models.dart';

/// تعديل كتاب معتمد (Final) — ينشئ إصداراً جديداً ويعيد توليد PDF/QR. الرقم يبقى ثابتاً.
class OutgoingEditApprovedScreen extends ConsumerStatefulWidget {
  final OutgoingDetail book;
  const OutgoingEditApprovedScreen({super.key, required this.book});
  @override
  ConsumerState<OutgoingEditApprovedScreen> createState() => _State();
}

class _State extends ConsumerState<OutgoingEditApprovedScreen> {
  late final TextEditingController _subject;
  late final TextEditingController _body;
  late final TextEditingController _amount;
  late final TextEditingController _rate;
  final _note = TextEditingController();
  late DateTime _date;
  late int _entityId;
  late int _templateId;
  String? _currency;
  bool _busy = false;
  String? _error;
  late Future<_Refs> _refs;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _subject = TextEditingController(text: b.subject);
    _body = TextEditingController(text: b.bodyHtml);
    _amount = TextEditingController(text: b.amount?.toString() ?? '');
    _rate = TextEditingController(text: b.exchangeRate?.toString() ?? '');
    _date = b.date;
    _entityId = b.entityId;
    _templateId = b.templateId;
    _currency = b.currency;
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _subject.dispose(); _body.dispose(); _amount.dispose(); _rate.dispose(); _note.dispose();
    super.dispose();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    final entities = await api.entities();
    final templates = await api.templates();
    return _Refs(entities, templates.where((t) => t.isActive).toList());
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'الموضوع والنص مطلوبان.');
      return;
    }
    num? amount;
    num? rate;
    if (_amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'المبلغ غير صالح.'); return; }
      if (_currency == null) { setState(() => _error = 'اختر العملة.'); return; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي للدولار.'); return; }
      }
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(apiClientProvider).editApproved(widget.book.outgoingId, {
        'entityId': _entityId,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'subject': _subject.text.trim(),
        'bodyHtml': _body.text,
        'amount': amount,
        'currency': amount == null ? null : _currency,
        'exchangeRate': rate,
        'rowVersion': widget.book.rowVersion,
        'changeNote': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تعديل كتاب معتمد ${widget.book.number ?? ''}')),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final refs = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.amber.shade100,
                    child: const Text('سيُحفظ إصدار من النسخة الحالية ويُعاد توليد PDF/QR. الرقم لا يتغيّر.'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _entityId,
                    decoration: const InputDecoration(labelText: 'الجهة المستلمة'),
                    items: refs.entities.map((e) => DropdownMenuItem(value: e.entityId, child: Text(e.name))).toList(),
                    onChanged: (v) => setState(() => _entityId = v ?? _entityId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _templateId,
                    decoration: const InputDecoration(labelText: 'القالب'),
                    items: refs.templates.map((t) => DropdownMenuItem(value: t.templateId, child: Text(t.name))).toList(),
                    onChanged: (v) => setState(() => _templateId = v ?? _templateId),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}')),
                    TextButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) setState(() => _date = d);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('تغيير'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: _subject, decoration: const InputDecoration(labelText: 'الموضوع')),
                  const SizedBox(height: 12),
                  TextField(controller: _body, maxLines: 6, decoration: const InputDecoration(labelText: 'نص الكتاب', alignLabelWithHint: true)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ'))),
                    const SizedBox(width: 12),
                    Expanded(child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      items: const [
                        DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                        DropdownMenuItem(value: 'USD', child: Text('دولار')),
                      ],
                      onChanged: (v) => setState(() => _currency = v),
                    )),
                  ]),
                  if (_currency == 'USD') ...[
                    const SizedBox(height: 12),
                    TextField(controller: _rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر الصرف')),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة التغيير (اختياري)')),
                  if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ التعديل (إصدار جديد)'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Refs {
  final List<EntityModel> entities;
  final List<TemplateModel> templates;
  _Refs(this.entities, this.templates);
}
