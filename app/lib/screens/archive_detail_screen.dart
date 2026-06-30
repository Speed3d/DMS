import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';
import 'archive_form_screen.dart';

class ArchiveDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const ArchiveDetailScreen({super.key, required this.id});
  @override
  ConsumerState<ArchiveDetailScreen> createState() => _State();
}

class _State extends ConsumerState<ArchiveDetailScreen> {
  late Future<ArchiveDetail> _doc;
  late Future<List<AttachmentModel>> _attachments;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _doc = ref.read(apiClientProvider).archiveGet(widget.id);
    _attachments = ref.read(apiClientProvider).archiveAttachments(widget.id);
    setState(() {});
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red : null));
  }

  Future<void> _edit(ArchiveDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ArchiveFormScreen(existing: d)));
    if (changed == true) _reload();
  }

  Future<void> _addAttachment() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx'],
      withData: true,
    );
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).uploadArchiveAttachment(widget.id, f.bytes!, f.name);
      _snack('تم رفع المرفق.');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(AttachmentModel a) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).downloadAttachment(a.attachmentId);
      await downloadBytes(bytes, a.fileName, 'application/octet-stream');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAttachment(AttachmentModel a) async {
    try {
      await ref.read(apiClientProvider).deleteAttachment(a.attachmentId);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _deleteArchive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('حذف ناعم لهذا المستند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteArchive(widget.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل مستند الأرشيف'),
        actions: [IconButton(onPressed: _deleteArchive, icon: const Icon(Icons.delete_outline))],
      ),
      body: FutureBuilder<ArchiveDetail>(
        future: _doc,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final d = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Row(children: [
                    Text(d.archiveNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const Spacer(),
                    TextButton.icon(onPressed: () => _edit(d), icon: const Icon(Icons.edit), label: const Text('تعديل')),
                  ]),
                  const Divider(height: 24),
                  _row('العنوان', d.title),
                  if (d.bookNumber != null) _row('رقم الكتاب', d.bookNumber!),
                  if (d.bookDate != null) _row('تاريخ الكتاب', DateFormat('yyyy-MM-dd').format(d.bookDate!)),
                  if (d.amount != null) ...[
                    _row('المبلغ', '${d.amount} ${d.currency == 'USD' ? 'دولار' : 'دينار'}'),
                    if (d.currency == 'USD') _row('سعر الصرف', '${d.exchangeRate}'),
                    _row('المعادل بالدينار', '${d.amountInIqd} د.ع'),
                  ],
                  if (d.keywords != null) _row('كلمات مفتاحية', d.keywords!),
                  if (d.notes != null) _row('ملاحظات', d.notes!),
                  const Divider(height: 32),
                  Row(children: [
                    const Text('المرفقات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    FilledButton.icon(onPressed: _busy ? null : _addAttachment, icon: const Icon(Icons.attach_file), label: const Text('إضافة مرفق')),
                  ]),
                  const SizedBox(height: 8),
                  FutureBuilder<List<AttachmentModel>>(
                    future: _attachments,
                    builder: (context, asnap) {
                      if (asnap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                      final list = asnap.data ?? [];
                      if (list.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد مرفقات.', style: TextStyle(color: Colors.black54)));
                      return Card(
                        child: Column(
                          children: [
                            for (final a in list)
                              ListTile(
                                leading: const Icon(Icons.insert_drive_file),
                                title: Text(a.fileName),
                                subtitle: Text('${a.fileType.toUpperCase()} • ${(a.fileSize / 1024).toStringAsFixed(0)} KB'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(icon: const Icon(Icons.download), onPressed: _busy ? null : () => _download(a)),
                                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteAttachment(a)),
                                ]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );
}
