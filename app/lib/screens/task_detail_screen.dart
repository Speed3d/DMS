import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../core/task_providers.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/attachment_viewer.dart';
import '../widgets/custom_card.dart';
import '../widgets/task_badges.dart';
import 'task_form_screen.dart';

/// تفاصيل المهمة (ADR-037) — ترويسةٌ ثابتة وأربعة تبويبات.
///
/// ⚠️ **نفسُ شكل ملفّ الموظف والبروفايل** (الدفعة د): ترويسةٌ + تبويبات، ولكل تبويبٍ
/// تمريرُه. فلا يتعلّم المستخدم واجهتين لشيءٍ واحد.
class TaskDetailScreen extends ConsumerStatefulWidget {
  final int taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) invalidateTasks(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskAsync = ref.watch(taskDetailProvider(widget.taskId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المهمة'),
        actions: [
          taskAsync.maybeWhen(
            data: (t) => t.canEdit
                ? Row(
                    children: [
                      IconButton(
                        tooltip: 'تعديل',
                        onPressed: _busy
                            ? null
                            : () async {
                                final saved = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => TaskFormScreen(existing: t)),
                                );
                                if (saved == true && mounted) invalidateTasks(ref);
                              },
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: _busy ? null : () => _confirmDelete(t),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger)),
          ),
        ),
        data: (t) => DefaultTabController(
          length: 3,
          child: Column(
            children: [
              _header(t),
              const TabBar(tabs: [
                Tab(text: 'التفاصيل'),
                Tab(text: 'السجلّ'),
                Tab(text: 'المرفقات'),
              ]),
              // ⚠️ **لكل تبويبٍ تمريرُه** (درس الدفعة د): تمريرةٌ واحدة لكل المحتوى تجعل
              //    المستخدم يمرّ بالسجلّ ليبلغ المرفقات.
              Expanded(
                child: TabBarView(children: [
                  _detailsTab(t),
                  _logTab(t),
                  _attachmentsTab(t),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────── الترويسة ───────────────────

  Widget _header(TaskModel t) => CustomCard(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TaskStatusPill(status: t.status, label: t.statusLabel),
                TaskPriorityBadge(priority: t.priority, label: t.priorityLabel),
                TaskDueLabel(
                  isOverdue: t.isOverdue,
                  daysOverdue: t.daysOverdue,
                  daysRemaining: t.daysRemaining,
                ),
                if (t.taskNumber != null)
                  Text(t.taskNumber!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color)),
              ],
            ),
            const SizedBox(height: 14),
            _progressBar(t),
          ],
        ),
      );

  Widget _progressBar(TaskModel t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = TaskStatusPill.colorFor(t.status, isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('نسبة الإنجاز',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${t.progressPercent}%',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: t.progressPercent / 100,
            minHeight: 8,
            backgroundColor: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        if (t.isActive) ...[
          const SizedBox(height: 8),
          // 🔴 **الأزرار تُبنى من `nextStatuses` الآتية من الخادم** — لا من قائمةٍ مكتوبة
          //    هنا. مصفوفة الانتقالات تعيش في `TaskWorkflow`، ونسخةٌ في الواجهة تتباعد
          //    عند أول تعديل فتعرض زرّاً يردّ 400.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...[25, 50, 75, 100].map((p) => OutlinedButton(
                    onPressed: _busy || t.progressPercent == p
                        ? null
                        : () => _run(() => ref
                            .read(apiClientProvider)
                            .updateTaskProgress(t.taskId, p)),
                    child: Text('$p%'),
                  )),
            ],
          ),
        ],
      ],
    );
  }

  // ─────────────────── التفاصيل ───────────────────

  Widget _detailsTab(TaskModel t) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (t.isActive || t.isCompleted) _actionsCard(t),
          if (t.description != null && t.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الوصف',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(t.description!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          CustomCard(
            child: Column(
              children: [
                _row('النوع', t.taskTypeLabel),
                if (t.departmentName != null) _row('القسم', t.departmentName!),
                _row('المسؤول', t.assignedToUserName ?? 'غير مُسنَدة'),
                _row('أنشأها', t.createdByUserName),
                _row('موعد التسليم', _fmtDay(t.dueDate)),
                if (t.startDate != null) _row('تاريخ البدء', _fmtDay(t.startDate!)),
                if (t.completedDate != null)
                  _row('تاريخ الإكمال', _fmtDay(t.completedDate!)),
                if (t.relatedIncomingNumber != null)
                  _row('كتاب وارد مرتبط', t.relatedIncomingNumber!),
                if (t.relatedOutgoingNumber != null)
                  _row('كتاب صادر مرتبط', t.relatedOutgoingNumber!),
                if (t.isRecurring)
                  _row(
                      'التكرار',
                      'كل ${t.recurrenceInterval ?? 1} '
                          '${kRecurrenceLabels[t.recurrencePattern] ?? ''}'
                          '${t.recurrenceEndDate != null ? ' — حتى ${_fmtDay(t.recurrenceEndDate!)}' : ''}'),
                if (t.parentRecurringTaskId != null)
                  _row('نسخةٌ من مهمة متكررة', '#${t.parentRecurringTaskId}'),
                if (t.notes != null && t.notes!.isNotEmpty) _row('ملاحظات', t.notes!),
                // **لحظة** لا يوم — تُعرض بتوقيت الجهاز بـ`toLocal()` (درس ADR-032).
                _row('أُنشئت', _fmtInstant(t.createdAt)),
              ],
            ),
          ),
        ],
      );

  Widget _actionsCard(TaskModel t) {
    final session = ref.watch(sessionProvider);
    final canReopen = const ['SuperAdmin', 'President', 'Manager']
        .contains(session.auth?.role);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الإجراءات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // الانتقالات المسموحة — من الخادم.
              ...t.nextStatuses
                  .where((s) => s != 'Reopened')
                  .map((s) => ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => ref
                                .read(apiClientProvider)
                                .changeTaskStatus(t.taskId, s)),
                        child: Text(kTaskStatusLabels[s] ?? s),
                      )),

              // 🔐 **إعادة الفتح للمدير فأعلى وبسببٍ إلزامي** — والزرّ يغيب لغيره فلا
              //    يُقاد المستخدم إلى نقطةٍ تردّ 403.
              if (t.nextStatuses.contains('Reopened') && canReopen)
                ElevatedButton.icon(
                  onPressed: _busy ? null : () => _promptReopen(t),
                  icon: const Icon(Icons.lock_reset_rounded, size: 16),
                  label: const Text('إعادة الفتح'),
                ),

              if (session.canManageTasks && t.isActive)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _promptReassign(t),
                  icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                  label: const Text('إعادة الإسناد'),
                ),

              OutlinedButton.icon(
                onPressed: _busy ? null : () => _promptComment(t),
                icon: const Icon(Icons.comment_outlined, size: 16),
                label: const Text('تعليق'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────── السجلّ ───────────────────

  Widget _logTab(TaskModel t) {
    final updatesAsync = ref.watch(taskUpdatesProvider(t.taskId));

    return updatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) => rows.isEmpty
          ? const Center(child: Text('لا قيود بعد'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final u = rows[i];
                return CustomCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.description, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color),
                          const SizedBox(width: 3),
                          // ⚠️ **الاسم يُعرض ولو كان «—»** — ولا يُخفى السطر: قيدٌ بلا اسمٍ
                          //    أهون من قيدٍ محذوف (ADR-034).
                          Text(u.updatedByUserName,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).textTheme.bodySmall?.color)),
                          const Spacer(),
                          Text(_fmtInstant(u.updatedAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).textTheme.bodySmall?.color)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ─────────────────── المرفقات ───────────────────

  Widget _attachmentsTab(TaskModel t) {
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(t.taskId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _busy ? null : () => _uploadAttachment(t),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('رفع مرفق'),
              ),
            ],
          ),
        ),
        Expanded(
          child: attachmentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? const Center(child: Text('لا مرفقات'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(a.fileName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${(a.fileSize / 1024).toStringAsFixed(0)} ك.ب'),
                          trailing: AttachmentViewer.canView(a.fileName)
                              ? IconButton(
                                  tooltip: 'عرض',
                                  icon: const Icon(Icons.visibility_rounded),
                                  onPressed: () => _viewAttachment(t, a),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _uploadAttachment(TaskModel t) async {
    final picked = await FilePicker.pickFiles(withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    await _run(() => ref
        .read(apiClientProvider)
        .uploadTaskAttachment(t.taskId, file.name, file.bytes!));
  }

  Future<void> _viewAttachment(TaskModel t, AttachmentModel a) async {
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .taskAttachmentBytes(t.taskId, a.attachmentId);
      if (!mounted) return;
      await AttachmentViewer.show(context,
          bytes: Uint8List.fromList(bytes), fileName: a.fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ─────────────────── حواريّات ───────────────────

  Future<void> _promptReopen(TaskModel t) async {
    final reason = await _promptText(
      title: 'إعادة فتح المهمة',
      hint: 'سبب إعادة الفتح (٥ أحرف فأكثر)',
      // 🔴 **السبب إلزاميّ في الواجهة كما في الخادم**: إعادةُ الفتح تنقض إنجازاً مُعلَناً،
      //    وسجلُّها بلا تعليل لا يُفهم بعد أشهر (سابقة فكّ الأرشفة — ADR-021).
      validator: (v) => v.trim().length < 5 ? 'السبب مطلوب (٥ أحرف فأكثر)' : null,
    );
    if (reason == null) return;
    await _run(() => ref.read(apiClientProvider).reopenTask(t.taskId, reason));
  }

  Future<void> _promptComment(TaskModel t) async {
    final text = await _promptText(
      title: 'إضافة تعليق',
      hint: 'نصّ التعليق',
      validator: (v) => v.trim().isEmpty ? 'التعليق مطلوب' : null,
    );
    if (text == null) return;
    await _run(() => ref.read(apiClientProvider).addTaskComment(t.taskId, text));
  }

  Future<void> _promptReassign(TaskModel t) async {
    final users = await ref.read(assignableUsersProvider.future);
    if (!mounted || users.isEmpty) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('إعادة إسناد المهمة'),
        children: users
            .map((u) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(u.userId),
                  child: Text(u.fullName),
                ))
            .toList(),
      ),
    );
    if (picked == null) return;
    await _run(() => ref.read(apiClientProvider).reassignTask(t.taskId, picked));
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    required String? Function(String) validator,
  }) async {
    final controller = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
                hintText: hint, errorText: error, border: const OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final err = validator(controller.text);
                if (err != null) {
                  setLocal(() => error = err);
                  return;
                }
                Navigator.of(ctx).pop(controller.text.trim());
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _confirmDelete(TaskModel t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المهمة'),
        content: Text('هل تحذف «${t.title}»؟ الحذف ناعمٌ ويبقى سجلُّها.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _run(() async {
      await ref.read(apiClientProvider).deleteTask(t.taskId);
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ─────────────────── مساعدات ───────────────────

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  /// **يومٌ** — بلا `toLocal()`: تحويلُ يومٍ بالمنطقة الزمنية يُنقصه يوماً (درس G18).
  static String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// **لحظة** — تُحوَّل بـ`toLocal()` عن حقّ (درس ADR-032).
  static String _fmtInstant(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}'
        ' ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
