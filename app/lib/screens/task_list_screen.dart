import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav_intent.dart';
import '../core/session.dart';
import '../core/task_providers.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/search_field.dart';
import '../widgets/task_badges.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

/// قائمة المهام (ADR-037).
///
/// 🔴 **التخطيط يتضيّق بعتبةٍ مقيسة لا مخمَّنة**: الدرس المسجَّل من وحدة الرواتب — خُمّنت
/// عتبةُ الشريط 880 فوجدها الحارس تفيض عند 880 بالضبط، والصحيح 920. وهنا الشريط يلتفّ
/// بـ`Wrap` فلا عتبةَ سحرية أصلاً (درس G12).
class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // «نيّة التنقّل» — الضاغط في لوحة التحكم يكتب نيّته، وهذه الشاشة تقرؤها **وتمسحها**.
    // ⚠️ قراءةٌ متزامنة (`peek`) ومسحٌ **مؤجَّلٌ بعد الإطار ومشروطٌ**: المسح داخل
    //    `initState` يعدّل مزوّداً أثناء طور البناء فيرمي Riverpod، والمسح غير المشروط
    //    يبتلع نيّةً جديدة كُتبت في تلك الأثناء (بلاغ 2026-08-06).
    final intent = ref.read(navIntentProvider.notifier).peek<TaskListIntent>();
    if (intent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(taskFilterProvider.notifier).update(switch (intent.kind) {
              TaskIntentKind.mine => const TaskFilterState(mineOnly: true),
              TaskIntentKind.overdue => const TaskFilterState(isOverdue: true),
              TaskIntentKind.dueToday => const TaskFilterState(),
            });
        ref.read(navIntentProvider.notifier).clearIf(intent);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm({TaskModel? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TaskFormScreen(existing: existing)),
    );
    if (saved == true && mounted) invalidateTasks(ref);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final filters = ref.watch(taskFilterProvider);
    final pageAsync = ref.watch(tasksPageProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(filters),
          const SizedBox(height: 14),
          Expanded(
            child: pageAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _errorBox(e),
              data: (page) => page.items.isEmpty
                  ? _emptyState(filters, session)
                  : _list(page),
            ),
          ),
        ],
      ),
    );
  }

  // ── الشريط: بحثٌ حيّ + فلاتر + زرّ إنشاء ──
  //
  // ⚠️ **`Wrap` لا `Row`** (درس G12): الشريط فيه ستّة عناصر، و`Row` يفيض تحت ~500 بكسل
  //    بأشرطةٍ حمراء تحجب المحتوى. والالتفاف يجعل التضييق تدريجياً بلا عتبةٍ تُخمَّن.
  Widget _toolbar(TaskFilterState f) {
    final notifier = ref.read(taskFilterProvider.notifier);

    return CustomCard(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DebouncedSearchField(
              controller: _searchController,
              hintText: 'ابحث بالعنوان أو الرقم…',
              onChanged: (v) => notifier.update(f.copyWith(search: v)),
            ),
          ),
          _dropdown(
            hint: 'كل الحالات',
            value: f.status,
            items: kTaskStatusLabels,
            onChanged: (v) => notifier.update(
                v == null ? f.copyWith(clearStatus: true) : f.copyWith(status: v)),
          ),
          _dropdown(
            hint: 'كل الأولويات',
            value: f.priority,
            items: kTaskPriorityLabels,
            onChanged: (v) => notifier.update(
                v == null ? f.copyWith(clearPriority: true) : f.copyWith(priority: v)),
          ),
          FilterChip(
            label: const Text('مهامي'),
            selected: f.mineOnly,
            onSelected: (v) => notifier.update(f.copyWith(mineOnly: v)),
          ),
          FilterChip(
            label: const Text('المتأخرة'),
            selected: f.isOverdue == true,
            onSelected: (v) => notifier.update(
                v ? f.copyWith(isOverdue: true) : f.copyWith(clearOverdue: true)),
          ),
          if (f.hasAnyFilter)
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                notifier.reset();
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('مسح الفلاتر'),
            ),
          ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: const Text('مهمة جديدة'),
          ),
        ],
      ),
    );
  }

  /// منسدلةٌ **بقيمةٍ آمنة** — درس ADR-032: قيمةٌ لا توجد بين خياراتها تُسقط الشاشة كلها
  /// بـ«There should be exactly one item with [DropdownButton]'s value».
  Widget _dropdown({
    required String hint,
    required String? value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<String>(
          initialValue: safeDropdownValue(value, items.keys),
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            hintText: hint,
          ),
          items: [
            DropdownMenuItem<String>(value: null, child: Text(hint)),
            ...items.entries.map(
                (e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _list(TaskPage page) => Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _TaskRow(
                item: page.items[i],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TaskDetailScreen(taskId: page.items[i].taskId)));
                  if (mounted) invalidateTasks(ref);
                },
              ),
            ),
          ),
          if (page.total > page.pageSize) _pager(page),
        ],
      );

  Widget _pager(TaskPage page) {
    final f = ref.read(taskFilterProvider);
    final notifier = ref.read(taskFilterProvider.notifier);
    final lastPage = (page.total + page.pageSize - 1) ~/ page.pageSize;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page.page > 1
                ? () => notifier.update(f.copyWith(page: page.page - 1))
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'السابق',
          ),
          Text('صفحة ${page.page} من $lastPage  ·  ${page.total} مهمة'),
          IconButton(
            onPressed: page.page < lastPage
                ? () => notifier.update(f.copyWith(page: page.page + 1))
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'التالي',
          ),
        ],
      ),
    );
  }

  Widget _emptyState(TaskFilterState f, SessionState session) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded,
                size: 56,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            Text(
              f.hasAnyFilter ? 'لا مهامّ تطابق الفلاتر الحالية' : 'لا مهامّ بعد',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              f.hasAnyFilter
                  ? 'جرّب توسيع الفلاتر أو امسحها'
                  : 'ابدأ بإنشاء مهمة — لك أو لقسمك',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 16),
            // 🔴 **زرُّ الإنشاء في الحالة الفارغة كذلك** — وهي أوّل ما يراه المستخدم في
            //    شركةٍ جديدة، أي بالضبط موضع الحاجة (درس ADR-027: «ميزة بلا مدخل»).
            if (!f.hasAnyFilter)
              ElevatedButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('مهمة جديدة'),
              )
            else
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  ref.read(taskFilterProvider.notifier).reset();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('مسح الفلاتر'),
              ),
          ],
        ),
      );

  Widget _errorBox(Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذّر تحميل المهام: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger)),
        ),
      );
}

