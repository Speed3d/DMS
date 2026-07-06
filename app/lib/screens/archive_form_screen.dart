import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// Hint: شاشة إضافة مستند أرشيف جديد أو تعديله باستخدام التصميم المنقسم (Split Layout) ومحرر النصوص (Quill)
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
  final _quillController = quill.QuillController.basic();

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
      
      // Hint: إضافة النص المحفوظ إلى محرر النصوص
      if (e.bodyHtml != null && e.bodyHtml!.isNotEmpty) {
        final text = e.bodyHtml!.replaceAll('<br>', '\n');
        _quillController.document.insert(0, text);
      }
    }
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _title.dispose(); 
    _bookNumber.dispose(); 
    _amount.dispose();
    _rate.dispose(); 
    _keywords.dispose(); 
    _notes.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    return _Refs(await api.entities(), await api.documentTypes());
  }

  /// Hint: تحويل من محرر Quill إلى نص/HTML مبسط للإرسال للسيرفر
  String? _getHtmlFromBody() {
    if (_quillController.document.isEmpty()) return null;
    return _quillController.document.toPlainText().replaceAll('\n', '<br>');
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) { setState(() => _error = 'عنوان المستند مطلوب.'); return; }
    
    num? amount; num? rate;
    if (_amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'صيغة المبلغ غير صالحة.'); return; }
      if (_currency == null) { setState(() => _error = 'يرجى اختيار العملة.'); return; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي عند اختيار الدولار.'); return; }
      }
    }

    final bodyHtml = _getHtmlFromBody();

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
      'bodyHtml': bodyHtml,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل مستند الأرشيف' : 'أرشفة مستند جديد'),
        centerTitle: true,
      ),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ أثناء تحميل البيانات المرجعية: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;
          
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isSmall = constraints.maxWidth < 800;
                  
                  final basicInfoCard = CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.navyDeep.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.info_outline_rounded, color: AppColors.navyDeep),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(child: Text('المعلومات الأساسية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const Divider(height: 32),
                        
                        TextField(
                          controller: _title,
                          decoration: _inputDecoration('عنوان المستند', Icons.title_rounded),
                        ),
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _bookNumber,
                          decoration: _inputDecoration('رقم الكتاب (اختياري)', Icons.numbers_rounded),
                        ),
                        const SizedBox(height: 16),
                        
                        InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _bookDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.navyDeep),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (d != null) setState(() => _bookDate = d);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: _inputDecoration('تاريخ الكتاب', Icons.calendar_today_rounded),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_bookDate == null ? '— غير محدد —' : DateFormat('yyyy/MM/dd').format(_bookDate!), style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (_bookDate != null)
                                  InkWell(
                                    onTap: () => setState(() => _bookDate = null),
                                    child: const Icon(Icons.clear_rounded, size: 20, color: Colors.grey),
                                  )
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        DropdownButtonFormField<int?>(
                          isExpanded: true,
                          initialValue: _documentTypeId,
                          decoration: _inputDecoration('نوع المستند', Icons.category_rounded),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— لا شيء —')),
                            ...refs.types.map((t) => DropdownMenuItem<int?>(value: t.documentTypeId, child: Text(t.name))),
                          ],
                          onChanged: (v) => setState(() => _documentTypeId = v),
                        ),
                      ],
                    ),
                  );

                  final routingCard = CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.navyDeep.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.compare_arrows_rounded, color: AppColors.navyDeep),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(child: Text('تفاصيل التوجيه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const Divider(height: 32),
                        
                        DropdownButtonFormField<int?>(
                          isExpanded: true,
                          initialValue: _fromEntityId,
                          decoration: _inputDecoration('الجهة الصادرة', Icons.outbox_rounded),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— لا شيء —')),
                            ...refs.entities.map((e) => DropdownMenuItem<int?>(value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(() => _fromEntityId = v),
                        ),
                        const SizedBox(height: 16),
                        
                        DropdownButtonFormField<int?>(
                          isExpanded: true,
                          initialValue: _toEntityId,
                          decoration: _inputDecoration('الجهة المستلمة', Icons.move_to_inbox_rounded),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— لا شيء —')),
                            ...refs.entities.map((e) => DropdownMenuItem<int?>(value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(() => _toEntityId = v),
                        ),
                      ],
                    ),
                  );

                  final financialCard = CustomCard(
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
                            const Flexible(child: Text('التفاصيل الإضافية (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const Divider(height: 32),
                        
                        Builder(builder: (context) {
                          final children = [
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
                                  DropdownMenuItem(value: 'IQD', child: Text('دينار', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'USD', child: Text('دولار', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => _currency = v),
                              ),
                            ),
                          ];
                          if (isSmall) {
                            return Column(children: children.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: e)).toList());
                          }
                          return Row(children: children);
                        }),
                        if (_currency == 'USD') ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _rate,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('سعر الصرف لدينار', Icons.price_change_rounded),
                          ),
                        ],
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _keywords,
                          decoration: _inputDecoration('كلمات مفتاحية', Icons.tag_rounded),
                        ),
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _notes,
                          maxLines: 3,
                          decoration: _inputDecoration('ملاحظات (اختياري)', Icons.notes_rounded).copyWith(alignLabelWithHint: true),
                        ),
                      ],
                    ),
                  );

                  final editorSection = CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.edit_document, color: AppColors.navyDeep),
                            const SizedBox(width: 12),
                            const Flexible(child: Text('محتوى الأرشيف (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const Spacer(),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const Divider(height: 24),
                        
                        // Hint: شريط أدوات Quill Editor
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: quill.QuillSimpleToolbar(
                              controller: _quillController,
                            ),
                          ),
                        ),
                        
                        // Hint: مساحة العمل للكتابة
                        Container(
                          height: isSmall ? 400 : null,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: theme.dividerColor),
                              right: BorderSide(color: theme.dividerColor),
                              bottom: BorderSide(color: theme.dividerColor),
                            ),
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: quill.QuillEditor.basic(
                            controller: _quillController,
                          ),
                        ),
                      ],
                    ),
                  );

                  final saveButton = SizedBox(
                    width: double.infinity,
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
                        _busy ? 'جارٍ الحفظ...' : 'حفظ المستند في الأرشيف',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );

                  if (isSmall) {
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      children: [
                        basicInfoCard,
                        const SizedBox(height: 24),
                        routingCard,
                        const SizedBox(height: 24),
                        financialCard,
                        const SizedBox(height: 24),
                        editorSection,
                        const SizedBox(height: 24),
                        saveButton,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // القسم الأيمن (البيانات الأساسية وتفاصيل التوجيه)
                      Expanded(
                        flex: 4,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          children: [
                            basicInfoCard,
                            const SizedBox(height: 24),
                            routingCard,
                            const SizedBox(height: 24),
                            financialCard,
                          ],
                        ),
                      ),
                      
                      // القسم الأيسر (المحرر والنص)
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24, top: 32, bottom: 32),
                          child: Column(
                            children: [
                              Expanded(child: editorSection),
                              const SizedBox(height: 24),
                              saveButton,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
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
  final List<DocumentTypeModel> types;
  _Refs(this.entities, this.types);
}
