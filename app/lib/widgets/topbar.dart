import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../core/session.dart';

/// Hint: الشريط العلوي (Topbar) المحدث
class Topbar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final VoidCallback onProfileTap;

  const Topbar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(sessionProvider).auth;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Title & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(subtitle, style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              ],
            ),
          ),
          
          // Search Input
          Container(
            width: 260,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: theme.dividerColor, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'ابحث في الكتب، الأرشيف...',
                      hintStyle: TextStyle(fontSize: 13.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

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

          // Theme Toggle
          _buildIconButton(
            context,
            icon: isDark ? Icons.light_mode : Icons.dark_mode,
            onTap: () {
              ref.read(themeModeProvider.notifier).toggle();
            },
          ),
          const SizedBox(width: 8),

          // Notifications
          Stack(
            children: [
              _buildIconButton(context, icon: Icons.notifications_none, onTap: () {}),
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          
          Container(width: 1, height: 34, color: theme.dividerColor, margin: const EdgeInsets.symmetric(horizontal: 18)),

          // User Profile
          InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(auth?.fullName ?? 'المستخدم', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                    Text(_roleLabel(auth?.role ?? ''), style: const TextStyle(fontSize: 11.5, color: AppColors.gold, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 11),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1B3A6B), Color(0xFF0C1B33)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    auth?.fullName.isNotEmpty == true ? auth!.fullName[0] : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
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
