import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../core/theme.dart';
import '../core/profile_providers.dart';
import '../core/session.dart';
import '../core/outgoing_providers.dart';
import '../models.dart';
import '../screens/outgoing_detail_screen.dart';
import '../core/incoming_providers.dart';
import '../screens/incoming_detail_screen.dart';

/// Hint: الشريط العلوي (Topbar) المحدث
class Topbar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String subtitle;

  /// 🔴 **يُمرَّر سياق الزرّ لا مجرّد نداء** (بلاغ المالك 2026-08-20): القائمة كانت
  /// تُفتح بموضعٍ ثابت بالأرقام (`RelativeRect.fromLTRB(26, 70, 26, 0)`)، فتظهر في
  /// الجهة المعاكسة للزرّ في واجهةٍ من اليمين لليسار. الموضع يُشتقّ من الزرّ نفسه.
  final void Function(BuildContext anchorContext) onProfileTap;
  final VoidCallback onMenuTap;
  final String? logoUrl;

  const Topbar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onProfileTap,
    required this.onMenuTap,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(sessionProvider).auth;
    // ⚠️ `valueOrNull` لا `when`: الشريط العلوي يُبنى في كل إطار، وانتظارُ الصورة
    //    كان سيُظهر دوّارةً مكان الأفاتار عند كل تنقّل.
    final photo = ref.watch(myPhotoProvider).asData?.value;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMedium = constraints.maxWidth < 900;
          final isSmall = constraints.maxWidth < 600;
          final isVerySmall = constraints.maxWidth < 350;

          return Row(
            children: [
              // Menu Button
              _buildIconButton(
                context,
                icon: Icons.menu_rounded,
                onTap: onMenuTap,
              ),
              const SizedBox(width: 16),
              
              if (logoUrl != null && !isVerySmall) ...[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: NetworkImage(logoUrl!),
                ),
                const SizedBox(width: 12),
              ],

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    if (!isSmall)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              
              if (!isMedium) ...[
                // 🗑️ **حُذف حقل البحث العلويّ** (بلاغ المالك 2026-08-20): لم يكن موصولاً
                //    بشيء — حقلٌ يُكتب فيه ولا يبحث. والبحث الحقيقيّ في كل قسمٍ على حدة،
                //    وصار **حيّاً وأنت تكتب** (`DebouncedSearchField`).

                // QR Verify Button
                OutlinedButton.icon(
                  onPressed: () {}, // TODO: إضافة التحقق من الـ QR
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('تحقق QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textTheme.bodyMedium?.color,
                    side: BorderSide(color: theme.dividerColor, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(width: 14),
              ],

              if (!isVerySmall) ...[
                // Theme Toggle
                _buildIconButton(
                  context,
                  icon: isDark ? Icons.light_mode : Icons.dark_mode,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).toggle();
                  },
                ),
                const SizedBox(width: 8),

                // إشعارات الوارد — تظهر لمن يملك قسم «الوارد» في **الشركة الفعّالة** (ADR-017).
                // Hint: بدون هذا الفحص كان الزرّ يظهر للجميع فارغاً دائماً لمن لا يملك القسم،
                //       فيبدو كأن لا وارد في الشركة بينما الحقيقة أنه لا يراه.
                Consumer(
                  builder: (ctx, ref, child) {
                    if (!ref.watch(sessionProvider).hasModule('Incoming')) return const SizedBox.shrink();
                    final pendingIncList = ref.watch(pendingIncomingProvider).value ?? <IncomingListItem>[];
                    final pendingIncCount = pendingIncList.length;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildIconButton(ctx, icon: Icons.move_to_inbox_rounded, onTap: () {
                          if (pendingIncList.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كتب واردة جديدة')));
                            return;
                          }
                          final box = ctx.findRenderObject() as RenderBox;
                          final overlay = Navigator.of(ctx).overlay!.context.findRenderObject() as RenderBox;
                          showMenu<int>(
                            context: ctx,
                            position: RelativeRect.fromRect(
                              Rect.fromPoints(box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay), 
                                              box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
                              Offset.zero & overlay.size,
                            ),
                            items: pendingIncList.map((d) => PopupMenuItem<int>(
                              value: d.incomingId,
                              child: Row(
                                children: [
                                  const Icon(Icons.inbox_rounded, color: AppColors.gold, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(d.subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text(d.entityName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ).then((id) {
                            if (id != null && ctx.mounted) {
                              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => IncomingDetailScreen(id: id))).then((_) => invalidateIncoming(ref));
                            }
                          });
                        }),
                        if (pendingIncCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.colorScheme.surface, width: 2),
                              ),
                              child: Text(
                                pendingIncCount > 9 ? '+9' : '$pendingIncCount',
                                style: const TextStyle(color: AppColors.navyDeep, fontSize: 10, fontWeight: FontWeight.bold, height: 1),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                // الفاصل يتبع زرّ الوارد: لولا ذلك لبقيت مسافة معلّقة حين يُخفى الزرّ.
                Consumer(
                  builder: (ctx, ref, _) => ref.watch(sessionProvider).hasModule('Incoming')
                      ? const SizedBox(width: 8)
                      : const SizedBox.shrink(),
                ),

                // إشعارات الصادر — تظهر لمن يملك قسم «الصادر» في الشركة الفعّالة (ADR-017).
                Consumer(
                  builder: (ctx, ref, child) {
                    if (!ref.watch(sessionProvider).hasModule('Outgoing')) return const SizedBox.shrink();
                    final pendingList = ref.watch(pendingDraftsProvider).value ?? <OutgoingListItem>[];
                    final pendingCount = pendingList.length;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildIconButton(ctx, icon: Icons.notifications_none, onTap: () {
                          if (pendingList.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد مسودات بانتظار الاعتماد')));
                            return;
                          }
                          final box = ctx.findRenderObject() as RenderBox;
                          final overlay = Navigator.of(ctx).overlay!.context.findRenderObject() as RenderBox;
                          showMenu<int>(
                            context: ctx,
                            position: RelativeRect.fromRect(
                              Rect.fromPoints(box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay), 
                                              box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
                              Offset.zero & overlay.size,
                            ),
                            items: pendingList.map((d) => PopupMenuItem<int>(
                              value: d.outgoingId,
                              child: Row(
                                children: [
                                  const Icon(Icons.pending_actions, color: AppColors.warn, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(d.subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text(d.entityName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ).then((id) {
                            if (id != null && ctx.mounted) {
                              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => OutgoingDetailScreen(id: id))).then((_) => ref.invalidate(pendingDraftsProvider));
                            }
                          });
                        }),
                        if (pendingCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.colorScheme.surface, width: 2),
                              ),
                              child: Text(
                                pendingCount > 9 ? '+9' : '$pendingCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                
                if (!isSmall)
                  Container(width: 1, height: 34, color: theme.dividerColor, margin: const EdgeInsets.symmetric(horizontal: 18))
                else
                  const SizedBox(width: 14),
              ] else ...[
                const SizedBox(width: 14),
              ],

              // User Profile
              Builder(builder: (btnContext) => InkWell(
                onTap: () => onProfileTap(btnContext),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    if (!isSmall) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(auth?.fullName ?? 'المستخدم', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                          Text(_roleLabel(auth?.role ?? ''), style: const TextStyle(fontSize: 11.5, color: AppColors.gold, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(width: 11),
                    ],
                    // 🖼️ **صورته لا حرفُه** (بلاغ المالك 2026-08-20) — والحرف يبقى
                    //    احتياطاً لمن لا صورةَ له أو لم يُربط ببطاقة.
                    _TopbarAvatar(photo: photo, fallback: auth?.fullName ?? ''),
                  ],
                ),
              )),
            ],
          );
        }
      ),
    );
  }

  Widget _buildIconButton(BuildContext context, {required IconData icon, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: theme.textTheme.bodyMedium?.color),
      ),
    );
  }

  String _roleLabel(String r) => switch (r) {
        'SuperAdmin' => 'سوبر أدمن',
        'President' => 'رئيس الشركة',
        'Manager' => 'مدير',
        'Employee' => 'موظف',
        _ => 'قارئ',
      };

  @override
  Size get preferredSize => const Size.fromHeight(70);
}

/// أفاتار الشريط العلوي — الصورة إن وُجدت، وإلا الحرف الأول.
class _TopbarAvatar extends StatelessWidget {
  final Uint8List? photo;
  final String fallback;
  const _TopbarAvatar({required this.photo, required this.fallback});

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: photo == null
              ? const LinearGradient(
                  colors: [Color(0xFF1B3A6B), Color(0xFF0C1B33)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)
              : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
          image: photo == null
              ? null
              : DecorationImage(image: MemoryImage(photo!), fit: BoxFit.cover),
        ),
        alignment: Alignment.center,
        child: photo != null
            ? null
            : Text(
                fallback.isNotEmpty ? fallback[0] : 'U',
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
              ),
      );
}
