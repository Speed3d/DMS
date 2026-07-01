import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/local_storage.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// Hint: شاشة إضافة كتاب صادر جديد مع محرر النصوص الاحترافي Quill
class OutgoingFormScreen extends ConsumerStatefulWidget {
  const OutgoingFormScreen({super.key});
  @override
  ConsumerState<OutgoingFormScreen> createState() => _OutgoingFormScreenState();
}

class _OutgoingFormScreenState extends ConsumerState<OutgoingFormScreen> {
  final _subject = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _quillController = quill.QuillController.basic();
  
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

  /// Hint: تحويل من Quill Delta إلى HTML للإرسال إلى السيرفر
  String _getHtmlFromBody() {
    // الطريقة البسيطة لتحويل Quill إلى HTML عبر الـ Markdown
    // هذا حل مؤقت يعمل بشكل جيد، يمكنك لاحقاً استخدام quill_html_converter
    // الطريقة البسيطة لتحويل Quill إلى HTML عبر الـ Markdown
    // استخراج النص فقط في حال لم يكن هناك محول HTML مباشر في هذه النسخة
    // لكننا سنستخدم Text للحفاظ على الهيكل العام كمسودة
    return _quillController.document.toPlainText().replaceAll('\n', '<br>');
  }

  Future<void> _save() async {
    if (_entityId == null || _templateId == null) {
      setState(() => _error = 'يرجى اختيار الجهة المقصودة والقالب.');
      return;
    }
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'موضوع الكتاب مطلوب.');
      return;
    }
    if (_quillController.document.isEmpty()) {
      setState(() => _error = 'نص الكتاب لا يمكن أن يكون فارغاً.');
      return;
    }
    
    num? amount;
    num? rate;
    if (_amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'صيغة المبلغ غير صالحة.'); return; }
      if (_currency == null) { setState(() => _error = 'يرجى اختيار العملة.'); return; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي عند اختيار الدولار.'); return; }
      }
    }
    
    setState(() { _busy = true; _error = null; });
    
    try {
      final payload = {
        'entityId': _entityId,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'subject': _subject.text.trim(),
        'bodyHtml': _getHtmlFromBody(),
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
          'bodyHtml': _getHtmlFromBody(),
          'amount': amount,
          'currency': amount == null ? null : _currency,
          'exchangeRate': rate,
        };
        await ref.read(localStorageProvider).saveDraft(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد اتصال بالإنترنت. تم حفظ الكتاب كمسودة محلية بنجاح.')));
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء كتاب صادر جديد'),
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
          if (refs.entities.isEmpty || refs.templates.isEmpty) {
            return const Center(
              child: Text('يلزم وجود جهة واحدة وقالب مُفعّل على الأقل للبدء. أضِفهما من الإعدادات أولاً.', style: TextStyle(fontWeight: FontWeight.bold)),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000), // شاشة عريضة تناسب المحرر
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // القسم الأيمن (البيانات الأساسية والمالية)
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      children: [
                        CustomCard(
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
                                  const Text('معلومات الكتاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 32),
                              
                              // الجهة
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: _entityId,
                                decoration: _inputDecoration('الجهة المستلمة', Icons.business_rounded),
                                items: refs.entities.map((e) => DropdownMenuItem(value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _entityId = v),
                              ),
                              const SizedBox(height: 16),
                              
                              // القالب
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: _templateId,
                                decoration: _inputDecoration('القالب المعتمد', Icons.style_rounded),
                                items: refs.templates.map((t) => DropdownMenuItem(value: t.templateId, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _templateId = v),
                              ),
                              const SizedBox(height: 16),
                              
                              // التاريخ
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                            primary: AppColors.navyDeep,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (d != null) setState(() => _date = d);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('تاريخ الكتاب', Icons.calendar_today_rounded),
                                  child: Text(DateFormat('yyyy/MM/dd').format(_date), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // الموضوع
                              TextField(
                                controller: _subject,
                                decoration: _inputDecoration('موضوع الكتاب', Icons.subject_rounded),
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
                                  const Text('التفاصيل المالية (اختياري)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
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
                                        DropdownMenuItem(value: 'IQD', child: Text('دينار', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'USD', child: Text('دولار', overflow: TextOverflow.ellipsis)),
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
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // القسم الأيسر (المحرر والنص)
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 24, top: 32, bottom: 32),
                      child: Column(
                        children: [
                          Expanded(
                            child: CustomCard(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.edit_document, color: AppColors.navyDeep),
                                      const SizedBox(width: 12),
                                      const Text('محتوى الكتاب (المحرر)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                                  Expanded(
                                    child: Container(
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
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // زر الحفظ
                          SizedBox(
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
                                _busy ? 'جارٍ الحفظ...' : 'حفظ كمسودة نهائية',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
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
  final List<TemplateModel> templates;
  _Refs(this.entities, this.templates);
}
