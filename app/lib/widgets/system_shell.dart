import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../core/system_status.dart';
import '../core/theme.dart';
import '../models.dart';

/// يلفّ التطبيق كلَّه (من `MaterialApp.builder`): الشريطان أعلى كل الشاشات، وطبقةُ الصيانة
/// فوقها (ADR-050).
///
/// 🔴 **الطبقة فوق الشاشة لا بدلها** — الشاشة تحتها تبقى حيّةً بما كُتب فيها، فإذا عاد
/// النظام وجد المستخدمُ عمله في مكانه. (استبدالُها بشاشةٍ أخرى كان سيهدم النموذج المفتوح.)
/// ⚠️ **وفوق الملّاح** — فتغطّي الحوارات والشاشات المفتوحة فوق غيرها أيضاً.
class SystemShell extends ConsumerWidget {
  final Widget child;
  const SystemShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(systemStatusProvider);
    final session = ref.watch(sessionProvider);
    final loggedIn = session.isLoggedIn;
    final isSuper = session.auth?.isSuperAdmin ?? false;
    final blocked = blocksUser(view, loggedIn: loggedIn, isSuperAdmin: isSuper);

    return Column(
      children: [
        if (!blocked && loggedIn && isSuper && view.phase == SystemPhase.lockdown)
          LockdownReminderBar(lockdown: view.lockdown),
        if (!blocked && loggedIn && view.announcement.shows)
          AnnouncementBar(announcement: view.announcement),
        Expanded(
          child: Stack(
            children: [
              // ⚠️ `ExcludeFocus` + `AbsorbPointer` لا إزالة: تُحجب الشاشة ولا تُهدم.
              Positioned.fill(
                child: ExcludeFocus(
                  excluding: blocked,
                  child: AbsorbPointer(absorbing: blocked, child: child),
                ),
              ),
              if (blocked) Positioned.fill(child: MaintenanceOverlay(view: view)),
            ],
          ),
        ),
      ],
    );
  }
}

/// لونا الشريط من نوعه — **مصدرٌ واحد** يقرؤه الشريط ومعاينته في الإعدادات.
({Color bg, Color fg, IconData icon}) announcementStyle(BuildContext context, AnnouncementKind kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    AnnouncementKind.warning => (
        bg: dark ? AppColors.warnDark : AppColors.warn,
        fg: dark ? AppColors.navyDeepDark : Colors.white,
        icon: Icons.warning_amber_rounded,
      ),
    AnnouncementKind.info => (
        bg: AppColors.action(context),
        fg: AppColors.onAction(context),
        icon: Icons.campaign_rounded,
      ),
  };
}

/// شريط الإعلان — **بلا زرّ إغلاق** (قرار المالك): السوبر أدمن وحده يُظهره ويُخفيه.
class AnnouncementBar extends StatelessWidget {
  final AnnouncementInfo announcement;
  const AnnouncementBar({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final s = announcementStyle(context, announcement.kind);
    return Material(
      color: s.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(s.icon, color: s.fg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  announcement.text ?? '',
                  style: TextStyle(color: s.fg, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مدّةٌ بالعربية: «ساعة و20 دقيقة» — **دالّةٌ نقيّة** تُختبر.
String arabicDuration(Duration d) {
  if (d.inMinutes < 1) return 'أقل من دقيقة';
  String unit(int n, String one, String two, String few, String many) => switch (n) {
        1 => one,
        2 => two,
        >= 3 && <= 10 => '$n $few',
        _ => '$n $many',
      };
  final days = d.inDays, hours = d.inHours % 24, minutes = d.inMinutes % 60;
  final parts = <String>[
    if (days > 0) unit(days, 'يوم', 'يومين', 'أيام', 'يوماً'),
    if (hours > 0) unit(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة'),
    if (minutes > 0 && days == 0) unit(minutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة'),
  ];
  return parts.join(' و');
}

/// تذكيرٌ أحمر **للسوبر أدمن وحده** أثناء الإيقاف: منذ متى، وزرّ «تشغيل الآن».
///
/// 🔴 **لا يعود النظام للعمل وحده أبداً** (قرار المالك) — فتذكيرٌ ظاهرٌ دائماً يمنع أن ينتهي
/// التحديث ويبقى الموظفون محجوبين لأن أحداً نسي.
class LockdownReminderBar extends ConsumerStatefulWidget {
  final LockdownInfo lockdown;
  const LockdownReminderBar({super.key, required this.lockdown});

  @override
  ConsumerState<LockdownReminderBar> createState() => _LockdownReminderBarState();
}

class _LockdownReminderBarState extends ConsumerState<LockdownReminderBar> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _unlock() async {
    final nav = appNavigatorKey.currentContext;
    if (nav == null) return;
    final ok = await showDialog<bool>(
      context: nav,
      builder: (c) => AlertDialog(
        title: const Text('تشغيل النظام للجميع؟'),
        content: const Text('سيعود كل المستخدمين إلى النظام خلال نصف دقيقة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تشغيل الآن')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).setLockdown(active: false);
      await ref.read(systemStatusProvider.notifier).check();
    } catch (e) {
      final m = appNavigatorKey.currentContext;
      if (m != null && m.mounted) {
        ScaffoldMessenger.maybeOf(m)?.showSnackBar(SnackBar(content: Text('تعذّر التشغيل: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.dangerDark : AppColors.danger;
    final fg = dark ? AppColors.navyDeepDark : Colors.white;
    final since = widget.lockdown.since;
    final elapsed = since == null ? null : DateTime.now().toUtc().difference(since);
    final text = elapsed == null
        ? 'النظام متوقّف عن المستخدمين — أنت وحدك تتصفّحه.'
        : 'النظام متوقّف عن المستخدمين منذ ${arabicDuration(elapsed)} — أنت وحدك تتصفّحه.';

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.pause_circle_filled_rounded, color: fg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  side: BorderSide(color: fg),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('تشغيل الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// طبقة الصيانة — تحجب الشاشة وتشرح السبب، وتختفي وحدها عند العودة.
class MaintenanceOverlay extends ConsumerWidget {
  final SystemView view;
  const MaintenanceOverlay({super.key, required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, title, body) = switch (view.phase) {
      SystemPhase.lockdown => (
          Icons.construction_rounded,
          'النظام متوقّف مؤقتاً',
          view.lockdown.message ?? 'النظام متوقّف للصيانة. سيعود قريباً.',
        ),
      SystemPhase.restoring => (
          Icons.settings_backup_restore_rounded,
          'جارٍ استعادة نسخة احتياطية',
          view.restoreReason ?? 'النظام متوقّف مؤقتاً حتى تنتهي الاستعادة.',
        ),
      _ => (
          Icons.cloud_off_rounded,
          'تعذّر الوصول إلى الخادم',
          'قد يكون النظام قيد التحديث، أو انقطع الاتصال بالإنترنت.',
        ),
    };

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: AppColors.action(context)),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(height: 1.6)),
                  const SizedBox(height: 24),
                  Text(
                    'ما كتبته محفوظٌ على الشاشة — ستعود إليه تلقائياً عند عودة النظام.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  if (view.phase == SystemPhase.unreachable) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => ref.read(systemStatusProvider.notifier).check(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة الآن'),
                    ),
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
