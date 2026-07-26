import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/incoming_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/attachment_viewer.dart';
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
      final still = await ref.read(apiClientProvider)
          .changeIncomingStatus(widget.id, chosen, note.trim().isEmpty ? null : note.trim());
      invalidateIncoming(ref);
      if (!mounted) return;
      if (still == null) {
        // نجح التغيير لكنه أخرج الكتاب من نطاق رؤية المستخدم (الأرشفة مثلاً).
        _snack('تم تغيير الحالة — لم يعُد الكتاب ضمن نطاقك.');
        Navigator.of(context).pop(true);
        return;
      }
      _snack('تم تغيير الحالة بنجاح.');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forwardBook() async {
    // الأقسام النشطة فقط تصلح وجهةً للإحالة.
    final List<DepartmentModel> depts;
    try {
      depts = (await ref.read(apiClientProvider).departments()).where((d) => d.isActive).toList();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
      return;
    }
    if (!mounted) return;
    if (depts.isEmpty) {
      _snack('لا توجد أقسام. أضِف الأقسام من الإعدادات أولاً.', error: true);
      return;
    }

    // مسار الإحالات السابقة — من يقرّر الوجهة التالية يحتاج أن يعرف أين مرّ الكتاب
    // وما كُتب في كل إحالة. فشلُ الجلب لا يمنع الإحالة (السجل معلومة مساعدة).
    List<MovementLogItem> history = const [];
    try {
      history = (await ref.read(apiClientProvider).incomingMovements(widget.id))
          .where((m) => m.action == 'Forwarded')
          .toList();
    } on ApiException catch (_) {
      // القارئ محجوب عن السجل — ولا يصل هنا أصلاً لأنه لا يُحيل.
    }
    if (!mounted) return;

    int? deptId;
    String note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('إحالة الكتاب لقسم'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (history.isNotEmpty) ...[
                  _ForwardHistory(history: history),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<int?>(
                  initialValue: deptId,
                  decoration: const InputDecoration(labelText: 'القسم المُحال إليه'),
                  items: depts
                      .map((d) => DropdownMenuItem<int?>(value: d.departmentId, child: Text(d.name)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => deptId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(labelText: 'ملاحظة أو توجيه (اختياري)'),
                  onChanged: (v) => note = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: deptId == null ? null : () => Navigator.pop(c, true),
              child: const Text('إحالة'),
            ),
          ],
        );
      }),
    );
    if (ok != true || deptId == null) return;

    setState(() => _busy = true);
    try {
      final deptName = depts.firstWhere((d) => d.departmentId == deptId).name;
      final still = await ref.read(apiClientProvider)
          .forwardIncoming(widget.id, deptId!, note.trim().isEmpty ? null : note.trim());
      invalidateIncoming(ref);
      if (!mounted) return;
      if (still == null) {
        // الإحالة نجحت وخرج الكتاب من قسم المُحيل — نُغلق الشاشة بدل إعادة تحميل محكومة بالفشل.
        _snack('تمت الإحالة إلى «$deptName» — لم يعُد الكتاب ضمن قسمك.');
        Navigator.of(context).pop(true);
        return;
      }
      _snack('تمت الإحالة إلى «$deptName».');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ربط الكتاب بكتاب صادر معتمد (Hint: الاختيار عبر شاشة كاملة لا حوار — حقول البحث داخل
  /// الحوارات تسبب خلل `disposed EngineFlutterView` على الويب).
  Future<void> _linkToOutgoing() async {
    final outgoingId = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => const _OutgoingPickerScreen()));
    if (outgoingId == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).linkIncoming(widget.id, outgoingId);
      _snack('تم ربط الكتاب بالصادر بنجاح.');
      invalidateIncoming(ref);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkFromOutgoing(IncomingDetail d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('فك الارتباط'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('سيُفك ارتباط هذا الكتاب بالصادر رقم '
            '${d.replyOutgoingNumber ?? d.replyOutgoingId}، وتعود حالته إلى (قيد المراجعة). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('فك الارتباط')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).unlinkIncoming(widget.id);
      _snack('تم فك الارتباط.');
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
          final role = currentUser?.role ?? '';
          // سجل الحركة يراه كل من يستطيع الإحالة — أي كل الأدوار عدا القارئ
          // (مرآة لقاعدة الباك-إند في GetMovementsAsync).
          final canViewMovements = currentUser != null && role != 'Reader';
          // المدير فأعلى (Hint: مرآة لـ RequireRole(Manager) في الباك-إند)
          final isManagerOrAbove = role == 'SuperAdmin' || role == 'President' || role == 'Manager';
          final canManageLink = isManagerOrAbove;
          // التعديل: ممنوع على المؤرشف · المدير فأعلى في بقية الحالات · الموظف وهو (جديد) فقط
          final canEdit = d.status != 'Archived' && (isManagerOrAbove || d.status == 'New');
          // القارئ لا يعدّل المرفقات (Hint: مرآة لـ RequireNotReader في AttachmentService)
          final canEditAttachments = role.isNotEmpty && role != 'Reader';

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
                          canEdit ? () => _edit(d) : null,
                          disabledHint: d.status == 'Archived'
                              ? 'لا يمكن تعديل كتاب مؤرشف — الأرشفة نهائية'
                              : 'التعديل في هذه الحالة يتطلب صلاحية المدير فأعلى'),
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
                              _buildInfoRow('القسم المحال إليه', d.departmentName ?? 'غير محال', Icons.apartment_rounded),
                              
                              // Hint: أُلغيت التفاصيل المالية من الوارد بقرار المالك (2026-07-25)
                              //       وأُزيل مصدر «وارد» من التقرير المالي. البيانات القديمة باقية
                              //       في القاعدة (لا migration حذف) فالقرار قابل للتراجع.

                              // ━━━ الارتباط بالصادر ━━━
                              const Divider(height: 32),
                              const Text('الارتباط بالصادر',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 16),
                              if (d.replyOutgoingId != null) ...[
                                _buildInfoRow('تم الرد بكتاب صادر رقم',
                                    d.replyOutgoingNumber ?? '#${d.replyOutgoingId}', Icons.link_rounded),
                                if (canManageLink) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                      onPressed: _busy ? null : () => _unlinkFromOutgoing(d),
                                      icon: const Icon(Icons.link_off_rounded, size: 18),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                      label: const Text('فك الارتباط'),
                                    ),
                                  ),
                                ],
                              ] else ...[
                                Text('لم يُربط هذا الكتاب بكتاب صادر بعد.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withValues(alpha: 0.6))),
                                if (canManageLink) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    // Hint: الربط متاح للكتب (جديد/قيد المراجعة) فقط — مرآة لقاعدة الباك-إند.
                                    child: Tooltip(
                                      message: _isOperable(d.status)
                                          ? 'اختيار كتاب صادر معتمد للرد على هذا الوارد'
                                          : 'الربط متاح للكتب (جديد) أو (قيد المراجعة) فقط',
                                      child: OutlinedButton.icon(
                                        onPressed: (_busy || !_isOperable(d.status)) ? null : _linkToOutgoing,
                                        icon: const Icon(Icons.add_link_rounded, size: 18),
                                        label: const Text('ربط بكتاب صادر'),
                                      ),
                                    ),
                                  ),
                                ],
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
                            _AttachmentsWidget(incomingId: widget.id, canEdit: canEditAttachments),
                            
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
}

