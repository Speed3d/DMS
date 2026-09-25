import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/backup_upload.dart';
import '../core/downloader.dart';
import '../core/job_watcher.dart';
import '../core/session.dart';
import '../core/backup_providers.dart';
import '../widgets/backup_alert.dart';
import '../widgets/job_progress_card.dart';
import '../core/theme.dart';
import '../models.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _State();
}

class _State extends ConsumerState<BackupScreen> {
  BackupScheduleModel? _schedule;
  List<BackupRecordModel> _list = [];
  String _freq = 'Off';
  bool _enabled = false;
  int _hour = 2;
  bool _loading = true, _busy = false;
  String? _error, _info;

  /// العملية الطويلة الجارية (نسخ · مرآة · استعادة) — تُعرض بطاقةَ تقدّمٍ أعلى الشاشة.
  JobInfo? _job;

  /// رفعُ نسخةٍ من الجهاز الجاري (ADR-055) — اسمُ الملف ونسبةُ ما وصل (قبل أن يبدأ الفحص في الخادم).
  String? _uploadName;
  double _uploadProgress = 0;

  // فلترة القائمة — **محلّية**: النسخ عشراتٌ لا آلاف (سياسة الاحتفاظ تقلّمها).
  final _search = TextEditingController();
  String? _kindFilter;
  String? _scopeFilter;
  bool? _statusFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) => _resumeRunning());
  }

  // ─────────────────────────── العمليات الطويلة ───────────────────────────
  //
  // ⚙️ **تبدأ ولا تنتظر** (حدّ Cloudflare ~100 ثانية): الزرّ يبدأ العملية في الخادم ويعود
  //    فوراً، وهذه الشاشة **تتابعها** حتى تنتهي. ومغادرةُ الشاشة أو إغلاقُ المتصفّح لا يوقفها.

  /// إن كانت عمليةٌ جارية (بدأها المالك ثم غادر الشاشة) تُستأنف متابعتها.
  Future<void> _resumeRunning() async {
    try {
      final running = await ref.read(apiClientProvider).currentJob();
      if (running == null || !mounted) return;
      setState(() { _busy = true; _error = null; _info = null; });
      await _follow(running);
    } on ApiException {
      // لا شيء يُستأنف — الشاشة تعمل كالمعتاد.
    } finally {
      if (mounted) setState(() { _busy = false; _job = null; });
    }
  }

  /// يبدأ عمليةً ثم يتابعها حتى تنتهي — **والرفض الفوريّ** (تأكيدٌ خاطئ · مسارٌ مرفوض ·
  /// عمليةٌ أخرى جارية) **يعود رسالةً كما كان** قبل أن يبدأ شيء.
  Future<void> _runJob(Future<JobInfo> Function() start) async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await _follow(await start());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() { _busy = false; _job = null; });
    }
  }

  Future<void> _follow(JobInfo started) async {
    if (mounted) setState(() => _job = started);
    final end = await watchJob(ref.read(apiClientProvider), started,
        onUpdate: (j) { if (mounted) setState(() => _job = j); });
    if (!mounted) return;
    setState(() {
      if (end.succeeded) {
        _info = end.message ?? 'اكتملت العملية.';
      } else {
        _error = end.message ?? 'فشلت العملية.';
      }
    });
    // Hint: القائمة (وبعد الاستعادة القاعدةُ كلُّها) تغيّرت — تُعاد قراءتها.
    await _load(keepMessages: true);
  }

  /// [keepMessages]: بعد انتهاء عمليةٍ طويلة تُعاد القراءة **مع إبقاء رسالتها** — مسحُها
  /// يُخفي سبب الفشل (أو خبر النجاح) في اللحظة التي يحتاجه فيها المالك.
  Future<void> _load({bool keepMessages = false}) async {
    if (!mounted) return;
    setState(() { _loading = true; if (!keepMessages) _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      _schedule = await api.backupSchedule();
      _list = await api.backupList();

      // 🔴 **التغطية تُقرأ من المزوّد العامّ لا من حالةٍ محلية** — لأن التنبيه صار يظهر
      //    في القائمة الجانبية والشريط العلوي كذلك، **وحالتان لرقمٍ واحد تتباعدان**:
      //    تُؤخذ النسخة فتختفي البطاقة وتبقى الشارة (أو العكس).
      ref.invalidate(backupCoverageProvider);
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

    // رسالة النجاح (المنسوخ · المتخطّى · حال القاعدة) يكتبها الخادم.
    await _runJob(() => ref.read(apiClientProvider).backupMirror(path.trim()));
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

    await _runJob(() => ref.read(apiClientProvider).backupRestoreFromMirror(path.trim()));
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

  Future<void> _runNow() => _runJob(() => ref.read(apiClientProvider).backupRun());

  /// **استعادة نسخةٍ من جهازي** (ADR-055) — يرفع ملف `.zip` بقطع، ثم يفحصه الخادم ويضيفه إلى القائمة.
  ///
  /// 🐛 **بلاغ المالك (2026-09-24)**: نسخةٌ من جهاز التطوير لم تكن تُستعاد على الدومين ولا العكس — لا طريق
  /// لإدخالها. 🔑 **الرفع لا يستعيد**: تظهر النسخة في القائمة، والاستعادة بزرّها القائم وضماناته.
  Future<void> _uploadFromDevice() async {
    // ⚠️ **تدفّقٌ لا بايتات**: `withReadStream` فلا يُحمَّل الملف كلُّه في ذاكرة المتصفّح.
    final picked = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: const ['zip'], withReadStream: true);
    final file = picked?.files.single;
    if (file == null || file.readStream == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _uploadName = file.name;
      _uploadProgress = 0;
    });
    try {
      final job = await uploadBackupFile(
        ref.read(apiClientProvider),
        fileName: file.name,
        sizeBytes: file.size,
        content: file.readStream!,
        onProgress: (p) { if (mounted) setState(() => _uploadProgress = p); },
      );
      if (mounted) setState(() => _uploadName = null);
      await _follow(job);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = 'تعذّر رفع النسخة: ${e.message}');
    } finally {
      if (mounted) setState(() { _busy = false; _job = null; _uploadName = null; });
    }
  }

  /// استعادة نسخة — عملية تدميرية، لذا التأكيد بكتابة الكلمة يدوياً لا بزرّ واحد.
  /// Hint: شاشة كاملة لا حوار (حقل نصّي داخل حوار يسبب خلل disposed EngineFlutterView على الويب).
  Future<void> _restore(BackupRecordModel r) async {
    final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _RestoreConfirmPage(record: r, fmtSize: _size, fmtDate: _dt)));
    if (confirmed != true) return;

    // رسالة النجاح (ومعها فجوة المرفقات إن وُجدت) يكتبها الخادم.
    await _runJob(() => ref.read(apiClientProvider).backupRestore(r.id));
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
    // ⚠️ **اللون والأيقونة من `backup_alert.dart` لا نسخةٌ هنا** — ثلاثة مواضع تعرض
    //    التنبيه الآن (البطاقة · الشارة · الأيقونة)، وخرائطُ ألوانٍ متعدّدة تتباعد
    //    **فيتناقض التنبيه مع نفسه فلا يُصدَّق**.
    final color = backupUrgencyColor(c.urgency);
    final icon = backupUrgencyIcon(c.urgency);

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
              const SizedBox(height: 6),
              // ⚠️ **الأزرار في الشريط أعلى الشاشة** — والبطاقة تشرح وحدها (كان الزرّان هنا وحدهما،
              //    فبحث المالك عن «استعادة» فوجد «استعادة من مرآة» ووجّهه إلى نسخةٍ عادية).
              const Text(
                'تُشغَّل من «تشغيل المرآة» في الشريط أعلاه، وتُستعاد من «استعادة من مرآة». '
                'أمّا الملف المضغوط (.zip) الذي تنزّله من القائمة فيُستعاد من «استعادة نسخة من جهازي».',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
          ),
        ),
      );
  String _dt(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());

  /// القائمة بعد الفلترة — دالّةٌ نقيّة في `models.dart` (ADR-042).
  List<BackupRecordModel> get _shown => filterBackups(_list,
      kind: _kindFilter, scope: _scopeFilter, succeeded: _statusFilter, query: _search.text);

  /// 🔎 **بحثٌ وفلترة** (ADR-055) — بالاسم والملاحظة والنوع والنطاق والحالة.
  Widget _filterBar() => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              key: const Key('backup-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'بحث في الاسم والملاحظة'),
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String?>(
              key: const Key('backup-kind-filter'),
              initialValue: _kindFilter,
              isDense: true,
              // ⚠️ **يُقصّ داخل عرضه لا يفيض** — كان «قاعدة فقط» يفيض بكسلين حين يكبر الخطّ.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'النوع', isDense: true),
              items: [for (final e in kBackupKindFilters.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _kindFilter = v),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              initialValue: _scopeFilter,
              isDense: true,
              // ⚠️ **يُقصّ داخل عرضه لا يفيض** — كان «قاعدة فقط» يفيض بكسلين حين يكبر الخطّ.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'النطاق', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'Full', child: Text('كاملة')),
                DropdownMenuItem(value: 'DbOnly', child: Text('قاعدة فقط')),
              ],
              onChanged: (v) => setState(() => _scopeFilter = v),
            ),
          ),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<bool?>(
              initialValue: _statusFilter,
              isDense: true,
              // ⚠️ **يُقصّ داخل عرضه لا يفيض** — كان «قاعدة فقط» يفيض بكسلين حين يكبر الخطّ.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الحالة', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: true, child: Text('ناجحة')),
                DropdownMenuItem(value: false, child: Text('فاشلة')),
              ],
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
          ),
        ],
      );

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

          // 🧰 **شريط الأزرار — كلُّ ما يُفعل هنا في موضعٍ واحد** (ADR-055، طلب المالك). كانت الاستعادة
          //    من الجهاز غائبة، و«استعادة من مرآة» مدفونةً في بطاقتها فظُنّت الاستعادةَ الوحيدة.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const Key('backup-run-now'),
                onPressed: _busy ? null : _runNow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.action(context),
                  foregroundColor: AppColors.onAction(context),
                ),
                icon: const Icon(Icons.backup_rounded, size: 18),
                label: const Text('أخذ نسخة الآن'),
              ),
              OutlinedButton.icon(
                key: const Key('backup-upload'),
                onPressed: _busy ? null : _uploadFromDevice,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('استعادة نسخة من جهازي'),
              ),
              OutlinedButton.icon(
                key: const Key('backup-mirror-restore'),
                onPressed: _busy ? null : _restoreMirror,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                label: const Text('استعادة من مرآة'),
              ),
              OutlinedButton.icon(
                key: const Key('backup-mirror-run'),
                onPressed: _busy ? null : _runMirror,
                icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                label: const Text('تشغيل المرآة'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('تحديث'),
              ),
            ],
          ),
          if (_info != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_info!, style: const TextStyle(color: Colors.green))),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),

          // ⬆️ **الرفع قبل أن يبدأ الفحص** — نسبةُ ما وصل الخادم (والفحص بعده بطاقةُ العمليات المعتادة).
          if (_uploadName != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رفع النسخة: $_uploadName',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 6),
                    Text('${(_uploadProgress * 100).toStringAsFixed(0)}% — لا تغلق الصفحة حتى يكتمل الرفع.',
                        style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ⚙️ العملية الجارية أعلى الشاشة — **فوق كل شيء** لأنها ما ينتظره المالك الآن.
          if (_job != null) ...[
            JobProgressCard(job: _job!),
            const SizedBox(height: 16),
          ],

          ...(() {
            final c = ref.watch(backupCoverageProvider).asData?.value;
            return [
              if (c != null) _coverageCard(c),
              if (c != null) const SizedBox(height: 16),
            ];
          })(),

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

          Text(
              _shown.length == _list.length
                  ? 'النسخ السابقة (${_list.length})'
                  : 'النسخ السابقة — المعروض ${_shown.length} من ${_list.length}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _filterBar(),
          const SizedBox(height: 10),
          if (_list.isEmpty)
            const Text('لا توجد نسخ بعد.', style: TextStyle(color: Colors.grey))
          else if (_shown.isEmpty)
            const Text('لا نسخ تطابق البحث.', style: TextStyle(color: Colors.grey))
          else
            ..._shown.map((r) => Card(
                  child: ListTile(
                    leading: Icon(r.status == 'Success' ? Icons.check_circle : Icons.error,
                        color: r.status == 'Success' ? Colors.green : Colors.red),
                    title: Text(_dt(r.createdAt)),
                    // النطاق والتصنيف يوضّحان ماذا تتضمّن النسخة ولماذا يختلف حجمها.
                    subtitle: Text(
                        '${backupKindLabel(r)} • ${backupScopeLabel(r.scope)} • ${_size(r.sizeBytes)}'
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
    final color = widget.danger ? AppColors.danger : AppColors.action(context);
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
