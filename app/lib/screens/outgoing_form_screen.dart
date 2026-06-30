import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/local_storage.dart';
import '../models.dart';

class OutgoingFormScreen extends ConsumerStatefulWidget {
  const OutgoingFormScreen({super.key});
  @override
  ConsumerState<OutgoingFormScreen> createState() => _State();
}

class _State extends ConsumerState<OutgoingFormScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  DateTime _date = DateTime.now();
  int? _entityId;
  int? _templateId;
  String? _currency;
  bool _busy = false;
  String? _error;

  late Future<_Refs> _refs;

  @override
  void initState() {
    super.initState();
    _refs = _loadRefs();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(localStorageProvider);
    try {
      final entities = await api.entities();
      final templates = await api.templates();
      await storage.cacheEntities(entities);
      await storage.cacheTemplates(templates);
      return _Refs(entities, templates.where((t) => t.isActive).toList());
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        final cachedEntities = storage.getCachedEntities();
        final cachedTemplates = storage.getCachedTemplates();
        if (cachedEntities.isNotEmpty && cachedTemplates.isNotEmpty) {
          return _Refs(cachedEntities, cachedTemplates.where((t) => t.isActive).toList());
        }
      }
      rethrow;
    }
  }

  Future<void> _save() async {
    if (_entityId == null || _templateId == null) {
      setState(() => _error = 'اختر الجهة والقالب.');
      return;
    }
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
      final payload = {
        'entityId': _entityId,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'subject': _subject.text.trim(),
        'bodyHtml': _body.text,
        'amount': amount,
        'currency': amount == null ? null : _currency,
        'exchangeRate': rate,
      };
      await ref.read(apiClientProvider).createOutgoing(payload);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        final payload = {
          'entityId': _entityId,
          'templateId': _templateId,
          'date': _date.toIso8601String(),
          'subject': _subject.text.trim(),
          'bodyHtml': _body.text,
          'amount': amount,
          'currency': amount == null ? null : _currency,
          'exchangeRate': rate,
        };
        await ref.read(localStorageProvider).saveDraft(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد إنترنت. تم حفظ المسودة محلياً بنجاح.')));
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كتاب صادر جديد')),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final refs = snap.data!;
          if (refs.entities.isEmpty || refs.templates.isEmpty) {
            return const Center(
                child: Text('يلزم وجود جهة وقالب مُفعّل. أضِفهما من الإعدادات أولاً.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _entityId,
                    decoration: const InputDecoration(labelText: 'الجهة المستلمة'),
                    items: refs.entities
                        .map((e) => DropdownMenuItem(value: e.entityId, child: Text(e.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _entityId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _templateId,
                    decoration: const InputDecoration(labelText: 'القالب'),
                    items: refs.templates
                        .map((t) => DropdownMenuItem(value: t.templateId, child: Text(t.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _templateId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}')),
                      TextButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('تغيير'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _subject, decoration: const InputDecoration(labelText: 'الموضوع')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'نص الكتاب', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 20),
                  const Text('الحقول المالية (اختياري)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'المبلغ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(labelText: 'العملة'),
                          items: const [
                            DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                            DropdownMenuItem(value: 'USD', child: Text('دولار')),
                          ],
                          onChanged: (v) => setState(() => _currency = v),
                        ),
                      ),
                    ],
                  ),
                  if (_currency == 'USD') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'سعر الصرف (دينار لكل دولار)'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ المسودّة'),
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
