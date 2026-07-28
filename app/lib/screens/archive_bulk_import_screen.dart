import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// **استيراد دفعة من الأرشيف الورقي** — ملفات متعدّدة ببيانات وصفية مشتركة.
///
/// ⚠️ **لماذا بالجملة لا واحداً واحداً:** أرشيف الشركة ~80 غيغا ≈ **6,500 كتاب**؛ إدخالها
/// يدوياً بدقيقتين للكتاب = **٢٧ يوم عمل متواصل** — وهو ما لا يكتمل عملياً فينتهي الأمر
/// بأرشيف نصفه في النظام ونصفه على أجهزة الموظفين، وهو أسوأ من الحالتين.
///
/// البيانات المشتركة (السنة/الشهر/القسم/الجهة/النوع) تُعطي **الترتيب المطلوب نفسه**، والعنوان
/// يُستخلص من اسم الملف. وما لا يُستخلص يُعلَّم «يحتاج عنواناً» — **ولا يُخترع له عنوان**،
/// فعنوانٌ كاذب يوهم بأن الأرشيف مكتمل.
class ArchiveBulkImportScreen extends ConsumerStatefulWidget {
  const ArchiveBulkImportScreen({super.key});
  @override
  ConsumerState<ArchiveBulkImportScreen> createState() => _State();
}

class _State extends ConsumerState<ArchiveBulkImportScreen> {
  /// سقف الخادم للدفعة الواحدة — نعكسه هنا لنمنع الرفض بعد انتظار طويل.
  static const _maxPerBatch = 50;

  final List<PlatformFile> _picked = [];
  final _keywords = TextEditingController();

  int? _year = DateTime.now().year;
  int? _month;
  int? _departmentId, _entityId, _documentTypeId;

  bool _busy = false;
  String? _error;
  BulkImportResult? _result;
  late Future<_Refs> _refs;

