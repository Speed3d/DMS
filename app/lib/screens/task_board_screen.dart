import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/task_providers.dart';
import '../models_tasks.dart';
import '../widgets/task_badges.dart';
import 'task_detail_screen.dart';

/// **لوحة الكانبان** — أعمدةُ الحالات وبطاقاتٌ تُسحَب بينها (الدفعة ٧).
///
/// 🔴 **المصفوفة لا تُنسَخ هنا**: العمود يقبل الإفلات **إن كانت حالتُه في `nextStatuses`
/// القادمة من الخادم** (`TaskWorkflow`). ومصفوفةُ انتقالٍ مكتوبةٌ في Dart كانت ستتباعد عند
/// أول تعديل، **فتُبرز اللوحة عموداً يرفضه الخادم**.
///
/// 🔴 **و«ملغاة» ليست عموداً** — لأن الإلغاء **قرارٌ نهائي بلا رجعة** (`TaskWorkflow`)،
/// وسحبةُ إصبعٍ خاطئة لا يصحّ أن تُنهي مهمةً بلا سؤال. يبقى الإلغاء من شاشة التفاصيل حيث
/// يُقرأ ويُؤكَّد. ⚠️ **ولئلّا تختفي الملغاة صامتةً** يُعلَن عددها أسفل اللوحة صراحةً.
///
/// 🔴 **وإعادة الفتح لا تمرّ من الإفلات**: لها نقطتُها وسببُها الإلزاميّ — فالإفلات على
/// عمود «أُعيد فتحها» **يفتح حواراً يطلب السبب**، ولا يُرسل شيئاً قبل كتابته.
class TaskBoardScreen extends ConsumerStatefulWidget {
  const TaskBoardScreen({super.key});

  @override
  ConsumerState<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

/// أعمدة اللوحة — **بلا «ملغاة»** (انظر توثيق الصنف).
const List<({String status, String label, IconData icon})> _boardColumns = [
  (status: 'New', label: 'جديدة', icon: Icons.fiber_new_outlined),
  (status: 'InProgress', label: 'قيد التنفيذ', icon: Icons.play_circle_outline),
  (status: 'OnHold', label: 'معلّقة', icon: Icons.pause_circle_outline),
  (status: 'Reopened', label: 'أُعيد فتحها', icon: Icons.refresh),
  (status: 'Completed', label: 'مكتملة', icon: Icons.check_circle_outline),
];

class _TaskBoardScreenState extends ConsumerState<TaskBoardScreen> {
  /// المهمة المسحوبة الآن — لتُبرَز أعمدةُ الإفلات الصالحة وحدها.
  TaskListItem? _dragging;

  bool _busy = false;

