import 'dart:async';

import 'package:flutter/material.dart';

import '../core/job_watcher.dart';
import '../core/theme.dart';

/// بطاقة تقدّم عمليةٍ طويلة — العنوان والمرحلة وشريطُ النسبة.
///
/// ⚠️ **شريطٌ غير محدَّد حين لا تُعرف النسبة** (نسخ القاعدة · الاستعادة نفسها) — نسبةٌ
/// مختلَقة تكذب، والشريط المتحرّك يقول الحقيقة: «تعمل، ولا أعرف كم بقي».
class JobProgressCard extends StatelessWidget {
  const JobProgressCard({super.key, required this.job});

  final JobInfo job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.action(context);
    final p = job.percent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${job.title} — جارية',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (p != null)
                  Text('$p٪', style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p == null ? null : p / 100,
                minHeight: 6,
                color: accent,
                backgroundColor: theme.dividerColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(job.stage ?? '…', style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color)),
            const SizedBox(height: 4),
            Text(
              'العملية تجري في الخادم — يمكنك مغادرة هذه الشاشة أو إغلاق المتصفّح، ولن تتوقّف.',
              style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// حوارُ متابعةٍ لا يُغلق باللمس — لعمليةٍ ينتظرها المستخدم في مكانه (حذف شركة).
///
/// يعيد حالة العملية الأخيرة، أو يرمي `ApiException` حين تضيع المتابعة.
Future<JobInfo> showJobProgressDialog(
    BuildContext context, Future<JobInfo> Function(void Function(JobInfo) onUpdate) watch, JobInfo start) {
  final notifier = ValueNotifier<JobInfo>(start);
  final done = Completer<JobInfo>();
  // ⚠️ **يُلتقط قبل أيّ انتظار** — السياق قد لا يبقى صالحاً حين تنتهي العملية.
  final nav = Navigator.of(context, rootNavigator: true);

  watch((j) => notifier.value = j).then((j) {
    if (!done.isCompleted) done.complete(j);
  }, onError: (Object e, StackTrace s) {
    if (!done.isCompleted) done.completeError(e, s);
  }).whenComplete(() {
    if (nav.canPop()) nav.pop();
  });

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ValueListenableBuilder<JobInfo>(
            valueListenable: notifier,
            builder: (_, j, _) => JobProgressCard(job: j),
          ),
        ),
      ),
    ),
  );
  // ⚠️ **لا `dispose` للمُبلّغ هنا**: الحوار يُغلق بحركةٍ لها زمن، والمنشئ فيه يستمع حتى
  //    تنتهي — والتخلّص منه قبلها يرمي في وضع التصحيح. يجمعه جامعُ المهملات.
  return done.future;
}
