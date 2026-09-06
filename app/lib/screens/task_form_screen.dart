import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/incoming_providers.dart';
import '../core/session.dart';
import '../core/task_providers.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// نموذج إنشاء/تعديل مهمة (ADR-037).
///
/// 🔴 **حقل المسؤول يغيب لمن لا يملك `CanManageTasks` — ولا يُعطَّل.** والخادم يُسنِد
/// المهمة لصاحبها قسراً، فحقلٌ معطَّل كان يَعِد بشيءٍ لا يقع؛ **والخفاء أصدق من التعطيل**.
class TaskFormScreen extends ConsumerStatefulWidget {
  /// `null` ⇒ إنشاء. وغيرُه ⇒ تعديل.
  final TaskModel? existing;

  /// ربطٌ مسبق بكتابٍ وارد/صادر (زرّ «إنشاء مهمة من هذا الكتاب»).
  final int? presetIncomingId;
  final int? presetOutgoingId;

  const TaskFormScreen({
    super.key,
    this.existing,
    this.presetIncomingId,
    this.presetOutgoingId,
  });

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _notes;

  String _taskType = 'Individual';
  String _priority = 'Normal';
  DateTime? _dueDate;
  int? _departmentId;
  int? _assignedToUserId;

  bool _isRecurring = false;
  String _recurrencePattern = 'Weekly';
  final _recurrenceInterval = TextEditingController(text: '1');
  DateTime? _recurrenceEndDate;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');

    if (e != null) {
      _taskType = e.taskType;
      _priority = e.priority;
      _dueDate = e.dueDate;
      _departmentId = e.departmentId;
      _assignedToUserId = e.assignedToUserId;
      _isRecurring = e.isRecurring;
      _recurrencePattern = e.recurrencePattern ?? 'Weekly';
      _recurrenceInterval.text = '${e.recurrenceInterval ?? 1}';
      _recurrenceEndDate = e.recurrenceEndDate;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _notes.dispose();
    _recurrenceInterval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dueDate == null) {
      setState(() => _error = 'موعد التسليم مطلوب.');
      return;
    }
    if (_taskType == 'Department' && _departmentId == null) {
      setState(() => _error = 'مهمة القسم تحتاج تحديد القسم.');
      return;
    }

