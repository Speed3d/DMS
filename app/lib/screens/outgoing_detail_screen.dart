import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';
import 'outgoing_edit_approved_screen.dart';
import 'outgoing_edit_draft_screen.dart';

/// Hint: شاشة تفاصيل الصادر بتصميم أنيق يعتمد على البطاقات
class OutgoingDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const OutgoingDetailScreen({super.key, required this.id});
  @override
  ConsumerState<OutgoingDetailScreen> createState() => _OutgoingDetailScreenState();
}

class _OutgoingDetailScreenState extends ConsumerState<OutgoingDetailScreen> {
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
      _snack('تم الاعتماد وتوليد الرقم والـ PDF بنجاح.');
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

  Future<void> _previewDraft() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).previewDraftPdf(widget.id);
      await downloadBytes(bytes, 'draft-preview-${widget.id}.pdf', 'application/pdf');
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

  Future<void> _editDraft(OutgoingDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OutgoingEditDraftScreen(book: d)));
    if (changed == true) {
      _snack('تم حفظ التعديل.');
      _reload();
    }
  }

  Future<void> _showVersions() async {
    try {
      final versions = await ref.read(apiClientProvider).versions(widget.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: versions.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Text('لا توجد إصدارات سابقة لهذا الكتاب.', style: TextStyle(fontWeight: FontWeight.bold)))
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text('سجل الإصدارات (Versions)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 16),
                    for (final v in versions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navyDeep.withValues(alpha: 0.1),
                            foregroundColor: AppColors.navyDeep,
                            child: Text('V${v.versionNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          title: Text(v.changeNote ?? 'تعديل على محتوى الكتاب', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(v.changedAt)),
                        ),
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
        content: const Text('هل أنت متأكد من نقل هذا الكتاب إلى سلة المهملات؟'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف نهائي'),
          ),
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
      SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الكتاب الصادر'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            tooltip: 'حذف الكتاب',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<OutgoingDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final d = snap.data!;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // Hint: ترويسة الكتاب (الإجراءات والحالة)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StatusPill(status: d.isFinal ? 'Final' : 'Draft'),
                      const SizedBox(width: 16),
                      Text(
                        d.number ?? 'مسودة (بلا رقم حتى الآن)',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, fontFamily: 'Tahoma', letterSpacing: -0.5),
                      ),
                      const Spacer(),
                      // أزرار الإجراءات السريعة
                      if (!d.isFinal) ...[
                        _buildActionButton('تعديل المسودة', Icons.edit_document, AppColors.warn, () => _editDraft(d)),
                        _buildActionButton('معاينة القالب', Icons.preview_rounded, AppColors.gold, _previewDraft),
                        _buildActionButton('اعتماد وإصدار', Icons.verified_rounded, AppColors.success, _approve, isFilled: true),
                      ],
                      if (d.hasPdf)
                        _buildActionButton('تحميل PDF', Icons.picture_as_pdf_rounded, AppColors.gold, _downloadPdf),
                      if (d.isFinal) ...[
                        _buildActionButton('تعديل كإصدار', Icons.edit_document, AppColors.warn, () => _editApproved(d)),
                        _buildActionButton('سجل الإصدارات', Icons.history_rounded, AppColors.navyDeep, _showVersions),
                      ]
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Hint: تفاصيل الكتاب موزعة على شكل بطاقات
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // القسم الأيمن (معلومات وصفية)
                      Expanded(
                        flex: 4,
                        child: CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('المعلومات الأساسية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Divider(height: 32),
                              _buildInfoRow('الموضوع', d.subject, Icons.subject_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('تاريخ الكتاب', DateFormat('yyyy/MM/dd').format(d.date), Icons.calendar_month_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('الجهة المقصودة', d.entityName, Icons.business_rounded),
                              if (d.signatoryName != null && d.signatoryName!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _buildInfoRow('الموقّع', '${d.signatoryName}${d.signatoryTitle != null && d.signatoryTitle!.isNotEmpty ? ' - ${d.signatoryTitle}' : ''}', Icons.person_rounded),
                              ],
                              
                              if (d.amount != null) ...[
                                const Divider(height: 32),
                                const Text('التفاصيل المالية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                _buildInfoRow('المبلغ الأصلي', '${_fmt(d.amount!)} ${d.currency == 'USD' ? 'دولار' : 'دينار'}', Icons.monetization_on_rounded),
                                if (d.currency == 'USD') ...[
                                  const SizedBox(height: 16),
                                  _buildInfoRow('سعر الصرف', '${d.exchangeRate}', Icons.currency_exchange_rounded),
                                ],
                                const SizedBox(height: 16),
                                _buildInfoRow('المعادل بالدينار', '${_fmt(d.amountInIqd ?? 0)} د.ع', Icons.payments_rounded),
                              ],

                              if (d.qrContent != null) ...[
                                const Divider(height: 32),
                                const Text('محتوى ختم الـ QR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SelectableText(
                                    d.qrContent!,
                                    style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8), fontFamily: 'Courier'),
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),

                      // القسم الأيسر (محتوى النص)
                      Expanded(
                        flex: 6,
                        child: CustomCard(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.segment_rounded, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
                                  const SizedBox(width: 8),
                                  const Text('نص الكتاب (المحتوى)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              const Divider(height: 32),
                              // TODO: عندما نقوم بدمج flutter_quill سنقوم بعرض المحتوى بشكل أفضل
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: SelectableText(
                                  d.bodyHtml.replaceAll(RegExp(r'<[^>]*>'), ''), // إزالة مؤقتة للـ HTML tags حتى يتم إضافة Quill
                                  style: const TextStyle(fontSize: 15, height: 1.8),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap, {bool isFilled = false}) {
    if (_busy) return const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: CircularProgressIndicator());
    
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: isFilled
          ? FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
    );
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
