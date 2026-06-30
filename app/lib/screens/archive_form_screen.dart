import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../models.dart';

class ArchiveFormScreen extends ConsumerStatefulWidget {
  final ArchiveDetail? existing;
  const ArchiveFormScreen({super.key, this.existing});
  @override
  ConsumerState<ArchiveFormScreen> createState() => _State();
}

class _State extends ConsumerState<ArchiveFormScreen> {
  final _title = TextEditingController();
  final _bookNumber = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _keywords = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _bookDate;
  int? _fromEntityId, _toEntityId, _documentTypeId;
  String? _currency;
  bool _busy = false;
  String? _error;
  late Future<_Refs> _refs;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _bookNumber.text = e.bookNumber ?? '';
      _amount.text = e.amount?.toString() ?? '';
      _rate.text = e.exchangeRate?.toString() ?? '';
      _keywords.text = e.keywords ?? '';
      _notes.text = e.notes ?? '';
      _bookDate = e.bookDate;
      _fromEntityId = e.fromEntityId;
      _toEntityId = e.toEntityId;
      _documentTypeId = e.documentTypeId;
      _currency = e.currency;
    }
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _title.dispose(); _bookNumber.dispose(); _amount.dispose();
    _rate.dispose(); _keywords.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    return _Refs(await api.entities(), await api.documentTypes());
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) { setState(() => _error = 'العنوان مطلوب.'); return; }
    num? amount; num? rate;
    if (_amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'المبلغ غير صالح.'); return; }
      if (_currency == null) { setState(() => _error = 'اختر العملة.'); return; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي للدولار.'); return; }
      }
    }
    final body = {
      'title': _title.text.trim(),
      'bookNumber': _bookNumber.text.trim().isEmpty ? null : _bookNumber.text.trim(),
      'bookDate': _bookDate?.toIso8601String(),
      'fromEntityId': _fromEntityId,
      'toEntityId': _toEntityId,
      'documentTypeId': _documentTypeId,
      'amount': amount,
      'currency': amount == null ? null : _currency,
      'exchangeRate': rate,
      'keywords': _keywords.text.trim().isEmpty ? null : _keywords.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    setState(() { _busy = true; _error = null; });
    try {
      if (_isEdit) {
        await ref.read(apiClientProvider).updateArchive(widget.existing!.archiveId, body);
      } else {
        await ref.read(apiClientProvider).createArchive(body);
      }
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
      appBar: AppBar(title: Text(_isEdit ? 'تعديل مستند أرشيف' : 'مستند أرشيف جديد')),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final r = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان')),
                  const SizedBox(height: 12),
                  TextField(controller: _bookNumber, decoration: const InputDecoration(labelText: 'رقم الكتاب (اختياري)')),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text('تاريخ الكتاب: ${_bookDate == null ? 'غير محدد' : DateFormat('yyyy-MM-dd').format(_bookDate!)}')),
                    TextButton(onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: _bookDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (d != null) setState(() => _bookDate = d);
                    }, child: const Text('تحديد')),
                    if (_bookDate != null) TextButton(onPressed: () => setState(() => _bookDate = null), child: const Text('مسح')),
                  ]),
                  const SizedBox(height: 4),
                  _entityDropdown('الجهة الصادرة', _fromEntityId, r.entities, (v) => setState(() => _fromEntityId = v)),
                  const SizedBox(height: 12),
                  _entityDropdown('الجهة المستلمة', _toEntityId, r.entities, (v) => setState(() => _toEntityId = v)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _documentTypeId,
                    decoration: const InputDecoration(labelText: 'نوع المستند'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('— لا شيء —')),
                      ...r.types.map((t) => DropdownMenuItem<int?>(value: t.documentTypeId, child: Text(t.name))),
                    ],
                    onChanged: (v) => setState(() => _documentTypeId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text('الحقول المالية (اختياري)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ'))),
                    const SizedBox(width: 12),
                    Expanded(child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      items: const [DropdownMenuItem(value: 'IQD', child: Text('دينار')), DropdownMenuItem(value: 'USD', child: Text('دولار'))],
                      onChanged: (v) => setState(() => _currency = v),
                    )),
                  ]),
                  if (_currency == 'USD') ...[
                    const SizedBox(height: 12),
                    TextField(controller: _rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر الصرف')),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _keywords, decoration: const InputDecoration(labelText: 'الكلمات المفتاحية (اختياري)')),
                  const SizedBox(height: 12),
                  TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', alignLabelWithHint: true)),
                  if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save), label: Text(_busy ? 'جارٍ...' : 'حفظ')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _entityDropdown(String label, int? value, List<EntityModel> entities, ValueChanged<int?> onChanged) =>
      DropdownButtonFormField<int?>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('— لا شيء —')),
          ...entities.map((e) => DropdownMenuItem<int?>(value: e.entityId, child: Text(e.name))),
        ],
        onChanged: onChanged,
      );
}

class _Refs {
  final List<EntityModel> entities;
  final List<DocumentTypeModel> types;
  _Refs(this.entities, this.types);
}
