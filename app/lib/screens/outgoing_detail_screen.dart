import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';
import 'outgoing_edit_approved_screen.dart';

class OutgoingDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const OutgoingDetailScreen({super.key, required this.id});
  @override
  ConsumerState<OutgoingDetailScreen> createState() => _State();
}

class _State extends ConsumerState<OutgoingDetailScreen> {
  late Future<OutgoingDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).outgoingGet(widget.id);
    setState(() {});
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).approve(widget.id);
      _snack('تم الاعتماد وتوليد الرقم والـ PDF.');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).outgoingPdf(widget.id);
      await downloadBytes(bytes, 'book-${widget.id}.pdf', 'application/pdf');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editApproved(OutgoingDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OutgoingEditApprovedScreen(book: d)));
    if (changed == true) {
      _snack('تم حفظ التعديل وإنشاء إصدار جديد.');
      _reload();
    }
  }

  Future<void> _showVersions() async {
    try {
      final versions = await ref.read(apiClientProvider).versions(widget.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: versions.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد إصدارات سابقة.'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('سجل الإصدارات', style: TextStyle(fontWeight: FontWeight.bold))),
                    for (final v in versions)
                      ListTile(
                        leading: CircleAvatar(child: Text('${v.versionNo}')),
                        title: Text(v.changeNote ?? 'تعديل'),
                        subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(v.changedAt)),
                      ),
                  ],
                ),
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('حذف ناعم لهذا الكتاب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteOutgoing(widget.id);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الكتاب'),
        actions: [IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: FutureBuilder<OutgoingDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final d = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(d.isFinal ? 'معتمد' : 'مسودّة'),
                        backgroundColor: d.isFinal ? Colors.green.shade100 : Colors.orange.shade100,
                      ),
                      const Spacer(),
                      if (d.number != null)
                        Text(d.number!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const Divider(height: 32),
                  _row('الموضوع', d.subject),
                  _row('الجهة', d.entityName),
                  _row('التاريخ', DateFormat('yyyy-MM-dd').format(d.date)),
                  _row('النص', d.bodyHtml),
                  if (d.amount != null) ...[
                    const Divider(height: 32),
                    _row('المبلغ', '${d.amount} ${d.currency == 'USD' ? 'دولار' : 'دينار'}'),
                    if (d.currency == 'USD') _row('سعر الصرف', '${d.exchangeRate}'),
                    _row('المعادل بالدينار', '${d.amountInIqd} د.ع'),
                  ],
                  if (d.qrContent != null) ...[
                    const Divider(height: 32),
                    const Text('محتوى QR الموقّع:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SelectableText(d.qrContent!, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!d.isFinal)
                        FilledButton.icon(
                          onPressed: _busy ? null : _approve,
                          icon: const Icon(Icons.verified),
                          label: const Text('اعتماد'),
                        ),
                      if (d.hasPdf)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _downloadPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('تنزيل PDF'),
                        ),
                      if (d.isFinal)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _editApproved(d),
                          icon: const Icon(Icons.edit_document),
                          label: const Text('تعديل (إصدار جديد)'),
                        ),
                      if (d.isFinal)
                        TextButton.icon(
                          onPressed: _busy ? null : _showVersions,
                          icon: const Icon(Icons.history),
                          label: const Text('الإصدارات'),
                        ),
                    ],
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
