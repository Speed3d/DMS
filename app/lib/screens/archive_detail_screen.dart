import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/attachment_viewer.dart';
import '../widgets/custom_card.dart';
import 'archive_form_screen.dart';

/// Hint: شاشة تفاصيل الأرشيف مع التصميم الموحد ومساحة عرض المستندات والمرفقات
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: error ? AppColors.danger : AppColors.navyDeep,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
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
      _snack('تم رفع المرفق بنجاح.');
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
      // inline حتى هنا: نجلب البايتات بـXHR ونحفظها بأنفسنا، فترويسةُ «تنزيل» من الخادم
      // ضررُها فقط — يختطف مديرُ التحميل الطلبَ فلا يصل ردّ (انظر api_client).
      final bytes = await ref.read(apiClientProvider).downloadAttachment(a.attachmentId, inline: true);
      await downloadBytes(bytes, a.fileName, 'application/octet-stream');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// عرض المرفق داخل التطبيق بدل تنزيله (PDF والصور).
  Future<void> _view(AttachmentModel a) async {
    setState(() => _busy = true);
    try {
      // inline: للعرض لا للتنزيل — وإلا اختطف مديرُ التحميل الطلب (انظر api_client).
      final bytes = await ref.read(apiClientProvider).downloadAttachment(a.attachmentId, inline: true);
      if (!mounted) return;
      await AttachmentViewer.show(
        context,
        bytes: bytes,
        fileName: a.fileName,
        onDownload: () => downloadBytes(bytes, a.fileName, 'application/octet-stream'),
      );
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
        content: const Text('هل أنت متأكد من نقل هذا المستند إلى سلة المهملات؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('حذف'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          ),
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
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الأرشيف'),
        centerTitle: true,
      ),
      body: FutureBuilder<ArchiveDetail>(
        future: _doc,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ أثناء تحميل البيانات: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final d = snap.data!;
          
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // القسم الأيمن (البيانات الأساسية والإجراءات والمرفقات)
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        // بطاقة التحكم (إجراءات)
                        CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(d.archiveNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
                                  const Spacer(),
                                  Text('رقم الأرشيف', style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5), fontSize: 12)),
                                ],
                              ),
                              const Divider(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _edit(d),
                                      icon: const Icon(Icons.edit_rounded, size: 18),
                                      label: const Text('تعديل المستند'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _deleteArchive,
                                      icon: const Icon(Icons.delete_rounded, size: 18),
                                      label: const Text('حذف'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.danger,
                                        side: const BorderSide(color: AppColors.danger),
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // بطاقة المعلومات الأساسية
                        CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, color: AppColors.navyDeep),
                                  SizedBox(width: 8),
                                  Text('المعلومات الأساسية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 24),
                              _detailRow('عنوان المستند', d.title, theme),
                              if (d.bookNumber != null) _detailRow('رقم الكتاب', d.bookNumber!, theme),
                              if (d.bookDate != null) _detailRow('تاريخ الكتاب', DateFormat('yyyy/MM/dd').format(d.bookDate!), theme),
                              _detailRow('تاريخ الأرشفة', d.bookDate == null ? '-' : DateFormat('yyyy/MM/dd HH:mm').format(d.bookDate!), theme),
                              if (d.documentTypeId != null)
                                _detailRow('نوع المستند', d.documentTypeName ?? '—', theme),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // التفاصيل المالية والإضافية
                        if (d.amount != null || d.keywords != null || d.notes != null)
                          CustomCard(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.feed_rounded, color: AppColors.navyDeep),
                                    SizedBox(width: 8),
                                    Text('التفاصيل الإضافية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(height: 24),
                                if (d.amount != null) ...[
                                  _detailRow('المبلغ', '${_fmt(d.amount!)} ${d.currency == 'USD' ? 'دولار' : 'دينار'}', theme),
                                  if (d.currency == 'USD') _detailRow('سعر الصرف', '${d.exchangeRate}', theme),
                                  _detailRow('المعادل بالدينار', '${_fmt(d.amountInIqd!)} د.ع', theme),
                                ],
                                if (d.keywords != null) _detailRow('كلمات مفتاحية', d.keywords!, theme),
                                if (d.notes != null) _detailRow('ملاحظات', d.notes!, theme),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // القسم الأيسر (عرض محتوى HTML والمرفقات)
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 32, top: 32, bottom: 32),
                      child: CustomCard(
                        padding: const EdgeInsets.all(0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // رأس التبويبات أو العنوان
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: theme.dividerColor)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.visibility_rounded, color: AppColors.navyDeep),
                                  SizedBox(width: 8),
                                  Text('محتوى الأرشيف والمرفقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            
                            // محتوى HTML إذا وجد
                            if (d.bodyHtml != null && d.bodyHtml!.trim().isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(24),
                                constraints: const BoxConstraints(minHeight: 200),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: theme.dividerColor)),
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    // Hint: كحل مؤقت لعرض النص إذا لم نستخدم حزمة Html مباشرة. نستبدل <br> بـسطر جديد.
                                    d.bodyHtml!.replaceAll('<br>', '\n'),
                                    style: const TextStyle(fontSize: 15, height: 1.6),
                                  ),
                                ),
                              ),
                            ],

                            // قسم المرفقات
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Row(
                                      children: [
                                        const Text('المرفقات المحفوظة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        const Spacer(),
                                        FilledButton.icon(
                                          onPressed: _busy ? null : _addAttachment,
                                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                                          label: const Text('رفع ملف'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.navyDeep,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: FutureBuilder<List<AttachmentModel>>(
                                      future: _attachments,
                                      builder: (context, asnap) {
                                        if (asnap.connectionState != ConnectionState.done) {
                                          return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                                        }
                                        final list = asnap.data ?? [];
                                        if (list.isEmpty) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.attachment_rounded, size: 48, color: theme.dividerColor),
                                                const SizedBox(height: 16),
                                                Text('لا توجد مرفقات لهذا المستند', style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
                                              ],
                                            ),
                                          );
                                        }
                                        return ListView.separated(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                          itemCount: list.length,
                                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                                          itemBuilder: (_, i) {
                                            final a = list[i];
                                            return Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(color: theme.dividerColor),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              // ⚠️ صفٌّ صريح لا ListTile: ثلاثة أزرار في `trailing`
                                              // تستهلك عرض السطر كلَّه في بطاقة ضيّقة («Trailing widget
                                              // consumes the entire tile width»)، والحاوية هنا ليست
                                              // Material فيختفي أثر النقر. نفس علاج شاشة الوارد.
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(12),
                                                      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                                                      child: Icon(_fileIcon(a.fileType), color: AppColors.navyDeep),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                      child: InkWell(
                                                        onTap: _busy || !AttachmentViewer.canView(a.fileName)
                                                            ? null
                                                            : () => _view(a),
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                                              Text('${a.fileType.toUpperCase()} • ${(a.fileSize / 1024).toStringAsFixed(0)} KB', style: const TextStyle(fontSize: 12)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (AttachmentViewer.canView(a.fileName))
                                                      IconButton(
                                                        icon: const Icon(Icons.visibility_rounded),
                                                        color: AppColors.navyDeep,
                                                        onPressed: _busy ? null : () => _view(a),
                                                        tooltip: 'عرض',
                                                      ),
                                                    IconButton(
                                                      icon: const Icon(Icons.download_rounded),
                                                      color: AppColors.navyDeep,
                                                      onPressed: _busy ? null : () => _download(a),
                                                      tooltip: 'تحميل',
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline_rounded),
                                                      color: AppColors.danger,
                                                      onPressed: () => _deleteAttachment(a),
                                                      tooltip: 'حذف المرفق',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

  IconData _fileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'jpg': case 'jpeg': case 'png': return Icons.image_rounded;
      case 'docx': case 'doc': return Icons.description_rounded;
      case 'xlsx': case 'xls': return Icons.table_chart_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  Widget _detailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