// ----------------- ويدجت المرفقات -----------------
/// Hint: [canEdit] = false للقارئ — يرى المرفقات وينزّلها بلا رفع أو حذف.
class _AttachmentsWidget extends ConsumerStatefulWidget {
  final int incomingId;
  final bool canEdit;
  const _AttachmentsWidget({required this.incomingId, required this.canEdit});

  @override
  ConsumerState<_AttachmentsWidget> createState() => _AttachmentsWidgetState();
}

class _AttachmentsWidgetState extends ConsumerState<_AttachmentsWidget> {
  bool _busy = false;

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Hint: قائمة الامتدادات مطابقة لـ AttachmentService في الباك-إند.
  Future<void> _upload() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx', 'zip', 'dwg'],
      withData: true,
    );
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).uploadIncomingAttachment(widget.incomingId, f.bytes!, f.name);
      _snack('تم رفع المرفق بنجاح.');
      ref.invalidate(incomingAttachmentsProvider(widget.incomingId));
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AttachmentModel a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف المرفق'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('سيُحذف الملف «${a.fileName}» نهائياً. هل تريد المتابعة؟'),
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

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).deleteIncomingAttachment(widget.incomingId, a.attachmentId);
      _snack('تم حذف المرفق.');
      ref.invalidate(incomingAttachmentsProvider(widget.incomingId));
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(AttachmentModel a) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).downloadIncomingAttachment(widget.incomingId, a.attachmentId);
      await downloadBytes(bytes, a.fileName, 'application/octet-stream');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// عرض المرفق داخل التطبيق بدل تنزيله — معظم مرفقات الوارد صور ممسوحة.
  Future<void> _view(AttachmentModel a) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).downloadIncomingAttachment(widget.incomingId, a.attachmentId);
      if (!mounted) return;
      await AttachmentViewer.show(
        context,
        bytes: bytes,
        fileName: a.fileName,
        onDownload: () => downloadBytes(bytes, a.fileName, 'application/octet-stream'),
      );
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      // Hint: فشل **العرض** ليس فشل شبكة. بلا هذا الفرع كان أي خطأ في رسم الملف يظهر
      // برسالة «تعذّر الوصول إلى الخادم» فيوجّه التشخيص إلى الاتصال بدل الملف نفسه.
      _snack('تعذّر عرض هذا الملف داخل البرنامج — جرّب تنزيله.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// أيقونة حسب نوع الملف (Hint: تسهّل التمييز البصري بين المسح الضوئي والمخططات والجداول).
  IconData _iconFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'jpg' || 'jpeg' || 'png' => Icons.image_rounded,
      'xlsx' => Icons.table_chart_rounded,
      'docx' => Icons.description_rounded,
      'zip' => Icons.folder_zip_rounded,
      'dwg' => Icons.architecture_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final asyncAtt = ref.watch(incomingAttachmentsProvider(widget.incomingId));

    return CustomCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attachment_rounded,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              const Text('المرفقات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (_busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else if (widget.canEdit)
                TextButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('رفع مرفق'),
                ),
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
                children: list
                    .map((a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_iconFor(a.fileName), color: AppColors.gold),
                          title: Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${(a.fileSize / 1024 / 1024).toStringAsFixed(2)} م.ب'),
                          // النقر على السطر يفتح العارض مباشرةً — أسرع مسار للمسح الضوئي.
                          onTap: _busy || !AttachmentViewer.canView(a.fileName)
                              ? null
                              : () => _view(a),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (AttachmentViewer.canView(a.fileName))
                                IconButton(
                                  tooltip: 'عرض',
                                  icon: const Icon(Icons.visibility_rounded),
                                  onPressed: _busy ? null : () => _view(a),
                                ),
                              IconButton(
                                tooltip: 'تنزيل',
                                icon: const Icon(Icons.download_rounded),
                                onPressed: _busy ? null : () => _download(a),
                              ),
                              if (widget.canEdit)
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                  onPressed: _busy ? null : () => _delete(a),
                                ),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ----------------- مسار الإحالات السابقة (داخل حوار الإحالة) -----------------

/// يعرض أين مرّ الكتاب سابقاً وملاحظة كل إحالة.
///
/// Hint: كانت الإحالة «عمياء» — تختار الوجهة بلا معرفة أين مرّ الكتاب ولا ما طُلب فيه
/// سابقاً. المعلومة كانت مسجَّلة في `MovementLog` منذ البداية لكنها لم تُعرض هنا قط.
class _ForwardHistory extends StatelessWidget {
  final List<MovementLogItem> history;
  const _ForwardHistory({required this.history});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.route_rounded, size: 18),
            const SizedBox(width: 6),
            Text('مسار الكتاب (${history.length} إحالة)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          ...history.asMap().entries.map((e) {
            final m = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.key + 1}. ${m.fromDepartment ?? 'غير محدد'} ← ${m.toDepartment ?? 'غير محدد'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Text('${m.performedByUserName} · ${fmt.format(m.performedAt)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  // الوصف يحمل نصّ الملاحظة إن كُتبت عند الإحالة.
                  if (m.description.contains('ملاحظة:'))
                    Text(m.description.substring(m.description.indexOf('ملاحظة:')),
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ),
            );
          }),
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

