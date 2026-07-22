import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Hint: هذه الويدجت تعطي شكلاً مميزاً (Pill) لحالة الكتاب —
/// حالات الصادر (مسودة/قيد الاعتماد/معتمد/مرفوض) وحالات الوارد (جديد/قيد المراجعة/تم الرد/مغلق/مؤرشف).
class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    Color bgColor;
    String label;

    final lowerStatus = status.toLowerCase();

    if (lowerStatus.contains('draft')) {
        color = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6) ?? Colors.grey;
        bgColor = theme.dividerColor.withValues(alpha: 0.3);
        label = 'مسودة';
    } else if (lowerStatus.contains('pending')) {
        color = isDark ? AppColors.warnDark : AppColors.warn;
        bgColor = color.withValues(alpha: 0.15);
        label = 'قيد الاعتماد';
    } else if (lowerStatus.contains('final') || lowerStatus.contains('approved')) {
        color = isDark ? AppColors.successDark : AppColors.success;
        bgColor = color.withValues(alpha: 0.15);
        label = 'معتمد';
    } else if (lowerStatus.contains('reject')) {
        color = isDark ? AppColors.dangerDark : AppColors.danger;
        bgColor = color.withValues(alpha: 0.15);
        label = 'مرفوض';
    } else if (lowerStatus == 'new') {
        color = isDark ? Colors.blueAccent.shade100 : Colors.blueAccent;
        bgColor = color.withValues(alpha: 0.15);
        label = 'جديد';
    } else if (lowerStatus == 'inreview') {
        color = isDark ? Colors.orangeAccent.shade100 : Colors.orangeAccent;
        bgColor = color.withValues(alpha: 0.15);
        label = 'قيد المراجعة';
    } else if (lowerStatus == 'replied') {
        color = isDark ? Colors.tealAccent.shade100 : Colors.teal;
        bgColor = color.withValues(alpha: 0.15);
        label = 'تم الرد';
    } else if (lowerStatus == 'closed') {
        color = isDark ? Colors.blueGrey.shade200 : Colors.blueGrey.shade700;
        bgColor = color.withValues(alpha: 0.15);
        label = 'مغلق';
    } else if (lowerStatus == 'archived') {
        color = isDark ? Colors.purpleAccent.shade100 : Colors.purple;
        bgColor = color.withValues(alpha: 0.15);
        label = 'مؤرشف';
    } else {
        color = Colors.grey;
        bgColor = Colors.grey.withValues(alpha: 0.15);
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
