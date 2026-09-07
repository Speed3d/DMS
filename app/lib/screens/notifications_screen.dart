import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notification_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'task_detail_screen.dart';

/// شاشة الإشعارات (ADR-038).
///
/// ⚠️ **بلا حارس قسم** — الإشعارات عابرةٌ للأقسام، ومَن فقد قسماً لا يفقد إشعاراته القديمة:
/// هي **واقعاتٌ وقعت له**.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;
  bool _busy = false;

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).markAllNotificationsRead();
      if (mounted) invalidateNotifications(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// النقر: **يَسِم بالمقروء ويفتح الكيان** — لا أحدهما.
  ///
  /// ⚠️ إشعارٌ يُفتح ويبقى غير مقروء يعني عدّاداً لا ينزل مهما قرأ المستخدم، فيتجاهله.
  Future<void> _open(NotificationModel n) async {
    if (!n.isRead) {
      try {
        await ref.read(apiClientProvider).markNotificationRead(n.notificationId);
        if (mounted) invalidateNotifications(ref);
      } catch (_) {
        // فشلُ الوسم لا يمنع الفتح — والمستخدم جاء ليقرأ لا ليَسِم.
      }
    }

    if (!mounted) return;
    final id = n.entityId;
    if (n.entityType == 'DmsTask' && id != null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider(_unreadOnly));

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('تحديد الكل كمقروء'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('غير المقروءة فقط'),
                  selected: _unreadOnly,
                  onSelected: (v) => setState(() => _unreadOnly = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger)),
                ),
              ),
              data: (page) => page.items.isEmpty ? _empty() : _list(page),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 56,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            Text(_unreadOnly ? 'لا إشعارات غير مقروءة' : 'لا إشعارات',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _list(NotificationPage page) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: page.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _row(page.items[i]),
      );

  Widget _row(NotificationModel n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final accent = n.isHigh
        ? (isDark ? AppColors.dangerDark : AppColors.danger)
        : (isDark ? Colors.blueAccent.shade100 : Colors.blueAccent);

    return CustomCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => _open(n),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔵 نقطةٌ لغير المقروء — **الفرق يُرى بطرف العين** لا يُقرأ.
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsetsDirectional.only(top: 6, end: 10),
            decoration: BoxDecoration(
              color: n.isRead ? Colors.transparent : accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
                const SizedBox(height: 4),
                Text(n.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (n.isHigh)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.priority_high_rounded, size: 13, color: accent),
                        Text('عاجل',
                            style: TextStyle(
                                fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
                      ]),
                    Text(_fmt(n.createdAt), style: TextStyle(fontSize: 11, color: muted)),
                  ],
                ),
              ],
            ),
          ),
          if (n.entityType == 'DmsTask')
            Icon(Icons.chevron_left_rounded, size: 18, color: muted),
        ],
      ),
    );
  }

  /// **لحظة** — تُحوَّل بـ`toLocal()` عن حقّ (درس ADR-032).
  static String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}'
        ' ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