// ----------------- شاشة اختيار الكتاب الصادر للربط -----------------
/// شاشة كاملة لاختيار كتاب صادر معتمد للرد على الوارد.
/// Hint: شاشة كاملة لا حوار — حقول البحث داخل الحوارات تسبب خلل
/// `disposed EngineFlutterView` في Flutter Web. تُرجع `outgoingId` عبر Navigator.pop.
class _OutgoingPickerScreen extends ConsumerStatefulWidget {
  const _OutgoingPickerScreen();

  @override
  ConsumerState<_OutgoingPickerScreen> createState() => _OutgoingPickerScreenState();
}

class _OutgoingPickerScreenState extends ConsumerState<_OutgoingPickerScreen> {
  late Future<List<OutgoingListItem>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Hint: الباك-إند يقبل الربط بالمعتمد فقط (Final) — نطلبه مفلتراً من المصدر.
  void _load() {
    _future = ref.read(apiClientProvider).outgoingList(status: 'Final', search: _search);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار كتاب صادر للربط'), centerTitle: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'ابحث برقم الكتاب أو الموضوع...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (v) {
                    _search = v.trim();
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Text('تُعرض الكتب الصادرة المعتمدة فقط.',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<List<OutgoingListItem>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('حدث خطأ: ${snap.error}',
                                style: const TextStyle(color: AppColors.danger)));
                      }
                      final items = snap.data ?? const <OutgoingListItem>[];
                      if (items.isEmpty) {
                        return const Center(
                            child: Text('لا توجد كتب صادرة معتمدة مطابقة.',
                                style: TextStyle(fontWeight: FontWeight.bold)));
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                        itemBuilder: (_, i) {
                          final o = items[i];
                          return ListTile(
                            leading: const Icon(Icons.send_rounded, color: AppColors.gold),
                            title: Text(o.number ?? 'بلا رقم',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${o.subject}\n${DateFormat('yyyy/MM/dd').format(o.date)} • ${o.entityName}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            isThreeLine: true,
                            trailing: FilledButton(
                              onPressed: () => Navigator.pop(context, o.outgoingId),
                              child: const Text('اختيار'),
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
        ),
      ),
    );
  }
}
