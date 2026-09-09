import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup_providers.dart';
import '../core/theme.dart';

/// لونُ درجة إلحاح النسخة الاحتياطية — **مصدرٌ واحد** تقرؤه البطاقة والشارة والأيقونة.
///
/// ⚠️ ثلاثة مواضع بثلاث خرائط ألوان تتباعد عند أول تعديل، فيصير اللون في القائمة الجانبية
/// أهدأ ممّا في الشاشة — **والتنبيه الذي يتناقض مع نفسه لا يُصدَّق**.
Color backupUrgencyColor(String urgency) => switch (urgency) {
      'Ok' => AppColors.success,
      'Soon' => AppColors.gold,
      'Urgent' => AppColors.warn,
      _ => AppColors.danger,
    };

IconData backupUrgencyIcon(String urgency) => switch (urgency) {
      'Ok' => Icons.verified_rounded,
      'Soon' => Icons.schedule_rounded,
      'Urgent' => Icons.warning_amber_rounded,
      _ => Icons.error_outline_rounded,
    };

/// أيقونة تحذير النسخ في الشريط العلوي — **للسوبر أدمن وحده وعند التأخّر وحده**
/// (طلب المالك 2026-09-09).
///
/// 🔴 **ولماذا أيقونةٌ مستقلّة لا إشعارٌ في الجرس؟** لأن جدول الإشعارات (ADR-038) مربوطٌ
/// بـ**شركةٍ ومُستلِم**، والنسخة الاحتياطية **شأنٌ نظاميّ لا يخصّ شركة** — فوضعُ رقم شركةٍ
/// فيه كذبٌ في البيانات. ولأن التغطية **حالةٌ حيّة تختفي فور أخذ النسخة**، بينما الإشعار
/// المخزَّن يبقى حتى يُقرأ فيُنبّه على أمرٍ عولج.
///
/// ⚠️ **وتغيب تماماً حين لا تأخّر** — أيقونةٌ دائمة تُصبح جزءاً من الأثاث فلا تُرى حين تلزم.
class BackupAlertIcon extends ConsumerWidget {
  /// يفتح قسم النسخ الاحتياطي (المؤشّر 8) — **التنبيه يقود إلى علاجه لا إلى نصٍّ فقط**.
  final VoidCallback? onOpenBackup;

  const BackupAlertIcon({super.key, this.onOpenBackup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(backupAlertProvider);
    if (alert == null) return const SizedBox.shrink();

    final color = backupUrgencyColor(alert.urgency);
    final days = alert.daysSince;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Tooltip(
        message: alert.message,
        child: Material(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onOpenBackup,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(backupUrgencyIcon(alert.urgency), size: 18, color: color),
                  // ⚠️ **الرقم يُعرض إن وُجد**: «مضى 42 يوماً» يُقرأ فوراً، و«تحذير» وحده
                  //    يحتاج ضغطةً ليُعرف مداه. ومن لا نسخةَ له قطّ بلا رقم — فلا يُختلق.
                  if (days != null) ...[
                    const SizedBox(width: 6),
                    Text('$days يوم',
                        style: TextStyle(
                            color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
