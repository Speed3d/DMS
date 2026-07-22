import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// Hint: شاشة إضافة أو تعديل كتاب وارد
class IncomingFormScreen extends ConsumerStatefulWidget {
  final int? bookId;
  const IncomingFormScreen({super.key, this.bookId});
  @override
  ConsumerState<IncomingFormScreen> createState() => _IncomingFormScreenState();
}

class _IncomingFormScreenState extends ConsumerState<IncomingFormScreen> {
  final _subject = TextEditingController();
  final _externalNumber = TextEditingController();
  final _folderName = TextEditingController();
  final _keywords = TextEditingController();
  final _notes = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();

  DateTime _receivedDate = DateTime.now();
  TimeOfDay? _receivedTime = TimeOfDay.now();
  DateTime? _externalDate;

  int? _entityId;
  String _entitySearchText = '';
  
  int? _documentTypeId;
  /// Hint: القيمة تُرسل كما هي للباك-إند — يجب أن تبقى دائماً أحد مفاتيح [kReceiveMethods].
  String _receiveMethod = kDefaultReceiveMethod;
  String? _currency;
  
  bool _showFinancials = false;
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
    try {
      final entities = await api.entities();
      final docTypes = await api.documentTypes();
      
      if (widget.bookId != null) {
        final d = await api.incomingGet(widget.bookId!);
        _subject.text = d.subject;
        _externalNumber.text = d.externalNumber ?? '';
        _folderName.text = d.folderName ?? '';
        _keywords.text = d.keywords ?? '';
        _notes.text = d.notes ?? '';
        _receivedDate = d.receivedDate;
        
        if (d.receivedTime != null) {
          final parts = d.receivedTime!.split(':');
          if (parts.length >= 2) {
            _receivedTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
          }
        } else {
          _receivedTime = null;
        }

        _externalDate = d.externalDate;
        _entityId = d.entityId;
        _entitySearchText = d.entityName;
        _documentTypeId = d.documentTypeId;
        // Hint: حماية من قيمة غير معروفة (بيانات قديمة) — الـ Dropdown يتطلب قيمة ضمن عناصره وإلا تحطّمت الشاشة.
        _receiveMethod = kReceiveMethods.containsKey(d.receiveMethod) ? d.receiveMethod : kDefaultReceiveMethod;
        
        if (d.amount != null) {
          _showFinancials = true;
          _amount.text = d.amount.toString();
          _currency = d.currency;
          if (d.exchangeRate != null) _rate.text = d.exchangeRate.toString();
        }
      }

      return _Refs(entities, docTypes);
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic>? _buildPayload() {
    if (_entityId == null) {
      setState(() => _error = 'يرجى تحديد الجهة المرسلة (مصدر الكتاب).');
      return null;
    }
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'موضوع الكتاب مطلوب.');
      return null;
    }
    
