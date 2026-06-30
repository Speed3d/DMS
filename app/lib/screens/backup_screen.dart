import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
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
      _freq = _schedule!.frequency;
      _enabled = _schedule!.enabled;
      _hour = _schedule!.hour;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
          const Text('يشمل قاعدة البيانات وملفات المرفقات/المستندات في أرشيف مضغوط.',
              style: TextStyle(color: Colors.grey)),
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

          Row(children: [
            FilledButton.icon(
              onPressed: _busy ? null : _runNow,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
              label: const Text('نسخة احتياطية الآن'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
          ]),
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
                    subtitle: Text('${r.type == 'Manual' ? 'يدوي' : 'مجدول'} • ${_size(r.sizeBytes)}${r.note != null ? '\n${r.note}' : ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'تنزيل',
                      onPressed: r.status == 'Success' ? () => _download(r) : null,
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
