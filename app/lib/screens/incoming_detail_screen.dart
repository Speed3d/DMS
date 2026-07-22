import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/incoming_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';
import 'incoming_form_screen.dart';

/// Hint: شاشة تفاصيل الكتاب الوارد (تعرض المعلومات، المرفقات، سجل الحركة)
class IncomingDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const IncomingDetailScreen({super.key, required this.id});
  @override
  ConsumerState<IncomingDetailScreen> createState() => _IncomingDetailScreenState();
}

class _IncomingDetailScreenState extends ConsumerState<IncomingDetailScreen> {
  late Future<IncomingDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).incomingGet(widget.id);
    // Reload attachments and movements providers silently
    ref.invalidate(incomingAttachmentsProvider(widget.id));
    ref.invalidate(incomingMovementsProvider(widget.id));
    setState(() {});
  }

  Future<void> _edit(IncomingDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => IncomingFormScreen(bookId: d.incomingId)));
    if (changed == true) {
      _snack('تم حفظ التعديل.');
      invalidateIncoming(ref);
      _reload();
    }
  }

  Future<void> _changeStatus(IncomingDetail d) async {
    // Hint: نعرض الانتقالات المسموحة فقط (مرآة لمصفوفة الباك-إند) بدل ترك المستخدم يصطدم برفض من الخادم.
    final allowed = kIncomingTransitions[d.status] ?? const <String>[];
    if (allowed.isEmpty) {
      _snack('لا توجد حالة لاحقة متاحة — الكتاب في حالة (${incomingStatusLabel(d.status)}).', error: true);
      return;
    }

    String? newStatus;
    String note = '';
    String? noteError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        // Hint: الملاحظة إلزامية عند «تم الرد» يدوياً بلا ربط بصادر — نفس قاعدة الباك-إند.
        final noteRequired = newStatus == 'Replied' && d.replyOutgoingId == null;
        return AlertDialog(
          title: const Text('تغيير حالة الكتاب'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الحالة الحالية: ${incomingStatusLabel(d.status)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: newStatus,
                decoration: const InputDecoration(labelText: 'الحالة الجديدة'),
                items: allowed
                    .map((s) => DropdownMenuItem(value: s, child: Text(incomingStatusLabel(s))))
                    .toList(),
                onChanged: (v) => setDialogState(() => newStatus = v),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: noteRequired ? 'ملاحظة (إلزامية)' : 'ملاحظة (اختياري)',
                  errorText: noteError,
                ),
                onChanged: (v) => setDialogState(() {
                  note = v;
                  noteError = null;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: newStatus == null
                  ? null
                  : () {
                      if (noteRequired && note.trim().isEmpty) {
                        setDialogState(() =>
                            noteError = 'الملاحظة إلزامية عند اختيار (تم الرد) بدون ربط بكتاب صادر.');
                        return;
                      }
                      Navigator.pop(c, true);
                    },
              child: const Text('تأكيد'),
            ),
          ],
        );
      }),
    );

    final chosen = newStatus;
    if (ok != true || chosen == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider)
          .changeIncomingStatus(widget.id, chosen, note.trim().isEmpty ? null : note.trim());
      _snack('تم تغيير الحالة بنجاح.');
      invalidateIncoming(ref);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forwardBook() async {
    String toDept = '';
    String note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إحالة الكتاب'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'القسم المُحال إليه'),
              onChanged: (v) => toDept = v,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'ملاحظة أو توجيه'),
              onChanged: (v) => note = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(c, toDept.trim().isNotEmpty),
            child: const Text('إحالة'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).forwardIncoming(widget.id, toDept.trim(), note);
      _snack('تمت الإحالة بنجاح.');
      invalidateIncoming(ref);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الكتاب الوارد نهائياً؟'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    try {
      await ref.read(apiClientProvider).deleteIncoming(widget.id);
      ref.invalidate(incomingListProvider);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الكتاب الوارد'),
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
      body: FutureBuilder<IncomingDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(
                child: Text('حدث خطأ: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final d = snap.data!;
          final currentUser = ref.watch(sessionProvider).auth;
          // سجل الحركة يظهر فقط للسوبر أدمن والرئيس
          final canViewMovements =
              currentUser != null && (currentUser.isSuperAdmin || currentUser.role == 'President');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // ترويسة الكتاب (الإجراءات والحالة)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StatusPill(status: d.status),
                      const SizedBox(width: 16),
                      Text(
                        d.incomingNumber ?? 'وارد بلا رقم داخلي',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            fontFamily: 'Tahoma',
                            letterSpacing: -0.5),
                      ),
                      const Spacer(),
                      // الأزرار
                      // Hint: تعطيل الأزرار حسب الحالة — انعكاس لقواعد الباك-إند
                      // (التعديل للكتاب الجديد فقط، والإحالة للجديد/قيد المراجعة، والحالة النهائية بلا انتقالات).
                      _buildActionButton('تعديل', Icons.edit_document, AppColors.warn,
                          d.status == 'New' ? () => _edit(d) : null,
                          disabledHint: 'التعديل متاح للكتاب في حالة (جديد) فقط'),
                      _buildActionButton('تغيير الحالة', Icons.swap_horiz_rounded, Colors.blue,
                          (kIncomingTransitions[d.status] ?? const []).isEmpty ? null : () => _changeStatus(d),
                          disabledHint: 'لا توجد حالة لاحقة متاحة'),
                      _buildActionButton('إحالة لقسم', Icons.forward_to_inbox_rounded, AppColors.navyDeep,
                          _isOperable(d.status) ? _forwardBook : null,
                          disabledHint: 'الإحالة متاحة للكتب (جديد) أو (قيد المراجعة) فقط'),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // القسم الأيمن (معلومات)
                      Expanded(
                        flex: 5,
                        child: CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('المعلومات الأساسية',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Divider(height: 32),
                              _buildInfoRow('الموضوع', d.subject, Icons.subject_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('الجهة المُرسلة', d.entityName, Icons.business_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('تاريخ الاستلام', DateFormat('yyyy/MM/dd').format(d.receivedDate),
                                  Icons.calendar_month_rounded),
                              if (d.receivedTime != null) ...[
                                const SizedBox(height: 16),
                                _buildInfoRow('وقت الاستلام', d.receivedTime!, Icons.access_time_rounded),
                              ],
                              const SizedBox(height: 16),
                              _buildInfoRow('رقم الكتاب الخارجي', d.externalNumber ?? 'لا يوجد', Icons.tag_rounded),
                              if (d.externalDate != null) ...[
                                const SizedBox(height: 16),
                                _buildInfoRow('تاريخ الكتاب الخارجي', DateFormat('yyyy/MM/dd').format(d.externalDate!),
                                    Icons.event_note_rounded),
                              ],
                              const SizedBox(height: 16),
                              _buildInfoRow('طريقة الاستلام', receiveMethodLabel(d.receiveMethod), Icons.inbox_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('القسم المحال إليه', d.folderName ?? 'غير محدد', Icons.folder_shared_rounded),
                              
                              if (d.amount != null) ...[
                                const Divider(height: 32),
                                const Text('التفاصيل المالية',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                _buildInfoRow('المبلغ الأصلي', '${_fmt(d.amount!)} ${d.currency == 'USD' ? 'دولار' : 'دينار'}',
                                    Icons.monetization_on_rounded),
                                if (d.currency == 'USD') ...[
                                  const SizedBox(height: 16),
                                  _buildInfoRow('سعر الصرف', '${d.exchangeRate}', Icons.currency_exchange_rounded),
                                ],
                                const SizedBox(height: 16),
                                _buildInfoRow('المعادل بالدينار', '${_fmt(d.amountInIqd ?? 0)} د.ع', Icons.payments_rounded),
                              ],

                              if (d.replyOutgoingId != null) ...[
                                const Divider(height: 32),
                                const Text('الارتباط بالصادر',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                _buildInfoRow('تم الرد بكتاب صادر رقم', d.replyOutgoingNumber ?? '#${d.replyOutgoingId}', Icons.link_rounded),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),

                      // القسم الأيسر (مرفقات + سجل حركة)
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // المرفقات
                            _AttachmentsWidget(incomingId: widget.id),
                            
                            const SizedBox(height: 24),
                            
                            // سجل الحركة (إن كان يملك الصلاحية)
                            if (canViewMovements)
                              _MovementsWidget(incomingId: widget.id),
                          ],
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
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  /// Hint: حالة الكتاب تسمح بالإجراءات التشغيلية (الإحالة/الربط) — مرآة لـ IncomingWorkflow.IsOperable.
  bool _isOperable(String status) => status == 'New' || status == 'InReview';

  /// Hint: [onTap] = null يعني الزر معطّل، ويُعرض سبب التعطيل في tooltip بالعربية.
  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap,
      {String? disabledHint}) {
    if (_busy) {
      return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8), child: CircularProgressIndicator());
    }
    final button = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
    if (onTap == null && disabledHint != null) {
      return Tooltip(message: disabledHint, child: button);
    }
    return button;
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

// ----------------- ويدجت المرفقات -----------------
class _AttachmentsWidget extends ConsumerWidget {
  final int incomingId;
  const _AttachmentsWidget({required this.incomingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAtt = ref.watch(incomingAttachmentsProvider(incomingId));
    
    return CustomCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attachment_rounded, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              const Text('المرفقات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const Divider(height: 32),
          asyncAtt.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: AppColors.danger)),
            data: (list) {
              if (list.isEmpty) {
                return const Text('لا توجد مرفقات مع هذا الكتاب الوارد.');
              }
              return Column(
                children: list.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_rounded, color: AppColors.gold),
                  title: Text(a.fileName),
                  subtitle: Text('${(a.fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () async {
                      try {
                        final bytes = await ref.read(apiClientProvider).downloadIncomingAttachment(incomingId, a.attachmentId);
                        if (context.mounted) {
                          await downloadBytes(bytes, a.fileName, '');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحميل: $e')));
                        }
                      }
                    },
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ----------------- ويدجت سجل الحركة -----------------
class _MovementsWidget extends ConsumerWidget {
  final int incomingId;
  const _MovementsWidget({required this.incomingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLog = ref.watch(incomingMovementsProvider(incomingId));

    return CustomCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              const Text('سجل الحركة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const Divider(height: 32),
          asyncLog.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: AppColors.danger)),
            data: (list) {
              if (list.isEmpty) {
                return const Text('لا يوجد سجل حركة مسجل.');
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final log = list[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 12),
                        child: CircleAvatar(
                          radius: 4,
                          backgroundColor: AppColors.navyDeep,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(log.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${log.performedByUserName} • ${DateFormat('yyyy/MM/dd HH:mm').format(log.performedAt)}',
                              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
