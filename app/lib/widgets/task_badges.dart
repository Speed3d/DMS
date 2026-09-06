import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models.dart';

/// شارة حالة المهمة (ADR-037) — نمط `status_pill.dart`.
///
/// ⚠️ **لماذا شارةٌ خاصّة ولا تُستعمل [StatusPill]؟** لأن تلك تطابق النصّ بـ`contains`
/// على حالات الصادر والوارد، و«`New`» فيها تعني كتاباً وارداً جديداً. وحالاتُ المهمة ستٌّ
/// منها **«أُعيد فتحها»** التي لا نظير لها هناك — ومطابقةٌ فضفاضة كانت ستعطيها لون «جديد»
/// فيضيع الفرق الذي بُنيت الحالةُ لإظهاره.
class TaskStatusPill extends StatelessWidget {
  final String status;

  /// التسمية من الخادم إن وُجدت — **وهو المرجع** عند التعارض.
  final String? label;

  const TaskStatusPill({super.key, required this.status, this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colorFor(status, isDark);
    final text = (label != null && label!.isNotEmpty)
        ? label!
        : (kTaskStatusLabels[status] ?? status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  static Color colorFor(String status, bool isDark) => switch (status) {
        'New' => isDark ? Colors.blueAccent.shade100 : Colors.blueAccent,
        'InProgress' => isDark ? AppColors.warnDark : AppColors.warn,
        'OnHold' => isDark ? Colors.orange.shade200 : Colors.orange.shade800,
        'Completed' => isDark ? AppColors.successDark : AppColors.success,
        'Cancelled' => Colors.grey,
        'Reopened' => isDark ? Colors.purple.shade200 : Colors.purple,
        _ => Colors.grey,
      };
}

/// شارة أولوية المهمة.
class TaskPriorityBadge extends StatelessWidget {
  final String priority;
  final String? label;

  const TaskPriorityBadge({super.key, required this.priority, this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colorFor(priority, isDark);
    final text = (label != null && label!.isNotEmpty)
        ? label!
        : (kTaskPriorityLabels[priority] ?? priority);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconFor(priority), size: 13, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  static Color colorFor(String priority, bool isDark) => switch (priority) {
        'Low' => Colors.grey,
        'Normal' => isDark ? Colors.blueGrey.shade200 : Colors.blueGrey,
        'High' => isDark ? AppColors.warnDark : AppColors.warn,
        'Urgent' => isDark ? AppColors.dangerDark : AppColors.danger,
        _ => Colors.grey,
      };

  static IconData iconFor(String priority) => switch (priority) {
        'Low' => Icons.keyboard_arrow_down_rounded,
        'Normal' => Icons.remove_rounded,
        'High' => Icons.keyboard_arrow_up_rounded,
        'Urgent' => Icons.priority_high_rounded,
        _ => Icons.remove_rounded,
      };
}

/// سطرُ «متأخرة كذا يوماً» أو «تبقّى كذا» — **نصٌّ واحد لمعنى واحد**.
///
/// 🔴 **يقرأ `isOverdue` من الخادم ولا يحسبها**: القاعدة «الموعد يومٌ لا لحظة» تعيش في
/// `TaskWorkflow.IsOverdue` بتوقيت بغداد، وحسابُها هنا بساعة الجهاز يجعل مهمةً حمراء عند
/// مستخدمٍ وخضراء عند زميله في اللحظة نفسها.
class TaskDueLabel extends StatelessWidget {
  final bool isOverdue;
  final int daysOverdue;
  final int daysRemaining;

  const TaskDueLabel({
    super.key,
    required this.isOverdue,
    required this.daysOverdue,
    required this.daysRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isOverdue) {
      final color = isDark ? AppColors.dangerDark : AppColors.danger;
      return Text(
        daysOverdue == 1 ? 'متأخرة يوماً' : 'متأخرة $daysOverdue أيام',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      );
    }

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);

    final text = switch (daysRemaining) {
      0 => 'تستحق اليوم',
      1 => 'غداً',
      < 0 => 'انقضى موعدها',
      _ => 'بعد $daysRemaining أيام',
    };

    return Text(
      text,
      style: TextStyle(
        color: daysRemaining == 0 ? (isDark ? AppColors.warnDark : AppColors.warn) : muted,
        fontSize: 11,
        fontWeight: daysRemaining == 0 ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