  Future<void> _move(TaskListItem task, String to) async {
    if (task.status == to) return;

    final messenger = ScaffoldMessenger.of(context);
    String? reason;

    // إعادة الفتح: سببٌ إلزاميّ — والحوار يسبق الطلب فلا يُرسل نداءٌ يُرَدّ.
    if (to == 'Reopened') {
      reason = await _askReason();
      if (reason == null) return;
    }

    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      if (to == 'Reopened') {
        await api.reopenTask(task.taskId, reason!);
      } else {
        await api.changeTaskStatus(task.taskId, to);
      }
      ref.invalidate(taskBoardProvider);
      ref.invalidate(tasksPageProvider);
      ref.invalidate(taskSummaryProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب إعادة الفتح'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'لماذا تُعاد هذه المهمة إلى العمل؟',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.length < 5) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('إعادة الفتح'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.canSeeTasks) {
      return const Center(child: Text('قسم المهام غير متاح بصلاحياتك.'));
    }

    final page = ref.watch(taskBoardProvider);

    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (data) {
        final cancelled =
            data.items.where((t) => t.status == 'Cancelled').length;
        final truncated = data.total > data.items.length;

        return Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Row(
                  // 🔴 **`stretch` لا `start`** — فيأخذ العمود ارتفاع الشاشة المتاح ويُحسَب
                  //    ارتفاع قائمته بـ`Expanded`. وارتفاعٌ مكتوبٌ بيدي (`maxHeight: 560`)
                  //    يفيض كلّما ضاقت النافذة: **رقمٌ يساوي مجموع أرقامٍ أخرى يُحسب لا يُكتب**
                  //    (درسُ فيض 94 بكسل في وحدة الرواتب — وقد فاض هنا 28 بكسلاً فعلاً).
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final col in _boardColumns)
                      _column(col, data.items
                          .where((t) => t.status == col.status)
                          .toList()),
                  ],
                ),
              ),
            ),

            // ⚠️ **الملغاة تُعدّ ولا تُعرض** — وإخفاؤها بلا إعلانٍ يجعل اللوحة تكذب في
            //    عددها. النصّ يقول أين تُقرأ.
            if (cancelled > 0 || truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Icon(truncated ? Icons.warning_amber : Icons.info_outline,
                        size: 15,
                        color: truncated ? Colors.orange : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          if (cancelled > 0)
                            'و$cancelled مهمة ملغاة لا تظهر على اللوحة — تجدها في قائمة المهام.',
                          // ⚠️ **العدد يُعلَن حين يُقصّ** — لوحةٌ تعرض 200 من 340 بلا كلمة
                          //    تجعل القارئ يبني قراره على نصف الصورة وهو يحسبها كاملة.
                          if (truncated)
                            'تعرض اللوحة ${data.items.length} من ${data.total} مهمة — ضيّق الفلاتر لرؤية الباقي.',
                        ].join('  '),
                        style: TextStyle(
                            fontSize: 12,
                            color: truncated ? Colors.orange : Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _column(
      ({String status, String label, IconData icon}) col, List<TaskListItem> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = TaskStatusPill.colorFor(col.status, isDark);

    // العمود صالحٌ للإفلات **بحسب مصفوفة الخادم** لا بحسب حكمٍ محليّ.
    final canDrop = _dragging != null &&
        _dragging!.status != col.status &&
        _dragging!.nextStatuses.contains(col.status);

    return DragTarget<TaskListItem>(
      onWillAcceptWithDetails: (d) =>
          d.data.status != col.status && d.data.nextStatuses.contains(col.status),
      onAcceptWithDetails: (d) => _move(d.data, col.status),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return Container(
          width: 290,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hovering
                ? color.withValues(alpha: 0.12)
                : Theme.of(context).cardColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovering
                  ? color
                  : canDrop
                      ? color.withValues(alpha: 0.55)
                      : Theme.of(context).dividerColor.withValues(alpha: 0.4),
              width: hovering || canDrop ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Icon(col.icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Text(col.label,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: color, fontSize: 14)),
                    const Spacer(),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${items.length}',
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('لا مهام',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _card(items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(TaskListItem t) {
    final card = _CardBody(task: t);

    // مهمةٌ في حالةٍ نهائية لا تُسحَب — والسحبُ الذي لا يقود إلى شيء يُربك.
    if (t.nextStatuses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _tappable(t, Opacity(opacity: 0.75, child: card)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LongPressDraggable<TaskListItem>(
        data: t,
        onDragStarted: () => setState(() => _dragging = t),
        onDragEnd: (_) => setState(() => _dragging = null),
        onDraggableCanceled: (_, _) => setState(() => _dragging = null),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 260, child: card),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: _tappable(t, card),
      ),
    );
  }

  Widget _tappable(TaskListItem t, Widget child) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TaskDetailScreen(taskId: t.taskId)));
          ref.invalidate(taskBoardProvider);
      ref.invalidate(tasksPageProvider);
        },
        child: child,
      );
}

/// بطاقة المهمة على اللوحة — مفصولةٌ لأنها تُرسَم **ثلاث مرات** (ثابتة · مسحوبة · شبح).
class _CardBody extends StatelessWidget {
  final TaskListItem task;
  const _CardBody({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: task.isOverdue
              ? Colors.red.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TaskPriorityBadge(priority: task.priority, label: task.priorityLabel),
              const Spacer(),
              if (task.taskNumber != null)
                Text(task.taskNumber!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Text(task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          if (task.progressPercent > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: task.progressPercent / 100, minHeight: 4),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              // 🔴 **`Wrap` لا `Row` مسطّح**: البطاقة تُرسَم بعرض 250 حين تُسحَب، فالتاريخ
              //    ووسمُ التأخّر معاً يفيضان أفقياً (فاض 16 بكسلاً فعلاً وأمسكه الحارس).
              //    والالتفاف يُبقي المعلومتين ظاهرتين بدل قصّ إحداهما.
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event,
                            size: 13,
                            color: task.isOverdue ? Colors.red : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('yyyy-MM-dd').format(task.dueDate),
                          style: TextStyle(
                            fontSize: 11,
                            color: task.isOverdue ? Colors.red : Colors.grey,
                            fontWeight:
                                task.isOverdue ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    // «متأخرة N يوم» لا «0 يوم» — الصفر يُقرأ تأخّراً وهو ليس كذلك.
                    if (task.isOverdue)
                      Text('متأخرة ${task.daysOverdue} يوم',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (task.attachmentCount > 0) ...[
                const Icon(Icons.attach_file, size: 13, color: Colors.grey),
                Text('${task.attachmentCount}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
          if (task.assignedToUserName != null ||
              task.departmentName != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                    task.isDepartmentTask
                        ? Icons.groups_outlined
                        : Icons.person_outline,
                    size: 13,
                    color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.assignedToUserName ?? task.departmentName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
