import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
  final _keywords = TextEditingController();
  final _notes = TextEditingController();

  /// محتوى الأرشيف — **حقل نصّ عادي لا محرّر منسّق**.
  ///
  /// ⚠️ كان محرّر Quill بشريط كامل (خط · حجم · عريض · مائل · ألوان)، لكن الحفظ يتم
  /// بـ`toPlainText()` والعرض بـ`Text` عادي ⇒ **كل تنسيق يكتبه المستخدم يُمحى صامتاً**.
  /// فالشريط لم يكن زائداً فحسب بل **يَعِد بما لا يُنفَّذ**. وهذا المتن وصفٌ للمستند
  /// الممسوح لا مستندٌ رسمي (بخلاف متن الصادر الذي يُرسَم في PDF بتنسيقه).
  /// `TextField` يعطي التراجع والإعادة أصلاً (Ctrl+Z / Ctrl+Y) — وهو ما يحتاجه المالك.
  final _body = TextEditingController();

  /// ملفات اختيرت قبل الحفظ — تُرفَع بعد إنشاء المستند (المرفق يحتاج مالكاً محفوظاً).
  final List<_PendingFile> _pending = [];

  /// مرآة لحدّ `AttachmentService` في الباك-إند.
  static const _kMaxAttachmentMb = 50;

  DateTime? _bookDate;
  int? _fromEntityId, _toEntityId, _documentTypeId, _departmentId;

  /// ⚠️ **قيم محمولة لا مُدخَلة:** الحقول المالية أُزيلت من الواجهة (2026-07-28) لكن
  /// الأعمدة باقية في القاعدة، فنحمل قيم المستند ونُعيد إرسالها كما هي — وإلا مسحها
  /// أوّلُ تعديل بصمت. نفس نمط `_legacy*` في نموذج الوارد.
  num? _legacyAmount, _legacyRate;
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
      _legacyAmount = e.amount;
      _legacyRate = e.exchangeRate;
      _keywords.text = e.keywords ?? '';
      _notes.text = e.notes ?? '';
      _bookDate = e.bookDate;
      _fromEntityId = e.fromEntityId;
      _toEntityId = e.toEntityId;
      _documentTypeId = e.documentTypeId;
      _departmentId = e.departmentId;
      _currency = e.currency;
      
      // المتن يُخزَّن نصّاً مع `<br>` بدل الأسطر — نعكسها للعرض والتحرير.
      _body.text = (e.bodyHtml ?? '').replaceAll('<br>', '\n');
    }
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _title.dispose();
    _bookNumber.dispose();
    _keywords.dispose();
    _notes.dispose();
    _body.dispose();
    super.dispose();
  }

  /// اختيار مرفقات — نفس أنواع وحدّ الوارد (مرآة لقواعد `AttachmentService`).
  Future<void> _pickAttachments() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx', 'zip', 'dwg'],
      withData: true,
      allowMultiple: true,
    );
    if (res == null) return;

    final tooBig = <String>[];
    setState(() {
      for (final f in res.files) {
        if (f.bytes == null) continue;
        if (f.bytes!.length > _kMaxAttachmentMb * 1024 * 1024) { tooBig.add(f.name); continue; }
        if (_pending.any((p) => p.name == f.name)) continue;
        _pending.add(_PendingFile(f.name, f.bytes!));
      }
    });

    // نرفض المتجاوز **هنا** لا بعد الحفظ — حتى لا يُسجَّل المستند ثم يُفاجأ المستخدم بفشل المرفق.
    if (tooBig.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تجاوزت الحدّ ($_kMaxAttachmentMb م.ب): ${tooBig.join('، ')}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    return _Refs(await api.entities(), await api.documentTypes(), await api.departments());
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) { setState(() => _error = 'عنوان المستند مطلوب.'); return; }

    final text = _body.text.trim();
    final bodyHtml = text.isEmpty ? null : text.replaceAll('\n', '<br>');

    final body = {
      'title': _title.text.trim(),
      'bookNumber': _bookNumber.text.trim().isEmpty ? null : _bookNumber.text.trim(),
      'bookDate': _bookDate?.toIso8601String(),
      'fromEntityId': _fromEntityId,
      'toEntityId': _toEntityId,
      'documentTypeId': _documentTypeId,
      'departmentId': _departmentId,
      // قيم محمولة كما هي — لا مدخل لها في الواجهة (انظر `_legacy*` أعلى الملف).
      'amount': _legacyAmount,
      'currency': _legacyAmount == null ? null : _currency,
      'exchangeRate': _legacyRate,
      'keywords': _keywords.text.trim().isEmpty ? null : _keywords.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'bodyHtml': bodyHtml,
    };

    setState(() { _busy = true; _error = null; });
    
    try {
      final api = ref.read(apiClientProvider);
      final int archiveId;
      if (_isEdit) {
        await api.updateArchive(widget.existing!.archiveId, body);
        archiveId = widget.existing!.archiveId;
      } else {
        final created = await api.createArchive(body);
        archiveId = created.archiveId;
      }

      // المرفق يحتاج مالكاً محفوظاً (OwnerId)، فتُجمَّع الملفات في النموذج وتُرفَع بعده.
      // ⚠️ **فشلُ رفع مرفق لا يُبطل حفظ المستند** — المستند سجلّ قائم بذاته والمرفق مُلحق
      //    به؛ نُبلّغ المستخدم ليُعيد الرفع من شاشة التفاصيل بدل أن نفقد ما أدخله.
      final failed = <String>[];
      for (final f in _pending) {
        try {
          await api.uploadArchiveAttachment(archiveId, f.bytes, f.name);
        } on ApiException catch (_) {
          failed.add(f.name);
        }
      }
      if (mounted && failed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('حُفظ المستند، لكن تعذّر رفع: ${failed.join('، ')} — أعِد رفعها من شاشة التفاصيل.'),
          backgroundColor: AppColors.warn,
          duration: const Duration(seconds: 6),
        ));
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

                  final extraCard = CustomCard(
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

                        // ⚠️ أُزيلت الحقول المالية و«تفاصيل التوجيه» من هذا النموذج بطلب المالك
                        //    (2026-07-28) — الأرشيف سجلّ مستندات لا سجلّ محاسبي.
                        //    **والأعمدة باقية في القاعدة عمداً**: `ReportService` يقرأ
                        //    `ArchiveDoc.AmountInIqd` كمصدر في التقرير المالي، فحذفها يُلغي
                        //    مصدر تقرير لا حقلاً معطّلاً. الإخفاء واجهي بحت.

                        // القسم: يُحدّد من يرى الأضبارة (قسمه) ويُفلتَر به في الأرشيف.
                        // **اختياري عمداً** — إلزامه يدفع المُدخِل للتخمين فتُصنَّف خطأً.
                        DropdownButtonFormField<int?>(
                          isExpanded: true,
                          initialValue: _departmentId,
                          decoration: _inputDecoration('القسم (اختياري)', Icons.apartment_rounded),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— بلا قسم —')),
                            ...refs.departments.map((d) =>
                                DropdownMenuItem<int?>(value: d.departmentId, child: Text(d.name))),
                          ],
                          onChanged: (v) => setState(() => _departmentId = v),
                        ),
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

                        // ⚠️ حقل نصّ عادي بدل محرّر منسّق: الحفظ يتم بنصّ مجرّد والعرض
                        //    بـ`Text` عادي، فأي تنسيق كان يُمحى صامتاً — شريطٌ يَعِد بما
                        //    لا يُنفَّذ. والتراجع/الإعادة (Ctrl+Z / Ctrl+Y) مدمجان هنا أصلاً.
                        TextField(
                          controller: _body,
                          maxLines: isSmall ? 12 : 16,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'وصف المستند أو ملاحظات عنه…',
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: isDark
                                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  );

                  // بطاقة المرفقات — **المدخل الذي كان مفقوداً**: كان المستخدم يحفظ
                  // المستند ثم يُعيد فتحه ليُرفق الملف. والمرفق هو جوهر الأرشيف لا مُلحق به.
                  final attachmentsCard = CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.attach_file_rounded, color: AppColors.navyDeep),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isEdit
                                    ? 'إضافة مرفقات (${_pending.length})'
                                    : 'المرفقات (${_pending.length})',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _pickAttachments,
                              icon: const Icon(Icons.upload_file_rounded, size: 18),
                              label: const Text('اختيار ملفات'),
                            ),
                          ],
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 6),
                          Text('المرفقات المرفوعة سابقاً تُدار من شاشة التفاصيل — هنا تُضاف الجديدة فقط.',
                              style: TextStyle(fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                        ],
                        const Divider(height: 24),
                        if (_pending.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('لم تُختَر ملفات. المسموح: PDF · صور · Word · Excel · ZIP · DWG (حتى $_kMaxAttachmentMb م.ب).',
                                style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5), fontSize: 12.5)),
                          )
                        else
                          for (var i = 0; i < _pending.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.insert_drive_file_outlined, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_pending[i].name,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13))),
                                  Text(_fmtSize(_pending[i].bytes.length),
                                      style: TextStyle(fontSize: 12,
                                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    onPressed: _busy ? null : () => setState(() => _pending.removeAt(i)),
                                  ),
                                ],
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
                        extraCard,
                        const SizedBox(height: 24),
                        attachmentsCard,
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
                      // القسم الأيمن (البيانات الأساسية)
                      Expanded(
                        flex: 4,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          children: [
                            basicInfoCard,
                            const SizedBox(height: 24),
                            extraCard,
                            const SizedBox(height: 24),
                            attachmentsCard,
                          ],
                        ),
                      ),

                      // القسم الأيسر (المتن والحفظ)
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24, top: 32, bottom: 32),
                          child: Column(
                            children: [
                              Expanded(child: SingleChildScrollView(child: editorSection)),
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
  final List<DepartmentModel> departments;
  _Refs(this.entities, this.types, this.departments);
}

/// ملف اختير قبل الحفظ — يُحتفظ ببايتاته حتى يُنشأ المستند فيُرفَع إليه.
class _PendingFile {
  final String name;
  final Uint8List bytes;
  _PendingFile(this.name, this.bytes);
}

String _fmtSize(int b) {
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} ك.ب';
  return '$b بايت';
}