/// صفُّ مهمة — **يلتفّ ولا يفيض**، والعناصر الثانوية تسقط أولاً عند الضيق.
class _TaskRow extends StatelessWidget {
  final TaskListItem item;
  final VoidCallback onTap;

  const _TaskRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = TaskStatusPill.colorFor(item.status, isDark);

    return CustomCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريطُ لونٍ رفيع يحمل الحالة — يُقرأ بطرف العين قبل النصّ.
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsetsDirectional.only(end: 12),
            decoration: BoxDecoration(
                color: statusColor, borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                // ⚠️ `Wrap` — الشارات الستّ تفيض في `Row` عند ~380 بكسل.
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TaskStatusPill(status: item.status, label: item.statusLabel),
                    TaskPriorityBadge(
                        priority: item.priority, label: item.priorityLabel),
                    TaskDueLabel(
                      isOverdue: item.isOverdue,
                      daysOverdue: item.daysOverdue,
                      daysRemaining: item.daysRemaining,
                    ),
                    if (item.assignedToUserName != null)
                      _meta(context, Icons.person_outline_rounded, item.assignedToUserName!),
                    if (item.isDepartmentTask && item.departmentName != null)
                      _meta(context, Icons.groups_2_outlined, item.departmentName!),
                    if (item.attachmentCount > 0)
                      _meta(context, Icons.attach_file_rounded, '${item.attachmentCount}'),
                    if (item.taskNumber != null)
                      _meta(context, Icons.tag_rounded, item.taskNumber!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _progressRing(context, item.progressPercent, statusColor),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    final color = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Widget _progressRing(BuildContext context, int percent, Color color) => SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 4,
              backgroundColor: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(color),
            ),
            Text('$percent',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
