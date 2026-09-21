import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notification_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'case_files_screen.dart';
import 'incoming_detail_screen.dart';
import 'outgoing_detail_screen.dart';
import 'task_detail_screen.dart';

/// شاشة الإشعارات (ADR-038 · وفلترةُ الشركة ADR-046).
///
/// ⚠️ **بلا حارس قسم** — الإشعارات عابرةٌ للأقسام، ومَن فقد قسماً لا يفقد إشعاراته القديمة:
/// هي **واقعاتٌ وقعت له**.
///
/// 🔴 **لكنها ليست عابرةً للشركات (ADR-046 — قرار المالك):** ما تعرضه هذه الشاشة هو
/// إشعاراتُ **الشركة الفعّالة** وحدها، كالصادر والوارد والأرشيف والمهام. والخادم يفرض
/// ذلك بالفلتر العام، **والواجهة مرآةٌ له لا حارسٌ ثانٍ**.
///
/// ✅ **وما يُحجب يُعلَن**: ذيلُ الشاشة يقول «ولديك N في شركة كذا» بزرّ تبديل — فالحجبُ
/// بلا إعلانٍ كان يعني إشعاراً **لا يعلم به صاحبُه ثم يُحذف بعد 90 يوماً**.
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
    final route = _routeFor(n);
    if (route != null) await Navigator.of(context).push(route);
  }

  /// وجهةُ النقر بحسب نوع الكيان — أو `null` لإشعارٍ لا يُفتح.
  ///
  /// 🔴 **كان يعرف `DmsTask` وحده** — فإشعارُ كتابٍ أو معاملةٍ **يصل ولا يُفتح بالنقر**،
  /// وهو **ثامنُ تكرارٍ لنمط «ميزةٌ بلا مدخل»** في هذا المستودع. والخادم يرسل `EntityType`
  /// **ليفتحه العميل** (نصُّ `Notification.cs`)، فتصنيفٌ لا يعرفه الموجّه يُفرغ الحقل من غرضه.
  ///
  /// ⚠️ **ومصدرٌ واحد للقرار**: يستعمله المنطق **والسهمُ** معاً، فلا يظهر سهمٌ يَعِد بفتحٍ
  /// لا يقع، ولا يُفتح ما لا سهم له.
  Route<void>? _routeFor(NotificationModel n) {
    final id = n.entityId;
    if (id == null) return null;

    return switch (n.entityType) {
      'DmsTask' => MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
      'IncomingBook' => MaterialPageRoute(builder: (_) => IncomingDetailScreen(id: id)),
      'OutgoingBook' => MaterialPageRoute(builder: (_) => OutgoingDetailScreen(id: id)),
      'CaseFile' => MaterialPageRoute(builder: (_) => CaseFileDetailScreen(id: id)),
      _ => null,
    };
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
              // 🔴 **الذيل خارج فرع «فارغة»** (ADR-046): الحالة التي وُجد لأجلها هي
              //    **شركةٌ فعّالة بلا إشعارات وأخرى فيها ثلاثة** — فلو وُضع داخل `_list`
              //    لَغاب حين يلزم بالضبط، ورأى المستخدم «لا إشعارات» وهي موجودة.
              data: (page) => Column(
                children: [
                  Expanded(child: page.items.isEmpty ? _empty() : _list(page)),
                  if (page.otherCompanies.isNotEmpty)
                    _otherCompanies(page.otherCompanies),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شريطُ «ولديك إشعاراتٌ في شركاتك الأخرى» — يسدّ ثغرة الفقد الصامت (ADR-046).
  ///
  /// ⚠️ **يُعلن العدد واسم الشركة فقط** — لا عنواناً ولا متناً، فالمحتوى يبقى داخل شركته.
  Widget _otherCompanies(List<CompanyUnread> rows) {
    final theme = Theme.of(context);
    final action = AppColors.action(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.business_rounded, size: 16, color: action),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'إشعاراتٌ في شركاتك الأخرى',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold, color: action),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ⚠️ **`Wrap` لا `Row`**: الاسم والعدد والزرّ تفيض تحت ~400 بكسل.
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text('${r.companyName} — ${r.unread} غير مقروء',
                          style: theme.textTheme.bodyMedium),
                      TextButton(
                        onPressed: _busy ? null : () => _switchTo(r),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('تبديل إليها'),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  /// يبدّل الشركة الفعّالة — **فتُعاد الشاشة بإشعارات تلك الشركة**.
  ///
  /// ⚠️ **ولا يُغلق الشاشة**: المزوّدات تراقب الجلسة فتُعاد بنفسها، وإغلاقُها يعني أن
  /// المستخدم يبدّل ثم يبحث عن الجرس من جديد.
  Future<void> _switchTo(CompanyUnread row) async {
    await ref.read(sessionProvider.notifier).setActiveCompany(row.companyId);
    if (!mounted) return;
    invalidateNotifications(ref);
    setState(() {});
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
          // ⚠️ **السهم من المصدر نفسه** — لا شرطٌ ثانٍ يتباعد عنه.
          if (_routeFor(n) != null)
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
