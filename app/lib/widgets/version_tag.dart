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
                child: Text(appVersionLabel(uiVersion),
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

/// «حول النظام» — إصدار الواجهة والخادم والـcommit ولحظة البناء وآخر مهاجرة.
class AboutSystemDialog extends ConsumerStatefulWidget {
  const AboutSystemDialog({super.key, this.uiVersion = kAppVersion, this.uiCommit = kAppCommit});
  final String uiVersion;
  final String uiCommit;

  @override
  ConsumerState<AboutSystemDialog> createState() => _AboutSystemDialogState();
}

class _AboutSystemDialogState extends ConsumerState<AboutSystemDialog> {
  late final Future<SystemAboutInfo> _about = ref.read(apiClientProvider).systemAbout();

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(sessionProvider).auth?.isSuperAdmin == true;
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
              if (a != null && isSuper) ('قاعدة البيانات', '${a.migrationCount} مهاجرة — آخرُها ${a.appliedMigration ?? '—'}'),
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
                // 🔴 للسوبر أدمن وحده — هو مَن ينشر، وبيده الإصلاح.
                if (isSuper && differ) ...[
                  const SizedBox(height: 10),
                  _Warning('الواجهة والخادم من إصدارين مختلفين — أكمل التحديث (انشر الطرف الآخر) ثم أعد تحميل الصفحة.'),
                ],
                if (isSuper && a != null && !a.migrationsUpToDate) ...[
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
