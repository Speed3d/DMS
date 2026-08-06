import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/attachment_viewer.dart';
import '../widgets/custom_card.dart';
import 'employee_form_screen.dart';

/// Hint: ملفّ الموظف — ترويسة بالصورة والحالة، ثم تبويبا المعلومات وسجلّ الرواتب.
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  final int employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  EmployeeDetail? _employee;
  List<SalaryHistoryItem> _history = const [];
  List<LeaveModel> _leaves = const [];
  List<EmployeeLogItem> _log = const [];
  List<AttachmentModel> _docs = const [];
  Uint8List? _photo;
  bool _loading = true;
  bool _docsBusy = false;
  String? _error;

  /// هل تغيّر شيء يستوجب إعادة تحميل القائمة عند الرجوع؟
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final e = await api.employee(widget.employeeId);
      final h = await api.salaryHistory(widget.employeeId);
      final lv = await api.leaves(widget.employeeId);
      final lg = await api.employeeLog(widget.employeeId);
      // المستمسكات مساعِدةٌ لا حاسمة — فشلُ جلبها لا يُسقط الملفّ كلّه.
      List<AttachmentModel> docs = const [];
      try {
        docs = await api.employeeAttachments(widget.employeeId);
      } catch (_) {}
      Uint8List? photo;
      if (e.hasPhoto) {
        try {
          photo = await api.employeePhoto(widget.employeeId);
        } catch (_) {
          // غياب الصورة لا يمنع عرض الملفّ.
        }
      }
      if (!mounted) return;
      setState(() {
        _employee = e;
        _history = h;
        _leaves = lv;
        _log = lg;
        _docs = docs;
        _photo = photo;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ─────────────────────── المستمسكات ───────────────────────

  Future<void> _reloadDocs() async {
    try {
      final docs = await ref.read(apiClientProvider).employeeAttachments(widget.employeeId);
      if (mounted) setState(() => _docs = docs);
    } catch (_) {}
  }

  Future<void> _addDoc() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(withData: true, allowMultiple: true);
    if (res == null) return;

    setState(() => _docsBusy = true);
    var failed = 0;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      try {
        await ref
            .read(apiClientProvider)
            .uploadEmployeeAttachment(widget.employeeId, f.name, f.bytes!);
      } catch (_) {
        failed++;
      }
    }
    await _reloadDocs();
    if (!mounted) return;
    setState(() => _docsBusy = false);
    // ⚠️ يُعلَن الفشل الجزئي صراحةً: رفعُ ٣ من ٥ بصمتٍ يجعل المستخدم يظنّ الخمسة رُفعت.
    if (failed > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text('تعذّر رفع $failed من ${res.files.length} ملفاً'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _viewDoc(AttachmentModel a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .employeeAttachmentBytes(widget.employeeId, a.attachmentId);
      if (!mounted) return;
      await AttachmentViewer.show(context, bytes: bytes, fileName: a.fileName);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذّر العرض: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _downloadDoc(AttachmentModel a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // inline حتى هنا: نجلب البايتات ونحفظها بأنفسنا، فترويسة «تنزيل» من الخادم
      // ضررُها فقط — يختطف مديرُ التحميل الطلب فلا يصل ردّ (مبدأ ADR-019).
      final bytes = await ref
          .read(apiClientProvider)
          .employeeAttachmentBytes(widget.employeeId, a.attachmentId);
      await downloadBytes(bytes, a.fileName, 'application/octet-stream');
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذّر التنزيل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteDoc(AttachmentModel a) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المستمسك'),
        content: Text('حذف «${a.fileName}»؟ لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(apiClientProvider).deleteAttachment(a.attachmentId);
      await _reloadDocs();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذّر الحذف: $e'), backgroundColor: Colors.red));
    }
  }

  /// يرفع إيصال الاستلام **بعد توقيع الموظف** (بلاغ المالك ٦).
  Future<void> _uploadSignedReceipt(SalaryHistoryItem h) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;

    try {
      await ref
          .read(apiClientProvider)
          .uploadSignedReceipt(h.entryId, f.name, f.bytes!);
      final fresh = await ref.read(apiClientProvider).salaryHistory(widget.employeeId);
      if (!mounted) return;
      setState(() => _history = fresh);
      messenger.showSnackBar(
          SnackBar(content: Text('رُفع إيصال ${h.monthName} ${h.year} الموقَّع.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذّر الرفع: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employeeId: widget.employeeId)),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _terminate() async {
    final result = await showDialog<_TerminationResult>(
      context: context,
      builder: (_) => _TerminateDialog(hireDate: _employee?.employment?.hireDate),
    );
    if (result == null) return;
    try {
      await ref.read(apiClientProvider).terminateEmployee(
          widget.employeeId, result.date, result.reason, result.notes);
      _changed = true;
      await _load();
      if (mounted) _snack('سُجّل إنهاء الخدمة.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  Future<void> _addLeave() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _LeaveDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(apiClientProvider).addLeave(widget.employeeId, result);
      _changed = true;
      await _load();
      if (mounted) _snack('سُجّلت الإجازة.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  Future<void> _reviewLeave(LeaveModel leave, bool approve) async {
    try {
      await ref.read(apiClientProvider).reviewLeave(leave.leaveId, approve, null);
      _changed = true;
      await _load();
      if (mounted) _snack(approve ? 'قُبلت الإجازة.' : 'رُفضت الإجازة.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  Future<void> _deleteLeave(LeaveModel leave) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الإجازة'),
        content: Text('حذف إجازة ${leave.leaveTypeLabel} '
            '(${DateFormat('yyyy-MM-dd').format(leave.fromDate)})؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteLeave(leave.leaveId);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  Future<void> _printReceipt(SalaryHistoryItem item) async {
    try {
      final bytes = await ref.read(apiClientProvider).payrollFile(
          item.year, item.month, 'receipts', employeeId: widget.employeeId);
      await downloadBytes(
          bytes, 'receipt-${item.year}-${item.month.toString().padLeft(2, '0')}.pdf',
          'application/pdf');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(sessionProvider).canManageEmployees;
    final e = _employee;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ملفّ الموظف'),
          actions: [
            if (canManage && e != null) ...[
              IconButton(
                onPressed: _edit,
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'تعديل',
              ),
              if (e.employment?.terminationDate == null)
                IconButton(
                  onPressed: _terminate,
                  icon: const Icon(Icons.person_off_rounded),
                  tooltip: 'إنهاء الخدمة',
                ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                : ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      _Header(employee: e!, photo: _photo),
                      const SizedBox(height: 20),
                      _InfoCard(employee: e),
                      const SizedBox(height: 20),
                      _DocumentsCard(
                        items: _docs,
                        canManage: canManage,
                        busy: _docsBusy,
                        onAdd: _addDoc,
                        onView: _viewDoc,
                        onDownload: _downloadDoc,
                        onDelete: _deleteDoc,
                      ),
                      const SizedBox(height: 20),
                      _LeavesCard(
                        leaves: _leaves,
                        canManage: canManage,
                        onAdd: _addLeave,
                        onReview: _reviewLeave,
                        onDelete: _deleteLeave,
                      ),
                      const SizedBox(height: 20),
                      _SalaryHistoryCard(
                        items: _history,
                        onPrint: _printReceipt,
                        onUploadReceipt: _uploadSignedReceipt,
                        // ⚠️ **صلاحية الرواتب لا الموظفين**: الإيصال وثيقةُ صرفٍ ماليّ.
                        canManage: ref.watch(sessionProvider).canManagePayroll,
                      ),
                      const SizedBox(height: 20),
                      _ChangeLogCard(items: _log),
                    ],
                  ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final EmployeeDetail employee;
  final Uint8List? photo;
  const _Header({required this.employee, this.photo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final job = employee.employment;
    final terminated = job?.terminationDate != null;

    return CustomCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.navy.withValues(alpha: 0.12),
            backgroundImage: photo != null ? MemoryImage(photo!) : null,
            child: photo == null
                ? Text(
                    employee.fullName.trim().isNotEmpty
                        ? employee.fullName.trim().characters.first
                        : '؟',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.navy))
                : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                if (employee.fullNameEn != null && employee.fullNameEn!.isNotEmpty)
                  Text(employee.fullNameEn!,
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Text(job?.position ?? '—',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _Chip(
                    icon: Icons.event_available_rounded,
                    label: job != null
                        ? 'التعيين ${DateFormat('yyyy-MM-dd').format(job.hireDate)}'
                        : '—',
                  ),
                  if (job != null)
                    _Chip(
                      icon: Icons.payments_rounded,
                      label:
                          '${NumberFormat('#,##0.##').format(job.baseSalary)} ${job.salaryCurrency == 'USD' ? '\$' : 'د.ع'}',
                    ),
                  _Chip(
                    icon: terminated ? Icons.person_off_rounded : Icons.verified_user_rounded,
                    label: terminated
                        ? 'منتهي الخدمة ${DateFormat('yyyy-MM-dd').format(job!.terminationDate!)}'
                        : 'على رأس العمل',
                    color: terminated
                        ? (isDark ? AppColors.dangerDark : AppColors.danger)
                        : (isDark ? AppColors.successDark : AppColors.success),
                  ),
                ]),

                // ── «يعمل أيضاً في» (ADR-027) ──
                //
                // ⚠️ **هذا السطر هو ما يجعل الإسناد الثاني مرئياً.** بدونه يقع الربط صامتاً:
                //    يُسنِده المحاسب ثم لا يرى في البطاقة أثراً له، فيظنّه لم يقع فيُعيده.
                // ⚠️ **وأسماءُ شركاتٍ لا شروطُ عملٍ فيها** — الراتب والصفة هناك يحجبهما
                //    الفلتر العام عمداً (ADR-017)، والمعروض واقعةُ العمل وحدها.
                if (employee.otherCompanies.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('يعمل أيضاً في:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.6))),
                      ...employee.otherCompanies.map((c) => _Chip(
                            icon: Icons.apartment_rounded,
                            label: c.name,
                            color: isDark ? AppColors.goldBright : AppColors.navy,
                          )),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? theme.dividerColor).withValues(alpha: color != null ? 0.13 : 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      // ⚠️ `Flexible` + قصٌّ بثلاث نقاط: البطاقة تعرض الآن **أسماء شركات** (ADR-027)، واسمٌ
      //    طويل كـ«شركة أرض العرين للتجارة والمقاولات العامة المحدودة» يجعل الرقاقة أعرض من
      //    حاويتها فتفيض. و`Wrap` يحمي من تعدّد الرقاقات لا من رقاقةٍ واحدة أعرض من السطر.
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final EmployeeDetail employee;
  const _InfoCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final job = employee.employment;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.info_outline_rounded, title: 'المعلومات'),
          _Row(label: 'رقم الهوية', value: employee.nationalId),
          _Row(label: 'الهاتف', value: employee.phone),
          _Row(label: 'العنوان', value: employee.address),
          _Row(
              label: 'لغة الإيصال',
              value: employee.receiptLanguage == 'English' ? 'الإنجليزية' : 'العربية'),
          if (job != null) ...[
            _Row(label: 'الصفة بالإنجليزية', value: job.positionEn),
            _Row(label: 'الترتيب في الكشف', value: '${job.displayOrder}'),
            if (job.terminationReason != null)
              _Row(label: 'سبب إنهاء الخدمة', value: _reasonLabel(job.terminationReason!)),
            if (job.terminationNotes != null)
              _Row(label: 'ملاحظات الإنهاء', value: job.terminationNotes),
          ],
          _Row(label: 'ملاحظات', value: employee.notes),
        ],
      ),
    );
  }

  static String _reasonLabel(String r) => switch (r) {
        'Resignation' => 'استقالة',
        'Termination' => 'فصل',
        'Retirement' => 'تقاعد',
        'Death' => 'وفاة',
        _ => 'أخرى',
      };
}

class _SalaryHistoryCard extends StatelessWidget {
  final List<SalaryHistoryItem> items;
  final ValueChanged<SalaryHistoryItem> onPrint;
  final ValueChanged<SalaryHistoryItem> onUploadReceipt;
  final bool canManage;
  const _SalaryHistoryCard({
    required this.items, required this.onPrint,
    required this.onUploadReceipt, required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0.##');

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.receipt_long_rounded, title: 'سجلّ الرواتب'),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('لا توجد رواتب مسجَّلة بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            )
          else
            ...items.map((h) {
              final paid = h.periodStatus == 'Paid';
              final color = paid
                  ? (theme.brightness == Brightness.dark
                      ? AppColors.successDark
                      : AppColors.success)
                  : (theme.brightness == Brightness.dark ? AppColors.warnDark : AppColors.warn);
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text('${h.monthName} ${h.year}',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(
                        '${money.format(h.netSalary)} ${h.currency == 'USD' ? '\$' : 'د.ع'}'
                        '${h.currency == 'USD' ? '  (${money.format(h.netSalaryIqd)} د.ع)' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(paid ? 'مُسدَّد' : 'مسودة',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
                    ),
                    IconButton(
                      // الإيصال يُطبع للمُسدَّد وللمسودّة معاً — المحاسب قد يطبعه قبل الصرف.
                      onPressed: () => onPrint(h),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      tooltip: 'طباعة إيصال الاستلام',
                    ),
                    // ── رفع الإيصال **بعد توقيع الموظف** (بلاغ المالك ٦) ──
                    // ⚠️ **للمُسدَّد وحده**: التوقيع يقع بعد الاستلام، ورفعُ «إيصال موقَّع»
                    //    على مسودّةٍ لم تُصرف بعدُ يوثّق ما لم يحدث.
                    if (paid && canManage)
                      IconButton(
                        onPressed: () => onUploadReceipt(h),
                        icon: Icon(
                            h.signedReceiptCount > 0
                                ? Icons.assignment_turned_in_rounded
                                : Icons.upload_file_rounded,
                            size: 18,
                            color: h.signedReceiptCount > 0
                                ? (theme.brightness == Brightness.dark
                                    ? AppColors.successDark
                                    : AppColors.success)
                                : null),
                        tooltip: h.signedReceiptCount > 0
                            ? 'الإيصال الموقَّع مرفوع (${h.signedReceiptCount}) — إضافة نسخة'
                            : 'رفع الإيصال بعد توقيعه',
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// مستمسكات الموظف (هوية · عقد · شهادات).
///
/// ⚠️ الباك-إند كان جاهزاً منذ الدفعة ١ — `OwnerType.Employee` وحارسُ صلاحيةٍ مكتوب —
/// **ولم يكن له مدخلٌ في الواجهة قطّ**، فماتت الميزة صامتةً حتى بلّغ عنها المالك.
class _DocumentsCard extends StatelessWidget {
  final List<AttachmentModel> items;
  final bool canManage;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<AttachmentModel> onView;
  final ValueChanged<AttachmentModel> onDownload;
  final ValueChanged<AttachmentModel> onDelete;

  const _DocumentsCard({
    required this.items, required this.canManage, required this.busy,
    required this.onAdd, required this.onView,
    required this.onDownload, required this.onDelete,
  });

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} م.ب';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
    return '$bytes بايت';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('yyyy-MM-dd');

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
                child: _CardTitle(icon: Icons.folder_copy_outlined, title: 'المستمسكات')),
            if (canManage)
              TextButton.icon(
                onPressed: busy ? null : onAdd,
                icon: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_rounded, size: 17),
                label: Text(busy ? 'جارٍ الرفع...' : 'رفع مستمسك'),
              ),
          ]),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                  canManage
                      ? 'لا مستمسكات — ارفع الهوية أو العقد أو الشهادات.'
                      : 'لا مستمسكات مرفوعة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            )
          else
            ...items.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    Icon(
                        AttachmentViewer.canView(a.fileName)
                            ? Icons.description_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 18,
                        color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text('${_size(a.fileSize)} · ${date.format(a.uploadedAt)}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                    // زرّ العرض يظهر لما يُعرض داخلياً فقط — وعده بالعرض ثم تنزيلُه خُلفٌ.
                    if (AttachmentViewer.canView(a.fileName))
                      IconButton(
                        onPressed: () => onView(a),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        tooltip: 'عرض',
                      ),
                    IconButton(
                      onPressed: () => onDownload(a),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      tooltip: 'تنزيل',
                    ),
                    if (canManage)
                      IconButton(
                        onPressed: () => onDelete(a),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.danger),
                        tooltip: 'حذف',
                      ),
                  ]),
                )),
        ],
      ),
    );
  }
}

class _LeavesCard extends StatelessWidget {
  final List<LeaveModel> leaves;
  final bool canManage;
  final VoidCallback onAdd;
  final void Function(LeaveModel, bool) onReview;
  final ValueChanged<LeaveModel> onDelete;

  const _LeavesCard({
    required this.leaves, required this.canManage,
    required this.onAdd, required this.onReview, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final date = DateFormat('yyyy-MM-dd');

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
                child: _CardTitle(icon: Icons.beach_access_rounded, title: 'الإجازات')),
            if (canManage)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إجازة جديدة'),
              ),
          ]),
          if (leaves.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('لا توجد إجازات مسجَّلة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            )
          else
            ...leaves.map((l) {
              final color = l.isPending
                  ? (isDark ? AppColors.warnDark : AppColors.warn)
                  : l.isRejected
                      ? (isDark ? AppColors.dangerDark : AppColors.danger)
                      : (isDark ? AppColors.successDark : AppColors.success);
              final label = l.isPending ? 'بانتظار الموافقة' : (l.isRejected ? 'مرفوضة' : 'مقبولة');

              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(l.leaveTypeLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(
                        '${date.format(l.fromDate)} → ${date.format(l.toDate)}  ·  ${l.durationDays} يوماً',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    if (l.deductFromSalary)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Text('تُحسم',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.dangerDark : AppColors.danger)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                    ),
                    if (canManage && l.isPending) ...[
                      IconButton(
                        onPressed: () => onReview(l, true),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        tooltip: 'موافقة',
                        color: isDark ? AppColors.successDark : AppColors.success,
                      ),
                      IconButton(
                        onPressed: () => onReview(l, false),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        tooltip: 'رفض',
                        color: isDark ? AppColors.dangerDark : AppColors.danger,
                      ),
                    ],
                    if (canManage)
                      IconButton(
                        onPressed: () => onDelete(l),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        tooltip: 'حذف',
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// سجلّ التغييرات — **قراءة فقط**: يُكتب ولا يُعدَّل ولا يُحذف.
class _ChangeLogCard extends StatelessWidget {
  final List<EmployeeLogItem> items;
  const _ChangeLogCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('yyyy-MM-dd HH:mm');

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.history_rounded, title: 'سجلّ التغييرات'),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('لا تغييرات مسجَّلة بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            )
          else
            ...items.map((l) => Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.gold, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // الوصف نصٌّ عربي جاهز من الخادم — لا يُركَّب هنا.
                            Text(l.description,
                                style: const TextStyle(fontSize: 13, height: 1.5)),
                            Text(date.format(l.changedAt),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

/// نافذة تسجيل إجازة.
class _LeaveDialog extends StatefulWidget {
  const _LeaveDialog();
  @override
  State<_LeaveDialog> createState() => _LeaveDialogState();
}

class _LeaveDialogState extends State<_LeaveDialog> {
  String _type = 'Annual';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _requiresApproval = false;
  bool _deduct = false;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  int get _days => _to.difference(_from).inDays + 1;
  bool get _invalid => _to.isBefore(_from);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إجازة جديدة'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'نوع الإجازة', isDense: true),
              items: kLeaveTypes.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 8),
            _DatePickRow(
              label: 'من',
              value: _from,
              onChanged: (d) => setState(() {
                _from = d;
                if (_to.isBefore(_from)) _to = _from;
              }),
            ),
            _DatePickRow(label: 'إلى', value: _to, onChanged: (d) => setState(() => _to = d)),
            if (!_invalid)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('المدّة: $_days يوماً',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _requiresApproval,
              title: const Text('تحتاج موافقة', style: TextStyle(fontSize: 13)),
              subtitle: const Text('بدونها تُسجَّل مقبولةً مباشرةً',
                  style: TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() => _requiresApproval = v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _deduct,
              activeThumbColor: AppColors.warn,
              title: const Text('تُحسم من الراتب', style: TextStyle(fontSize: 13)),
              subtitle: const Text('الحسم يُطبَّق يدوياً في كشف الشهر المعني',
                  style: TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() => _deduct = v),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true),
            ),
            if (_invalid)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('تاريخ النهاية لا يسبق البداية.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _invalid
              ? null
              : () => Navigator.pop(context, {
                    'leaveType': _type,
                    'fromDate': _from.toIso8601String(),
                    'toDate': _to.toIso8601String(),
                    'requiresApproval': _requiresApproval,
                    'deductFromSalary': _deduct,
                    'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  }),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _DatePickRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DatePickRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.calendar_today_rounded, size: 17),
        title: Text('$label: ${DateFormat('yyyy-MM-dd').format(value)}',
            style: const TextStyle(fontSize: 13.5)),
        trailing: TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) onChanged(d);
          },
          child: const Text('تغيير'),
        ),
      );
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ),
          Expanded(
            child: Text(
              (value == null || value!.trim().isEmpty) ? '—' : value!,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminationResult {
  final DateTime date;
  final String reason;
  final String? notes;
  _TerminationResult(this.date, this.reason, this.notes);
}

class _TerminateDialog extends StatefulWidget {
  final DateTime? hireDate;
  const _TerminateDialog({this.hireDate});
  @override
  State<_TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<_TerminateDialog> {
  DateTime _date = DateTime.now();
  String _reason = 'Resignation';
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invalid = widget.hireDate != null && _date.isBefore(widget.hireDate!);
    return AlertDialog(
      title: const Text('إنهاء الخدمة'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_rounded, size: 18),
              title: Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}',
                  style: const TextStyle(fontSize: 14)),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: widget.hireDate ?? DateTime(1970),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _date = d);
                },
                child: const Text('تغيير'),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'السبب', isDense: true),
              items: const [
                DropdownMenuItem(value: 'Resignation', child: Text('استقالة')),
                DropdownMenuItem(value: 'Termination', child: Text('فصل')),
                DropdownMenuItem(value: 'Retirement', child: Text('تقاعد')),
                DropdownMenuItem(value: 'Death', child: Text('وفاة')),
                DropdownMenuItem(value: 'Other', child: Text('أخرى')),
              ],
              onChanged: (v) => setState(() => _reason = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true),
            ),
            if (invalid)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('تاريخ الإنهاء لا يسبق تاريخ التعيين.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: invalid
              ? null
              : () => Navigator.pop(
                  context,
                  _TerminationResult(
                      _date, _reason, _notes.text.trim().isEmpty ? null : _notes.text.trim())),
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
