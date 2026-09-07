import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/incoming_providers.dart';
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
  final _commentController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

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
          length: 4,
          child: Column(
            children: [
              _header(t),
              // 🔴 **التعليقات تبويبٌ مستقلّ عن السجلّ** (بلاغ المالك: «أين تظهر
              //    التعليقات؟»). كانت تُحفَظ وتُعرض فعلاً — لكن **مختلطةً بتغييرات الحالة**
              //    في تبويب السجلّ، فمن يعلّق ثم ينظر في «التفاصيل» لا يرى شيئاً.
              //    **حوارٌ شيءٌ وأثرُ تدقيقٍ شيءٌ آخر، وخلطُهما يدفن الأول.**
              const TabBar(isScrollable: true, tabs: [
                Tab(text: 'التفاصيل'),
                Tab(text: 'التعليقات'),
                Tab(text: 'السجلّ'),
                Tab(text: 'المرفقات'),
              ]),
              // ⚠️ **لكل تبويبٍ تمريرُه** (درس الدفعة د): تمريرةٌ واحدة لكل المحتوى تجعل
              //    المستخدم يمرّ بالسجلّ ليبلغ المرفقات.
              Expanded(
                child: TabBarView(children: [
                  _detailsTab(t),
                  _commentsTab(t),
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
                    onPressed:
                        _busy || t.progressPercent == p ? null : () => _setProgress(t, p),
                    // 🔻 يُميَّز ما يُنقص النسبة — فيعرف الضاغط أنه سيُسأل عن السبب.
                    child: Text(p < t.progressPercent ? '🔻 $p%' : '$p%'),
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
          const SizedBox(height: 12),
          _participantsCard(t),
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

              // ⚠️ **حُذف زرّ «تعليق» من هنا**: صار للتعليقات تبويبٌ بصندوق كتابةٍ ظاهر،
              //    وزرٌّ يفتح حواريّةً لشيءٍ له مكانٌ واضح **يُشتّت ولا يُضيف**.
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

  /// يضبط النسبة — **ويسأل عن السبب إن كانت تتراجع** (قرار المالك).
  ///
  /// 🔴 **التقدّم لا يحتاج تعليلاً والتراجع يحتاجه**: من رفع النسبة إلى 75% أعلن إنجازاً،
  /// ومن أعادها إلى 25% **نقض إعلاناً سابقاً** — ومن يقرأ الرقم بعد أسبوع لا يعرف أخطأَ
  /// إدخالٍ كان أم عملاً انكشف نقصُه. والخادم يفرض القاعدة نفسها، وهذه **مرآتُها** فلا
  /// يُفاجأ المستخدم بـ400 بعد الضغط.
  Future<void> _setProgress(TaskModel t, int percent) async {
    String? reason;

    if (percent < t.progressPercent) {
      reason = await _promptText(
        title: 'تقليل نسبة الإنجاز من ${t.progressPercent}% إلى $percent%',
        hint: 'لماذا تراجعت النسبة؟ (٥ أحرف فأكثر)',
        validator: (v) => v.trim().length < 5 ? 'السبب مطلوب (٥ أحرف فأكثر)' : null,
      );
      if (reason == null) return;
    }

    await _run(() => ref
        .read(apiClientProvider)
        .updateTaskProgress(t.taskId, percent, reason: reason));
  }

  /// تبويب التعليقات — **حوارٌ لا أثرُ تدقيق**: الأقدم أعلى وصندوق الكتابة في أسفله.
  Widget _commentsTab(TaskModel t) {
    final updatesAsync = ref.watch(taskUpdatesProvider(t.taskId));
    final myId = ref.read(sessionProvider).auth?.userId;

    return Column(
      children: [
        Expanded(
          child: updatesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              // ⚠️ **التعليقات وحدها** لا تغييرات الحالة. والترتيب **الأقدم أعلى** عكس
              //    السجلّ: الحوار يُقرأ من أوّله، والأثر يُقرأ من آخره.
              final comments =
                  rows.where((u) => u.updateType == 'Comment').toList().reversed.toList();

              if (comments.isEmpty) return _noComments();

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: comments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _commentBubble(comments[i], comments[i].updatedByUserId == myId),
              );
            },
          ),
        ),
        // 🔴 **صندوق الكتابة في الشاشة نفسها لا خلف زرٍّ في تبويبٍ آخر** — وهذا جوهر
        //    البلاغ: الميزة كانت تعمل، ومكانها هو الخطأ.
        _commentComposer(t),
      ],
    );
  }

  Widget _noComments() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 48, color: Theme.of(context).dividerColor.withValues(alpha: 0.8)),
            const SizedBox(height: 10),
            const Text('لا تعليقات بعد'),
            const SizedBox(height: 4),
            Text('اكتب أوّل تعليق في الأسفل',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
          ],
        ),
      );

  Widget _commentBubble(TaskUpdateModel c, bool mine) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.comment ?? c.description, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Text(c.updatedByUserName,
                          style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                  Text(_fmtInstant(c.updatedAt),
                      style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _commentComposer(TaskModel t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب تعليقاً…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _sendComment(t),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'إرسال',
              onPressed: _busy ? null : () => _sendComment(t),
              icon: const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      );

  Future<void> _sendComment(TaskModel t) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    await _run(() async {
      await ref.read(apiClientProvider).addTaskComment(t.taskId, text);
      _commentController.clear();
    });
  }

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

  /// إعادة الإسناد — **وتسأل صراحةً عمّا يحلّ بالمسؤول السابق** (بلاغ المالك).
  ///
  /// 🔴 كان السابق **يفقد رؤية المهمة صامتاً** عند نقلها، ويبقى اسمُه في سجلّها لا يستطيع
  /// فتحه ليقرأ ما كتب. والافتراض الآن **الإبقاء**، والنزع قرارٌ يُتّخذ لا سلوكٌ ضمنيّ.
  Future<void> _promptReassign(TaskModel t) async {
    final users = await ref.read(assignableUsersProvider.future);
    if (!mounted || users.isEmpty) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('إعادة إسناد المهمة'),
        children: users
            .where((u) => u.userId != t.assignedToUserId)
            .map((u) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(u.userId),
                  child: Text(u.fullName),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;

    // ⚠️ **السؤال يُطرح فقط إن كان ثمّة مسؤولٌ سابق** — ومهمةٌ بلا مسؤول لا سابقَ لها.
    var keepPrevious = true;
    if (t.assignedToUserId != null) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('ماذا عن المسؤول السابق؟'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المسؤول الحالي: ${t.assignedToUserName ?? "—"}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: keepPrevious,
                  onChanged: (v) => setLocal(() => keepPrevious = v ?? true),
                  title: const Text('أبقِه مشاركاً يرى المهمة ويتابعها'),
                  subtitle: const Text(
                      'إن أزلته فلن يراها بعد الآن — واسمُه يبقى في سجلّها',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(keepPrevious),
                child: const Text('نقل المسؤولية'),
              ),
            ],
          ),
        ),
      );
      if (answer == null) return;   // ألغى
      keepPrevious = answer;
    }

    await _run(() => ref
        .read(apiClientProvider)
        .reassignTask(t.taskId, picked, keepPreviousAsParticipant: keepPrevious));
  }

  /// بطاقة المشاركين — **مَن يرى المهمة غير مسؤولها**.
  Widget _participantsCard(TaskModel t) {
    final async = ref.watch(taskParticipantsProvider(t.taskId));

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('المشاركون',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('مَن يرى هذه المهمة غير مسؤولها',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color)),
              ),
              if (t.canEdit)
                TextButton.icon(
                  onPressed: _busy ? null : () => _promptAddParticipant(t),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text('إضافة'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger)),
            data: (rows) {
              final active = rows.where((p) => !p.isRemoved).toList();
              if (active.isEmpty) {
                return Text('لا مشاركين — المهمة يراها مسؤولها ومُنشئها وقسمها',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color));
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: active
                    .map((p) => Chip(
                          avatar: Icon(
                              p.isDepartment
                                  ? Icons.groups_2_outlined
                                  : Icons.person_outline_rounded,
                              size: 16),
                          label: Text(p.displayName, style: const TextStyle(fontSize: 12)),
                          onDeleted: t.canEdit && !_busy
                              ? () => _run(() => ref
                                  .read(apiClientProvider)
                                  .removeTaskParticipant(t.taskId, p.participantId))
                              : null,
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _promptAddParticipant(TaskModel t) async {
    final users = await ref.read(assignableUsersProvider.future);
    final departments = await ref.read(departmentsListProvider.future);
    if (!mounted) return;

    final choice = await showDialog<({int? userId, int? departmentId})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('إضافة مشارك'),
        children: [
          if (departments.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text('الأقسام',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            ...departments.map((d) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx)
                      .pop((userId: null, departmentId: d.departmentId)),
                  child: Row(children: [
                    const Icon(Icons.groups_2_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(d.name),
                  ]),
                )),
          ],
          if (users.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text('الأشخاص',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            ...users.map((u) => SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(ctx).pop((userId: u.userId, departmentId: null)),
                  child: Row(children: [
                    const Icon(Icons.person_outline_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(u.fullName),
                  ]),
                )),
          ],
        ],
      ),
    );

    if (choice == null) return;
    await _run(() => ref.read(apiClientProvider).addTaskParticipant(
          t.taskId,
          userId: choice.userId,
          departmentId: choice.departmentId,
        ));
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