    // 🔴 **سببٌ إلزاميّ عند تغيير ما يمسّ غيرك** (قرار المالك): العنوان · الموعد ·
    //    الأولوية · القسم. وتصحيحُ الوصف أو الملاحظات يمرّ بلا سؤال — فاشتراطُ تعليلٍ لكل
    //    حرفٍ يدفع الناس إلى كتابة «تعديل»، **فيصير الحقل شكليّاً وهو أسوأ من غيابه**.
    //    ⚠️ **مرآةٌ لحارس الخادم** (`TaskChangeReason`): يفرض القاعدة نفسها بـ400.
    String? reason;
    if (_isEdit && _materialChange()) {
      reason = await _promptReason();
      if (reason == null) return;   // ألغى — لا حفظ
    }

    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      if (_isEdit) {
        await api.updateTask(
          widget.existing!.taskId,
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          priority: _priority,
          dueDate: _dueDate!,
          departmentId: _departmentId,
          relatedIncomingId: widget.existing!.relatedIncomingId,
          relatedOutgoingId: widget.existing!.relatedOutgoingId,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          rowVersion: widget.existing!.rowVersion,
          reason: reason,
        );
      } else {
        await api.createTask(
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          taskType: _taskType,
          priority: _priority,
          dueDate: _dueDate!,
          departmentId: _taskType == 'Department' ? _departmentId : null,
          assignedToUserId: _assignedToUserId,
          relatedIncomingId: widget.presetIncomingId,
          relatedOutgoingId: widget.presetOutgoingId,
          isRecurring: _isRecurring,
          recurrencePattern: _isRecurring ? _recurrencePattern : null,
          recurrenceInterval:
              _isRecurring ? (int.tryParse(_recurrenceInterval.text) ?? 1) : null,
          recurrenceEndDate: _isRecurring ? _recurrenceEndDate : null,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canAssign = session.canManageTasks;
    final departments = ref.watch(departmentsListProvider);
    final assignable = ref.watch(assignableUsersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل مهمة' : 'مهمة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                        labelText: 'عنوان المهمة *', border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'الوصف',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),

                  // ⚠️ `Wrap` — الحقول الثلاثة تفيض في `Row` تحت ~500 بكسل (درس G12).
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // نوع المهمة — **يُقفل في التعديل**: تحويلُ فرديةٍ إلى مهمة قسم يغيّر
                      // **مَن يراها**، وهو قرارُ إسنادٍ لا تحريرُ حقل.
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _taskType,
                          decoration: const InputDecoration(
                              labelText: 'نوع المهمة', border: OutlineInputBorder()),
                          items: kTaskTypeLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: _isEdit
                              ? null
                              : (v) => setState(() {
                                    _taskType = v ?? 'Individual';
                                    if (_taskType == 'Individual') _departmentId = null;
                                  }),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _priority,
                          decoration: const InputDecoration(
                              labelText: 'الأولوية', border: OutlineInputBorder()),
                          items: kTaskPriorityLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setState(() => _priority = v ?? 'Normal'),
                        ),
                      ),
                      SizedBox(width: 220, child: _dueDateField()),
                    ],
                  ),

                  if (_taskType == 'Department') ...[
                    const SizedBox(height: 14),
                    departments.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('تعذّر تحميل الأقسام: $e',
                          style: const TextStyle(color: AppColors.danger)),
                      data: (list) => DropdownButtonFormField<int>(
                        initialValue: safeDropdownValue(
                            _departmentId, list.map((d) => d.departmentId)),
                        decoration: const InputDecoration(
                            labelText: 'القسم *', border: OutlineInputBorder()),
                        items: list
                            .map((d) => DropdownMenuItem(
                                value: d.departmentId, child: Text(d.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _departmentId = v),
                      ),
                    ),
                  ],

                  // 🔴 **يغيب لمن لا يملك العلَم** — والخادم يُسنده لنفسه قسراً.
                  if (canAssign && !_isEdit) ...[
                    const SizedBox(height: 14),
                    assignable.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('تعذّر تحميل المستخدمين: $e',
                          style: const TextStyle(color: AppColors.danger)),
                      data: (users) => DropdownButtonFormField<int>(
                        initialValue: safeDropdownValue(
                            _assignedToUserId, users.map((u) => u.userId)),
                        decoration: InputDecoration(
                          labelText: _taskType == 'Department'
                              ? 'المسؤول (اختياري — القسم كلُّه مسؤول)'
                              : 'المسؤول',
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                              value: null, child: Text('— بلا مسؤولٍ بعينه —')),
                          ...users.map((u) => DropdownMenuItem(
                              value: u.userId, child: Text(u.fullName))),
                        ],
                        onChanged: (v) => setState(() => _assignedToUserId = v),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'ملاحظات', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),

            // التكرار — **عند الإنشاء وحده**: تحويلُ مهمةٍ قائمة إلى أمٍّ متكررة يخلق
            // نُسخاً بأثرٍ رجعيّ غامض.
            if (!_isEdit) ...[
              const SizedBox(height: 14),
              CustomCard(child: _recurrenceSection()),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ],

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_isEdit ? 'حفظ التعديل' : 'إنشاء المهمة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// هل يمسّ هذا التعديل غيرَ صاحبه؟ — **مرآةُ `TaskChangeReason.EditNeedsReason`**.
  ///
  /// ⚠️ النسختان تتحرّكان معاً: الخادم يرفض بـ400، وهذه تسأل قبل الإرسال. ولو تباعدتا
  /// لسأل النموذج عن سببٍ لا يُطلب، أو أرسل بلا سببٍ فارتطم برفضٍ لا يفهمه المستخدم.
  bool _materialChange() {
    final e = widget.existing!;
    return e.title.trim() != _title.text.trim()
        || e.dueDate.difference(_dueDate!).inDays != 0
        || e.priority != _priority
        || e.departmentId != _departmentId;
  }

  Future<String?> _promptReason() async {
    final controller = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('سبب التعديل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'غيّرتَ ما يقرؤه غيرُك (العنوان أو الموعد أو الأولوية أو القسم).\n'
                'اكتب سبباً يُحفظ في سجلّ المهمة.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'مثال: تأجيل الموعد بطلب القسم القانوني',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().length < 5) {
                  setLocal(() => error = 'السبب مطلوب (٥ أحرف فأكثر)');
                  return;
                }
                Navigator.of(ctx).pop(controller.text.trim());
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  Widget _dueDateField() => InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _dueDate ?? now,
            // ⚠️ **الماضي مسموحٌ في التعديل ممنوعٌ في الإنشاء** — مرآةُ حارس الخادم:
            //    مهمةٌ تُنشأ متأخرةً خطأُ إدخالٍ غالباً، والتعديل قد يكون تصحيحاً.
            firstDate: _isEdit ? DateTime(now.year - 3) : DateTime(now.year, now.month, now.day),
            lastDate: DateTime(now.year + 3),
          );
          if (picked != null) setState(() => _dueDate = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
              labelText: 'موعد التسليم *', border: OutlineInputBorder()),
          child: Text(_dueDate == null ? 'اختر التاريخ' : _fmt(_dueDate!)),
        ),
      );

  Widget _recurrenceSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isRecurring,
            title: const Text('مهمة متكررة'),
            subtitle: const Text(
                'تُنشأ نسخةٌ جديدة تلقائياً عند كل دورة',
                style: TextStyle(fontSize: 11)),
            onChanged: (v) => setState(() => _isRecurring = v),
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('كل'),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _recurrenceInterval,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: _recurrencePattern,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: kRecurrenceLabels.entries
                        .map((e) =>
                            DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _recurrencePattern = v ?? 'Weekly'),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _recurrenceEndDate ?? (_dueDate ?? now),
                      firstDate: _dueDate ?? now,
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) setState(() => _recurrenceEndDate = picked);
                  },
                  icon: const Icon(Icons.event_busy_rounded, size: 16),
                  label: Text(_recurrenceEndDate == null
                      ? 'حتى: بلا نهاية'
                      : 'حتى ${_fmt(_recurrenceEndDate!)}'),
                ),
                if (_recurrenceEndDate != null)
                  IconButton(
                    tooltip: 'إزالة تاريخ النهاية',
                    onPressed: () => setState(() => _recurrenceEndDate = null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
              ],
            ),
          ],
        ],
      );

  /// ⚠️ **تنسيقٌ تقويميّ بلا منطقةٍ زمنية** — لا `toLocal()` على يومٍ (درس G18).
  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
