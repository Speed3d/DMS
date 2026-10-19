import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/app_version.dart';
import '../core/session.dart';
import '../core/system_status.dart';
import '../core/theme.dart';
import '../models_system.dart';

/// سطر الإصدار أسفل القائمة الجانبية — والنقر يفتح «حول النظام» (ADR-054).
///
/// 🔴 **للسوبر أدمن: يتلوّن إن اختلف إصدار الواجهة عن الخادم** — علامةُ تحديثٍ ناقص (نُشر أحدهما
/// دون الآخر). ولغيره لا تنبيه: ليس بيده ما يفعله.
class VersionTag extends ConsumerWidget {
  const VersionTag({super.key, this.uiVersion = kAppVersion});

  /// إصدار الواجهة — يُمرَّر في الاختبار، والافتراض ما خُبز عند البناء.
  final String uiVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuper = ref.watch(sessionProvider).auth?.isSuperAdmin == true;
    final server = ref.watch(systemStatusProvider).serverVersion;
    final mismatch = isSuper && versionsDiffer(uiVersion, server);
    final color = mismatch ? AppColors.goldBright : const Color(0xFF7F93B5);
    // Hint: في بيئة التطوير (flutter run بدون dart-define) يكون uiVersion فارغاً، فنقرأ رقم الإصدار من الخادم (server) ليظهر 0.17.0 بدلاً من «نسخة تطوير».
    final displayVersion = uiVersion.isNotEmpty ? uiVersion : (server ?? '');

    return Tooltip(
      message: mismatch ? 'الواجهة $uiVersion والخادم $server — تحديثٌ لم يكتمل' : 'حول النظام',
      child: InkWell(
        key: const Key('version-tag'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(context: context, builder: (_) => AboutSystemDialog(uiVersion: uiVersion)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mismatch ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(appVersionLabel(displayVersion),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «حول النظام» — يعرض للسوبر أدمن كافة التفاصيل التقنية (الواجهة، الخادم، الـcommit، وقت البناء، والمهاجرات)،
/// بينما يعرض لبقية الأدوار (رئيس، مدير، موظف، قارئ) «حول النظام 0.17.0» فقط بدون أي تفاصيل تقنية.
class AboutSystemDialog extends ConsumerStatefulWidget {
  const AboutSystemDialog({super.key, this.uiVersion = kAppVersion, this.uiCommit = kAppCommit});
  final String uiVersion;
  final String uiCommit;

  @override
  ConsumerState<AboutSystemDialog> createState() => _AboutSystemDialogState();
}

class _AboutSystemDialogState extends ConsumerState<AboutSystemDialog> {
  Future<SystemAboutInfo>? _about;

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(sessionProvider).auth?.isSuperAdmin == true;
    final serverVersion = ref.watch(systemStatusProvider).serverVersion;
    final effectiveVersion = widget.uiVersion.isNotEmpty ? widget.uiVersion : (serverVersion ?? '');

    // Hint: للمستخدم العادي (رئيس، مدير، موظف، قارئ) نعرض فقط «حول النظام <الإصدار>»
    //       بدون أي تفاصيل تقنية أخرى (لا commit، ولا وقت بناء الخادم، ولا المهاجرات).
    if (!isSuper) {
      final titleText = effectiveVersion.isEmpty ? 'حول النظام' : 'حول النظام $effectiveVersion';
      return AlertDialog(
        icon: Icon(Icons.info_outline_rounded, color: AppColors.action(context), size: 32),
        title: Text(titleText, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.action(context),
              foregroundColor: AppColors.onAction(context),
            ),
            child: const Text('حسناً'),
          ),
        ],
      );
    }

    // Hint: للسوبر أدمن وحده (المالك/المطوّر) نطلب تفاصيل الخادم الكاملة (الـcommit، وقت البناء، والمهاجرات).
    _about ??= ref.read(apiClientProvider).systemAbout();

    return AlertDialog(
      icon: Icon(Icons.info_outline_rounded, color: AppColors.action(context), size: 32),
      title: const Text('حول النظام'),
      content: SizedBox(
        width: 380,
        child: FutureBuilder<SystemAboutInfo>(
          future: _about,
          builder: (context, snap) {
            final a = snap.data;
            final rows = <(String, String)>[
              ('الواجهة', _withCommit(appVersionLabel(widget.uiVersion), widget.uiCommit)),
              if (a != null) ('الخادم', _withCommit('الإصدار ${a.version}', a.commit ?? '')),
              if (a?.builtAt != null) ('بناء الخادم', DateFormat('yyyy-MM-dd HH:mm').format(a!.builtAt!)),
              if (a != null) ('قاعدة البيانات', '${a.migrationCount} مهاجرة — آخرُها ${a.appliedMigration ?? '—'}'),
            ];
            final differ = a != null && versionsDiffer(widget.uiVersion, a.version);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 110, child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700))),
                        Expanded(child: SelectableText(r.$2)),
                      ],
                    ),
                  ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (snap.hasError)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('تعذّر سؤال الخادم عن إصداره.', style: TextStyle(color: AppColors.warn)),
                  ),
                if (differ) ...[
                  const SizedBox(height: 10),
                  _Warning('الواجهة والخادم من إصدارين مختلفين — أكمل التحديث (انشر الطرف الآخر) ثم أعد تحميل الصفحة.'),
                ],
                if (a != null && !a.migrationsUpToDate) ...[
                  const SizedBox(height: 10),
                  _Warning('في الكود مهاجرةٌ لم تُطبَّق على القاعدة (${a.latestMigration}) — أعد تشغيل الخدمة.'),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.action(context),
            foregroundColor: AppColors.onAction(context),
          ),
          child: const Text('حسناً'),
        ),
      ],
    );
  }

  static String _withCommit(String label, String commit) => commit.isEmpty ? label : '$label ($commit)';
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: const TextStyle(color: AppColors.warn, height: 1.6)),
      );
}