  @override
  void initState() {
    super.initState();
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _keywords.dispose();
    super.dispose();
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    return _Refs(await api.entities(), await api.documentTypes(), await api.departments());
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true, // نحتاج البايتات — الويب لا يعطي مساراً
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx', 'zip', 'dwg'],
    );
    if (res == null) return;
    setState(() {
      _error = null;
      _result = null;
      for (final f in res.files) {
        if (_picked.any((p) => p.name == f.name)) continue; // لا تكرار داخل الدفعة
        _picked.add(f);
      }
      if (_picked.length > _maxPerBatch) {
        _error = 'الحد الأقصى $_maxPerBatch ملفاً في الدفعة — احذف الزائد أو قسّمها شهراً شهراً.';
      }
    });
  }

  Future<void> _import() async {
    if (_picked.isEmpty) { setState(() => _error = 'اختر ملفاً واحداً على الأقل.'); return; }
    if (_picked.length > _maxPerBatch) return;

    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final files = _picked
          .where((f) => f.bytes != null)
          .map((f) => (name: f.name, bytes: f.bytes!))
          .toList();

      final r = await ref.read(apiClientProvider).archiveBulkImport(
            files: files,
            year: _year, month: _month,
            departmentId: _departmentId, fromEntityId: _entityId,
            documentTypeId: _documentTypeId,
            keywords: _keywords.text.trim(),
          );
      if (!mounted) return;
      setState(() { _result = r; _picked.clear(); });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد أرشيف ورقي (دفعة)'), centerTitle: true),
      body: FutureBuilder<_Refs>(
        future: _refs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('تعذّر تحميل البيانات المرجعية: ${snap.error}',
                style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _guidanceCard(theme),
                  const SizedBox(height: 20),
                  _metadataCard(refs),
                  const SizedBox(height: 20),
                  _filesCard(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _busy || _picked.isEmpty ? null : _import,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_upload_rounded),
                      label: Text(_busy ? 'جارٍ الاستيراد…' : 'استيراد ${_picked.length} ملفاً'),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 24),
                    _resultCard(_result!, theme),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _guidanceCard(ThemeData theme) => CustomCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline_rounded, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'ارفع الأرشيف على دفعات — شهراً شهراً مثلاً. البيانات التي تُدخلها هنا تُطبَّق على '
                'كل ملفات الدفعة، والعنوان يُستخرج من اسم الملف تلقائياً. الأسماء التي لا تحمل '
                'معنى (مثل IMG_0234) تُعلَّم لتُصحّحها لاحقاً على مهل.',
                style: TextStyle(fontSize: 13, height: 1.7,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)),
              ),
            ),
          ],
        ),
      );

  Widget _metadataCard(_Refs refs) => CustomCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('بيانات الدفعة (تُطبَّق على كل الملفات)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const Divider(height: 28),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _field(DropdownButtonFormField<int?>(
                  initialValue: _year,
                  decoration: const InputDecoration(labelText: 'السنة'),
                  items: [
                    for (var y = DateTime.now().year; y >= DateTime.now().year - 30; y--)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (v) => setState(() => _year = v),
                )),
                _field(DropdownButtonFormField<int?>(
                  initialValue: _month,
                  decoration: const InputDecoration(labelText: 'الشهر (اختياري)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— كل السنة —')),
                    for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('شهر $m')),
                  ],
                  onChanged: (v) => setState(() => _month = v),
                )),
                _field(DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _departmentId,
                  decoration: const InputDecoration(labelText: 'القسم (اختياري)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— بلا قسم —')),
                    ...refs.departments.map((d) => DropdownMenuItem<int?>(value: d.departmentId, child: Text(d.name))),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                )),
                _field(DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _entityId,
                  decoration: const InputDecoration(labelText: 'الجهة (اختياري)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— بلا جهة —')),
                    ...refs.entities.map((e) => DropdownMenuItem<int?>(value: e.entityId, child: Text(e.name))),
                  ],
                  onChanged: (v) => setState(() => _entityId = v),
                )),
                _field(DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _documentTypeId,
                  decoration: const InputDecoration(labelText: 'نوع المستند (اختياري)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— بلا نوع —')),
                    ...refs.types.map((t) => DropdownMenuItem<int?>(value: t.documentTypeId, child: Text(t.name))),
                  ],
                  onChanged: (v) => setState(() => _documentTypeId = v),
                )),
                _field(TextField(
                  controller: _keywords,
                  decoration: const InputDecoration(labelText: 'كلمات مفتاحية (اختياري)'),
                )),
              ],
            ),
          ],
        ),
      );

  Widget _field(Widget child) => SizedBox(width: 250, child: child);

  Widget _filesCard(ThemeData theme) => CustomCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('الملفات (${_picked.length} / $_maxPerBatch)',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (_picked.isNotEmpty)
                  TextButton.icon(
                    onPressed: _busy ? null : () => setState(() { _picked.clear(); _error = null; }),
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('إفراغ'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('اختيار ملفات'),
                ),
              ],
            ),
            const Divider(height: 28),
            if (_picked.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('لم تُختَر ملفات بعد.',
                      style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _picked.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                  itemBuilder: (_, i) {
                    final f = _picked[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                          Text(_size(f.size),
                              style: TextStyle(fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: _busy ? null : () => setState(() { _picked.removeAt(i); _error = null; }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );

  Widget _resultCard(BulkImportResult r, ThemeData theme) {
    final failed = r.rows.where((x) => !x.ok).toList();
    final needTitle = r.rows.where((x) => x.ok && x.needsTitle).toList();

    return CustomCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('حصيلة الاستيراد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Divider(height: 28),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _chip('نجح ${r.created}', AppColors.success),
            if (r.failed > 0) _chip('فشل ${r.failed}', AppColors.danger),
            if (r.needTitleCount > 0) _chip('يحتاج عنواناً ${r.needTitleCount}', AppColors.warn),
          ]),

          if (needTitle.isNotEmpty) ...[
            const SizedBox(height: 20),
            // ⚠️ قائمة محدّدة لا تحذير عام: المالك يعرف **أي** الملفات تحتاج عنواناً
            //    فيُصحّحها على مهل — بدل أن يبحث عنها بين آلاف الأضابير.
            Text('ملفات بأسماء بلا معنى — افتحها من الأرشيف وصحّح عناوينها لاحقاً:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8))),
            const SizedBox(height: 8),
            for (final x in needTitle)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${x.number} — ${x.fileName}', style: const TextStyle(fontSize: 12.5)),
              ),
          ],

          if (failed.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('ملفات لم تُستورَد:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
            const SizedBox(height: 8),
            for (final x in failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${x.fileName} — ${x.error}', style: const TextStyle(fontSize: 12.5)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      );

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
    return '$bytes بايت';
  }
}

class _Refs {
  final List<EntityModel> entities;
  final List<DocumentTypeModel> types;
  final List<DepartmentModel> departments;
  _Refs(this.entities, this.types, this.departments);
}