    num? amount;
    num? rate;
    if (_showFinancials && _amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'صيغة المبلغ غير صالحة.'); return null; }
      if (_currency == null) { setState(() => _error = 'يرجى اختيار العملة.'); return null; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي للدولار.'); return null; }
      }
    }

    String? timeStr;
    if (_receivedTime != null) {
      final h = _receivedTime!.hour.toString().padLeft(2, '0');
      final m = _receivedTime!.minute.toString().padLeft(2, '0');
      timeStr = '$h:$m:00';
    }

    return {
      'receivedDate': _receivedDate.toIso8601String(),
      'receivedTime': timeStr,
      'externalNumber': _externalNumber.text.trim().isEmpty ? null : _externalNumber.text.trim(),
      'externalDate': _externalDate?.toIso8601String(),
      'entityId': _entityId,
      'documentTypeId': _documentTypeId,
      'receiveMethod': _receiveMethod,
      'subject': _subject.text.trim(),
      'folderName': _folderName.text.trim().isEmpty ? null : _folderName.text.trim(),
      'keywords': _keywords.text.trim().isEmpty ? null : _keywords.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'amount': amount,
      'currency': amount == null ? null : _currency,
      'exchangeRate': rate,
    };
  }

  Future<void> _save() async {
    if (_entitySearchText.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال الجهة المرسلة.');
      return;
    }

    setState(() { _busy = true; _error = null; });
    
    try {
      final api = ref.read(apiClientProvider);
      if (_entityId == null) {
        final newE = await api.createEntity(_entitySearchText.trim(), 'Both');
        _entityId = newE.entityId;
      }

      final payload = _buildPayload();
      if (payload == null) {
        setState(() => _busy = false);
        return;
      }

      if (widget.bookId == null) {
        await api.createIncoming(payload);
      } else {
        await api.updateIncoming(widget.bookId!, payload);
      }
      
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookId == null ? 'تسجيل كتاب وارد جديد' : 'تعديل الكتاب الوارد'),
        centerTitle: true,
      ),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ أثناء تحميل البيانات: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;
          
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),

                  CustomCard(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('البيانات الأساسية للوارد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Divider(height: 32),
                        
                        // الجهة
                        Autocomplete<EntityModel>(
                          displayStringForOption: (e) => e.name,
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return refs.entities;
                            return refs.entities.where((e) => e.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (e) {
                            _entityId = e.entityId;
                            _entitySearchText = e.name;
                          },
                          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                            textEditingController.addListener(() {
                              _entitySearchText = textEditingController.text;
                              final matching = refs.entities.where((e) => e.name == textEditingController.text.trim());
                              if (matching.isNotEmpty) {
                                _entityId = matching.first.entityId;
                              } else {
                                _entityId = null;
                              }
                            });
                            if (_entityId != null && textEditingController.text.isEmpty) {
                              final selectedE = refs.entities.cast<EntityModel?>().firstWhere((e) => e?.entityId == _entityId, orElse: () => null);
                              if (selectedE != null) textEditingController.text = selectedE.name;
                            }
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: _inputDecoration('الجهة المُرسلة (المصدر)', Icons.business_rounded),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // الموضوع
                        TextField(
                          controller: _subject,
                          decoration: _inputDecoration('موضوع الكتاب', Icons.subject_rounded),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context, initialDate: _receivedDate,
                                    firstDate: DateTime(2000), lastDate: DateTime(2100),
                                  );
                                  if (d != null) setState(() => _receivedDate = d);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('تاريخ الاستلام', Icons.calendar_month_rounded),
                                  child: Text(DateFormat('yyyy/MM/dd').format(_receivedDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _receivedTime ?? TimeOfDay.now(),
                                  );
                                  setState(() => _receivedTime = t);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('وقت الاستلام', Icons.access_time_rounded),
                                  child: Text(_receivedTime?.format(context) ?? 'غير محدد', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _externalNumber,
                                decoration: _inputDecoration('رقم الكتاب الخارجي', Icons.tag_rounded),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context, initialDate: _externalDate ?? DateTime.now(),
                                    firstDate: DateTime(2000), lastDate: DateTime(2100),
                                  );
                                  if (d != null) setState(() => _externalDate = d);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('تاريخ الكتاب الخارجي', Icons.event_note_rounded),
                                  child: Text(_externalDate == null ? 'غير محدد' : DateFormat('yyyy/MM/dd').format(_externalDate!), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _receiveMethod,
                                decoration: _inputDecoration('طريقة الاستلام', Icons.inbox_rounded),
                                // Hint: تُبنى من الثوابت المشتركة لضمان تطابقها مع الباك-إند
                                items: kReceiveMethods.entries
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: (v) => setState(() => _receiveMethod = v!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                isExpanded: true,
                                initialValue: _documentTypeId,
                                decoration: _inputDecoration('نوع المستند (اختياري)', Icons.category_rounded),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('غير محدد')),
                                  ...refs.docTypes.map((t) => DropdownMenuItem(value: t.documentTypeId, child: Text(t.name))),
                                ],
                                onChanged: (v) => setState(() => _documentTypeId = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _folderName,
                          decoration: _inputDecoration('القسم المحال إليه (الإحالة الافتراضية)', Icons.folder_shared_rounded),
                        ),
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _keywords,
                          decoration: _inputDecoration('الكلمات المفتاحية (مفصولة بفاصلة)', Icons.key_rounded),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _notes,
                          maxLines: 2,
                          decoration: _inputDecoration('ملاحظات إضافية', Icons.note_rounded),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // التفاصيل المالية
                  CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), shape: BoxShape.circle),
                              child: const Icon(Icons.monetization_on_rounded, color: AppColors.gold),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(child: Text('التفاصيل المالية (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const Spacer(),
                            Switch(
                              value: _showFinancials,
                              activeThumbColor: AppColors.gold,
                              onChanged: (v) => setState(() => _showFinancials = v),
                            ),
                          ],
                        ),
                        
                        if (_showFinancials) ...[
                          const Divider(height: 32),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _amount,
                                  keyboardType: TextInputType.number,
                                  decoration: _inputDecoration('المبلغ', Icons.payments_rounded),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _currency,
                                  decoration: _inputDecoration('العملة', Icons.currency_exchange_rounded),
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
                            const SizedBox(height: 16),
                            TextField(
                              controller: _rate,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration('سعر الصرف لدينار', Icons.price_change_rounded),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navyDeep,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: AppColors.navyDeep.withValues(alpha: 0.5),
                      ),
                      icon: _busy 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
                        : const Icon(Icons.save_rounded),
                      label: Text(
                        _busy ? 'جارٍ الحفظ...' : 'حفظ الكتاب الوارد',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.navyDeep, width: 1.5)),
    );
  }
}

class _Refs {
  final List<EntityModel> entities;
  final List<DocumentTypeModel> docTypes;
  _Refs(this.entities, this.docTypes);
}
