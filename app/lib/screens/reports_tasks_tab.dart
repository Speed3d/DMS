import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/incoming_providers.dart';
import '../core/session.dart';
import '../models_tasks.dart';
import 'reports_screen.dart';

/// تبويب **تقرير المهام** — بفلاتر شاشة المهام نفسها (الدفعة ٧).
///
/// 🔐 يظهر لمن يملك **قسم التقارير مع قسم المهام ودورٍ فوق القارئ** (`canSeeTasksReport`)،
/// مرآةً لحارس الخادم `RequireGrantedModule(Tasks)` فوق حارس التقارير على الصنف.
///
/// 🔴 **ورؤية الصفوف تُحسم في الخادم** بقاعدة `TaskService.Query()` نفسها التي تغذّي شاشة
/// المهام — فما يُطبَع هنا **عين ما يُرى هناك**، ولا شرطَ رؤيةٍ مكتوبٌ في العميل.
class TasksDetailTab extends ConsumerStatefulWidget {
  const TasksDetailTab({super.key});
  @override
  ConsumerState<TasksDetailTab> createState() => _TasksDetailState();
}

class _TasksDetailState extends ConsumerState<TasksDetailTab> {
  DateTime? _from, _to;
  String? _status;
  String? _priority;
  int? _departmentId;
  bool? _isOverdue;
  TaskDetailReport? _report;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  bool get _hasFilters =>
      _from != null || _to != null || _status != null ||
      _priority != null || _departmentId != null || _isOverdue != null;

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      _report = await ref.read(apiClientProvider).tasksDetailReport(
            status: _status, priority: _priority, departmentId: _departmentId,
            dueFrom: _from, dueTo: _to, isOverdue: _isOverdue,
          );
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).tasksDetailFile(format,
          status: _status, priority: _priority, departmentId: _departmentId,
          dueFrom: _from, dueTo: _to, isOverdue: _isOverdue);
      await downloadBytes(bytes, reportFileName('tasks-detail', format), reportMime(format));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsListProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تقرير المهام', style: Theme.of(context).textTheme.headlineSmall),
          const Text('المهام التي تراها، بحالتها ومسؤولها وتأخّرها.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateFilterButton(label: 'موعدٌ من', value: _from, onPick: (d) => setState(() => _from = d)),
            DateFilterButton(label: 'موعدٌ إلى', value: _to, onPick: (d) => setState(() => _to = d)),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحالة', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('كل الحالات')),
                  ...kTaskStatusLabels.entries.map(
                      (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                initialValue: _priority,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الأولوية', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('كل الأولويات')),
                  ...kTaskPriorityLabels.entries.map(
                      (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: departments.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (list) => DropdownButtonFormField<int?>(
                  // ⚠️ القيمة تُمرَّر **فقط إن كان لها عنصرٌ في القائمة** — ومنسدلةٌ قيمتُها
                  //    تسبق قائمتها تُسقط الشاشة (درسٌ عولج في الوارد ثلاث مرات).
                  initialValue:
                      list.any((d) => d.departmentId == _departmentId) ? _departmentId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'القسم', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('كل الأقسام')),
                    ...list.map((d) => DropdownMenuItem<int?>(
                        value: d.departmentId,
                        child: Text(d.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
              ),
            ),
            FilterChip(
              label: const Text('المتأخّرة فقط'),
              selected: _isOverdue == true,
              onSelected: (v) => setState(() => _isOverdue = v ? true : null),
            ),
            FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.search),
                label: const Text('عرض')),
            if (_hasFilters)
              TextButton(
                  onPressed: () {
                    setState(() {
                      _from = null; _to = null; _status = null;
                      _priority = null; _departmentId = null; _isOverdue = null;
                    });
                    _run();
                  },
                  child: const Text('مسح الفلاتر')),
          ]),
          const SizedBox(height: 8),
          if (_report != null) ExportButtons(onExport: _export),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          Expanded(child: _busy ? const Center(child: CircularProgressIndicator()) : _results()),
        ],
      ),
    );
  }

  Widget _results() {
    final r = _report;
    if (r == null) return const SizedBox.shrink();
    if (r.rows.isEmpty) return const Center(child: Text('لا مهام ضمن الفلاتر المحددة.'));
    return Column(
      children: [
        Expanded(
          child: ReportTable(
            minWidth: 1150,
            columns: const [
              'الرقم', 'العنوان', 'القسم', 'المسؤول',
              'الأولوية', 'الحالة', 'الإنجاز', 'الموعد', 'التأخّر',
            ],
            rows: [
              for (final row in r.rows)
                [
                  row.number,
                  row.title,
                  row.departmentName,
                  row.assignedTo,
                  row.priorityLabel,
                  row.statusLabel,
                  '${row.progressPercent}%',
                  DateFormat('yyyy-MM-dd').format(row.dueDate),
                  // «—» لا «0 يوم»: صفرٌ في عمود التأخّر يُقرأ «تأخّرت اليوم».
                  row.isOverdue ? '${row.daysOverdue} يوم' : '—',
                ],
            ],
          ),
        ),
        // ⚠️ **متوسّط الإنجاز على النشِطة وحدها** — ومُعلَنٌ كذلك في نصّه، فرقمٌ مخصوص
        //    تحت تسميةٍ عامّة هو نصفُ العيب (درس ADR-029).
        SummaryBar(items: [
          'عدد المهام: ${r.count}',
          'نشِطة: ${r.active} · مكتملة: ${r.completed} · متأخرة: ${r.overdue}',
          'متوسّط إنجاز النشِطة: ${r.averageProgress}%',
        ]),
      ],
    );
  }
}
