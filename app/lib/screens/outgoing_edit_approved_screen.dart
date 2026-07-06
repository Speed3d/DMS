import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// Hint: شاشة تعديل كتاب معتمد لإنشاء إصدار جديد (Version)
class OutgoingEditApprovedScreen extends ConsumerStatefulWidget {
  final OutgoingDetail book;
  const OutgoingEditApprovedScreen({super.key, required this.book});
  @override
  ConsumerState<OutgoingEditApprovedScreen> createState() => _OutgoingEditApprovedScreenState();
}

class _OutgoingEditApprovedScreenState extends ConsumerState<OutgoingEditApprovedScreen> {
  late final TextEditingController _subject;
  late final TextEditingController _headerPhrase;
  late final TextEditingController _signatoryName;
  late final TextEditingController _signatoryTitle;
  late final TextEditingController _amount;
  late final TextEditingController _rate;
  late final TextEditingController _note;
  late final quill.QuillController _quillController;
  bool _showFinancials = false;
  
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
    _headerPhrase = TextEditingController(text: b.headerPhrase ?? '');
    _signatoryName = TextEditingController(text: b.signatoryName ?? '');
    _signatoryTitle = TextEditingController(text: b.signatoryTitle ?? '');
    _amount = TextEditingController(text: b.amount?.toString() ?? '');
    _rate = TextEditingController(text: b.exchangeRate?.toString() ?? '');
    _note = TextEditingController();
    _showFinancials = b.amount != null;
    
    // إعداد محرر النصوص بمحتوى الكتاب القديم
    _quillController = quill.QuillController(
      document: quill.Document()..insert(0, '${b.bodyHtml.replaceAll(RegExp(r'<[^>]*>'), '')}\n'),
      selection: const TextSelection.collapsed(offset: 0),
    );

    _date = b.date;
    _entityId = b.entityId;
    _templateId = b.templateId;
    _currency = b.currency;
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _subject.dispose();
    _headerPhrase.dispose();
    _signatoryName.dispose();
    _signatoryTitle.dispose();
    _amount.dispose();
    _rate.dispose();
    _note.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    final entities = await api.entities();
    final templates = await api.templates();
    return _Refs(entities, templates.where((t) => t.isActive).toList());
  }

  /// Hint: تحويل من Quill Delta إلى HTML للإرسال إلى السيرفر
  String _getHtmlFromBody() {
    final delta = _quillController.document.toDelta();
    final converter = QuillDeltaToHtmlConverter(
      delta.toJson().cast<Map<String, dynamic>>(),
    );
    return converter.convert();
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'الموضوع مطلوب.');
      return;
    }
    if (_quillController.document.isEmpty()) {
      setState(() => _error = 'نص الكتاب مطلوب.');
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
        'headerPhrase': _headerPhrase.text.trim().isEmpty ? null : _headerPhrase.text.trim(),
        'signatoryName': _signatoryName.text.trim().isEmpty ? null : _signatoryName.text.trim(),
        'signatoryTitle': _signatoryTitle.text.trim().isEmpty ? null : _signatoryTitle.text.trim(),
        'subject': _subject.text.trim(),
        'bodyHtml': _getHtmlFromBody(),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('تعديل إصدار: ${widget.book.number ?? ''}'),
        centerTitle: true,
      ),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('خطأ: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.warn.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.warn.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.warn),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'تنبيه: هذا الكتاب معتمد. أي حفظ للتعديلات سيولد (إصدار جديد) منه مع إعادة توليد الـ PDF والـ QR. رقم الكتاب لن يتغير.',
                                  style: TextStyle(height: 1.5, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('معلومات الإصدار الجديد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const Divider(height: 32),
                              
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: _entityId,
                                decoration: _inputDecoration('الجهة المستلمة', Icons.business_rounded),
                                items: refs.entities.map((e) => DropdownMenuItem(value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _entityId = v ?? _entityId),
                              ),
                              const SizedBox(height: 16),
                              
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: _templateId,
                                decoration: _inputDecoration('القالب المعتمد', Icons.style_rounded),
                                items: refs.templates.map((t) => DropdownMenuItem(value: t.templateId, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _templateId = v ?? _templateId),
                              ),
                              const SizedBox(height: 16),
                              
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
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
                              
                              TextField(
                                controller: _subject,
                                decoration: _inputDecoration('موضوع الكتاب', Icons.subject_rounded),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _headerPhrase,
                                decoration: _inputDecoration('عبارة رأسية اختيارية (إلى، أمر إداري، إلخ)', Icons.title_rounded),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _signatoryName,
                                decoration: _inputDecoration('اسم الموقّع (اختياري)', Icons.person_rounded),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _signatoryTitle,
                                decoration: _inputDecoration('المنصب (اختياري)', Icons.badge_rounded),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: Text('التفاصيل المالية والملاحظات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
                                    decoration: _inputDecoration('سعر الصرف', Icons.price_change_rounded),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 16),
                              TextField(
                                controller: _note,
                                decoration: _inputDecoration('ملاحظة التغيير (اختياري)', Icons.edit_note_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // القسم الأيسر (المحرر)
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
                                      const Text('تعديل نص الكتاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                          
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.warn,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 8,
                                shadowColor: AppColors.warn.withValues(alpha: 0.5),
                              ),
                              icon: _busy 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                : const Icon(Icons.save_rounded),
                              label: Text(
                                _busy ? 'جارٍ الحفظ...' : 'حفظ كإصدار جديد',
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
