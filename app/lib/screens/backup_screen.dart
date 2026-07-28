import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _State();
}

class _State extends ConsumerState<BackupScreen> {
  BackupScheduleModel? _schedule;
  BackupCoverage? _coverage;
  List<BackupRecordModel> _list = [];
  String _freq = 'Off';
  bool _enabled = false;
  int _hour = 2;
  bool _loading = true, _busy = false;
  String? _error, _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      _schedule = await api.backupSchedule();
      _list = await api.backupList();
      _coverage = await api.backupCoverage();
      _freq = _schedule!.frequency;
      _enabled = _schedule!.enabled;
      _hour = _schedule!.hour;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────── المرآة (ADR-020) ───────────────────────────

  /// يُشغّل المرآة إلى مسار يُدخله المالك — **بلا افتراض**، فالمسار قراره.
  Future<void> _runMirror() async {
    final path = await _askPath(
      title: 'مرآة كاملة إلى مسار خارجي',
      hint: r'مثال: E:\DMS-Backup',
      note: 'تُنسخ قاعدة البيانات وكل الملفات. المرة الأولى قد تستغرق وقتاً طويلاً، '
          'والمرات التالية تنسخ الجديد فقط.',
      actionLabel: 'ابدأ المرآة',
    );
    if (path == null || path.trim().isEmpty) return;

    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final r = await ref.read(apiClientProvider).backupMirror(path.trim());
      _info = 'المرآة اكتملت في ${r.targetPath} — نُسخ ${r.copied} ملفاً، وتُخطّي ${r.skipped} موجوداً سلفاً.'
          '${r.databaseOk ? '' : ' ⚠️ لكن قاعدة البيانات لم تُنسخ: ${r.note ?? ''}'}';
      await _load();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// استعادة من مرآة — تدميرية، بتأكيد مكتوب كالاستعادة العادية.
  Future<void> _restoreMirror() async {
    final path = await _askPath(
      title: 'استعادة من مرآة',
      hint: r'مثال: E:\DMS-Backup',
      note: '⚠️ عملية تدميرية: تُستبدل قاعدة البيانات وكل الملفات بمحتوى المرآة. '
          'يأخذ النظام نسخة أمان تلقائية قبل الاستبدال.',
      actionLabel: 'استعادة',
      danger: true,
      // نفس ضمانة الاستعادة العادية: كتابة الكلمة يدوياً لا زرّ واحد.
      confirmWord: kRestoreConfirmation,
    );
    if (path == null || path.trim().isEmpty) return;

    setState(() { _busy = true; _error = null; _info = null; });
    try {
      _info = await ref.read(apiClientProvider).backupRestoreFromMirror(path.trim());
      await _load();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// حوار إدخال مسار — **شاشة كاملة لا `showDialog`** (حقول النصّ داخل الحوارات
  /// تسبب `disposed EngineFlutterView` على الويب — قاعدة المشروع).
  Future<String?> _askPath({
    required String title, required String hint, required String note,
    required String actionLabel, bool danger = false, String? confirmWord,
  }) =>
      Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => _PathPromptPage(
            title: title, hint: hint, note: note, actionLabel: actionLabel,
            danger: danger, confirmWord: confirmWord),
      ));

  Future<void> _saveSchedule() async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      _schedule = await ref.read(apiClientProvider).updateBackupSchedule(_freq, _enabled, _hour);
      _info = 'تم حفظ الجدولة.';
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow() async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final rec = await ref.read(apiClientProvider).backupRun();
      _info = rec.status == 'Success'
          ? 'تمت النسخة الاحتياطية (${_size(rec.sizeBytes)}).'
          : 'انتهت بحالة: ${rec.status} — ${rec.note ?? ''}';
      _list = await ref.read(apiClientProvider).backupList();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// استعادة نسخة — عملية تدميرية، لذا التأكيد بكتابة الكلمة يدوياً لا بزرّ واحد.
  /// Hint: شاشة كاملة لا حوار (حقل نصّي داخل حوار يسبب خلل disposed EngineFlutterView على الويب).
  Future<void> _restore(BackupRecordModel r) async {
    final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _RestoreConfirmPage(record: r, fmtSize: _size, fmtDate: _dt)));
    if (confirmed != true) return;

    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await ref.read(apiClientProvider).backupRestore(r.id);
      _info = 'تمت الاستعادة بنجاح من ${r.fileName}. أُنشئت نسخة أمان تلقائية قبل الاستبدال.';
      // Hint: القاعدة تغيّرت بالكامل — نعيد تحميل كل شيء بدل الاعتماد على بيانات قديمة في الذاكرة.
      await _load();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// حذف نسخة — الخادم يمنع حذف آخر نسخة ناجحة، فنعرض رسالته كما هي.
  Future<void> _deleteBackup(BackupRecordModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف نسخة احتياطية'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('سيُحذف الأرشيف «${r.fileName}» (${_size(r.sizeBytes)}) نهائياً من الخادم.\n'
            'لن يمكن الاستعادة منه بعد الحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await ref.read(apiClientProvider).backupDelete(r.id);
      _info = 'تم حذف النسخة «${r.fileName}».';
      _list = await ref.read(apiClientProvider).backupList();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(BackupRecordModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).backupDownload(r.id);
      await downloadBytes(bytes, r.fileName, 'application/zip');
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  String _size(int b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';

  /// بطاقة تذكير النسخة الكاملة — لونها ونبرتها يتصاعدان مع اقتراب المهلة.
  ///
  /// 🔴 وجودها ليس تزيّناً: النسخة الكاملة **يدوية بقرار المالك**، والمجدولة لا تحمي
  /// المرفقات. فلو نُسيت شهرين ثم تعطّل القرص ضاعت مرفقات شهرين — **بينما النسخ
  /// اليومية تعمل بانتظام فتُعطي شعوراً زائفاً بالأمان.**
  Widget _coverageCard(BackupCoverage c) {
    final (color, icon) = switch (c.urgency) {
      'Ok' => (AppColors.success, Icons.verified_rounded),
      'Soon' => (AppColors.gold, Icons.schedule_rounded),
      'Urgent' => (AppColors.warn, Icons.warning_amber_rounded),
      _ => (AppColors.danger, Icons.error_outline_rounded),
    };

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تغطية المرفقات والأرشيف',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  Text(c.message, style: const TextStyle(fontSize: 13, height: 1.6)),
                ],
              ),
            ),
            if (!c.isOk)
              FilledButton.icon(
                onPressed: _busy ? null : _runMirror,
                style: FilledButton.styleFrom(backgroundColor: color),
                icon: const Icon(Icons.backup_rounded, size: 18),
                label: const Text('خذ نسخة الآن'),
              ),
          ],
        ),
      ),
    );
  }

  /// بطاقة المرآة — النسخة الكاملة اليدوية إلى قرص خارجي.
  Widget _mirrorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المرآة — نسخة كاملة إلى قرص خارجي',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'تنسخ قاعدة البيانات وكل الملفات إلى مسار تحدّده (قرص SSD خارجي مثلاً). '
                '**لا تُكرّر**: الملف الموجود يُتخطّى، فالمرة الأولى طويلة والتالية دقائق.',
                style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.6),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _runMirror,
                  icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                  label: const Text('تشغيل المرآة'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restoreMirror,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                  label: const Text('استعادة من مرآة'),
                ),
              ]),
            ],
          ),
        ),
      );
  String _dt(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('النسخ الاحتياطي', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('مستويان: نسخ مجدولة خفيفة (قاعدة البيانات) + مرآة كاملة يدوية إلى قرص خارجي.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          // ⚠️ النصّ يصف السلوك **بعد ADR-020**: كان يقول إن المجدولة تُرقّى إلى كاملة
          //    جمعةً وأول الشهر — وهو ما أُلغي لأن ٣٦ نسخة × 80 غيغا = 2.9 تيرابايت.
          const Text(
            'النسخ المجدولة **قاعدة البيانات فقط** — خفيفة وسريعة وتصلح للرفع إلى OneDrive. '
            'يُحتفظ بآخر ٧ يومية و٤ أسبوعية و١٢ شهرية، وتُحذف الأقدم تلقائياً.\n'
            '⚠️ وهي **لا تحمي المرفقات والأرشيف** — حمايتها من «المرآة» أدناه، وهي يدوية بقرارك.',
            style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 16),

          if (_coverage != null) _coverageCard(_coverage!),
          if (_coverage != null) const SizedBox(height: 16),

          _mirrorCard(),
          const SizedBox(height: 16),

          // الجدولة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الجدولة التلقائية', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        initialValue: _freq,
                        decoration: const InputDecoration(labelText: 'التكرار', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'Off', child: Text('متوقّف')),
                          DropdownMenuItem(value: 'Daily', child: Text('يومي')),
                          DropdownMenuItem(value: 'Weekly', child: Text('أسبوعي')),
                        ],
                        onChanged: (v) => setState(() => _freq = v ?? 'Off'),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        initialValue: _hour,
                        decoration: const InputDecoration(labelText: 'الساعة', isDense: true),
                        items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                        onChanged: (v) => setState(() => _hour = v ?? 2),
                      ),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('مُفعّل'),
                      Switch(value: _enabled, onChanged: _freq == 'Off' ? null : (v) => setState(() => _enabled = v)),
                    ]),
                    FilledButton.icon(onPressed: _busy ? null : _saveSchedule, icon: const Icon(Icons.save), label: const Text('حفظ الجدولة')),
                  ]),
                  if (_schedule?.nextRunAt != null && _enabled && _freq != 'Off')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('التشغيل التالي: ${_dt(_schedule!.nextRunAt!)}', style: const TextStyle(color: Colors.teal)),
                    ),
                  if (_schedule?.lastRunAt != null)
                    Text('آخر تشغيل: ${_dt(_schedule!.lastRunAt!)}', style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _runNow,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
                label: const Text('نسخة احتياطية الآن'),
              ),
              TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
            ],
          ),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, style: const TextStyle(color: Colors.green))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),

          Text('النسخ السابقة (${_list.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_list.isEmpty)
            const Text('لا توجد نسخ بعد.', style: TextStyle(color: Colors.grey))
          else
            ..._list.map((r) => Card(
                  child: ListTile(
                    leading: Icon(r.status == 'Success' ? Icons.check_circle : Icons.error,
                        color: r.status == 'Success' ? Colors.green : Colors.red),
                    title: Text(_dt(r.createdAt)),
                    // النطاق والتصنيف يوضّحان ماذا تتضمّن النسخة ولماذا يختلف حجمها.
                    subtitle: Text(
                        '${backupCategoryLabel(r.category)} • ${backupScopeLabel(r.scope)} • ${_size(r.sizeBytes)}'
                        '${r.note != null ? '\n${r.note}' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: 'تنزيل',
                          onPressed: (_busy || r.status != 'Success') ? null : () => _download(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.restore, color: AppColors.danger),
                          tooltip: 'استعادة هذه النسخة',
                          onPressed: (_busy || r.status != 'Success') ? null : () => _restore(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'حذف النسخة',
                          onPressed: _busy ? null : () => _deleteBackup(r),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────── شاشة تأكيد الاستعادة ───────────────────────────
/// شاشة تأكيد الاستعادة — عملية تدميرية تستبدل قاعدة البيانات والملفات بالكامل.
/// Hint: التأكيد بكتابة الكلمة يدوياً (لا بزرّ واحد) حتى لا تقع بالخطأ، وهي نفس الكلمة
///       التي يتحقق منها الباك-إند. شاشة كاملة لا حوار — الحقول النصّية داخل الحوارات
///       تسبب خلل `disposed EngineFlutterView` في Flutter Web.
class _RestoreConfirmPage extends StatefulWidget {
  final BackupRecordModel record;
  final String Function(int) fmtSize;
  final String Function(DateTime) fmtDate;
  const _RestoreConfirmPage({required this.record, required this.fmtSize, required this.fmtDate});

  @override
  State<_RestoreConfirmPage> createState() => _RestoreConfirmPageState();
}

class _RestoreConfirmPageState extends State<_RestoreConfirmPage> {
  final _controller = TextEditingController();
  bool get _matches => _controller.text.trim() == kRestoreConfirmation;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد استعادة نسخة احتياطية'), centerTitle: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Text('عملية لا رجعة فيها مباشرةً',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold, color: AppColors.danger)),
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                      'سيُستبدل محتوى النظام بالكامل — قاعدة البيانات وكل الملفات — بمحتوى هذه النسخة. '
                      'كل ما أُضيف بعد تاريخها سيختفي.\n\n'
                      'سيتوقّف النظام عن خدمة المستخدمين لثوانٍ أثناء العملية، '
                      'وستُؤخذ نسخة أمان تلقائية قبل الاستبدال يمكن الرجوع إليها.',
                      style: TextStyle(height: 1.7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text('النسخة المختارة', style: theme.textTheme.titleSmall),
              const Divider(),
              _row('التاريخ', widget.fmtDate(r.createdAt)),
              _row('الملف', r.fileName),
              _row('المحتوى', backupScopeLabel(r.scope)),
              _row('التصنيف', backupCategoryLabel(r.category)),
              _row('الحجم', widget.fmtSize(r.sizeBytes)),
              if (r.scope == 'DbOnly')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'ملاحظة: هذه نسخة قاعدة بيانات فقط — ستبقى ملفات المرفقات الحالية كما هي بلا تغيير.',
                    style: TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 24),

              Text('للمتابعة، اكتب كلمة «$kRestoreConfirmation» في الحقل أدناه:',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: kRestoreConfirmation,
                  suffixIcon: _matches ? const Icon(Icons.check_circle, color: AppColors.success) : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) { if (_matches) Navigator.pop(context, true); },
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      // الزر معطّل حتى تُكتب الكلمة بالضبط.
                      onPressed: _matches ? () => Navigator.pop(context, true) : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      icon: const Icon(Icons.restore),
                      label: const Text('استعادة الآن'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// شاشة إدخال مسار (المرآة أو الاستعادة منها).
///
/// ⚠️ **شاشة كاملة لا `showDialog`:** حقول النصّ داخل حوارات Flutter على الويب تسبب
/// خلل `disposed EngineFlutterView` — قاعدة مستقرّة في هذا المشروع.
class _PathPromptPage extends StatefulWidget {
  final String title, hint, note, actionLabel;
  final bool danger;

  /// إن حُدِّدت، وجب على المالك كتابتها حرفياً قبل تفعيل الزرّ (للعمليات التدميرية).
  final String? confirmWord;

  const _PathPromptPage({
    required this.title, required this.hint, required this.note,
    required this.actionLabel, this.danger = false, this.confirmWord,
  });
  @override
  State<_PathPromptPage> createState() => _PathPromptPageState();
}

class _PathPromptPageState extends State<_PathPromptPage> {
  final _c = TextEditingController();
  final _confirm = TextEditingController();

  bool get _ready =>
      _c.text.trim().isNotEmpty &&
      (widget.confirmWord == null || _confirm.text.trim() == widget.confirmWord);

  @override
  void dispose() { _c.dispose(); _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? AppColors.danger : AppColors.navyDeep;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.note, style: const TextStyle(fontSize: 13, height: 1.7)),
                const SizedBox(height: 20),
                TextField(
                  controller: _c,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'المسار على السيرفر',
                    hintText: widget.hint,
                    prefixIcon: const Icon(Icons.folder_open_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (widget.confirmWord != null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirm,
                    decoration: InputDecoration(
                      labelText: 'اكتب «${widget.confirmWord}» للتأكيد',
                      prefixIcon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 8),
                // ⚠️ المسار يُفحص في الخادم (مطلق · ليس مجلد نظام · ليس داخل التخزين)،
                //    ونُنبّه هنا مسبقاً لتقليل المحاولات الفاشلة.
                Text(
                  'المسار على **جهاز السيرفر** لا على جهازك. يجب أن يبدأ بحرف قرص، '
                  'وألّا يكون داخل مجلد نظام أو داخل مجلد تخزين البرنامج.',
                  style: TextStyle(fontSize: 12, height: 1.6,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: color),
                        onPressed: _ready ? () => Navigator.pop(context, _c.text.trim()) : null,
                        child: Text(widget.actionLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
