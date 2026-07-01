import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';

/// Hint: القائمة الجانبية (Sidebar) المحدثة بتصميم فاخر
class Sidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool canManageUsers;
  final bool isSuperAdmin;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.canManageUsers,
    required this.isSuperAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 266,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF102544), Color(0xFF0A1730)],
        ),
        border: Border(left: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo & Title
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.business, color: AppColors.navy, size: 28),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DEN LAND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15.5, letterSpacing: 0.4)),
                  Text('إدارة الوثائق', style: TextStyle(color: Color(0xFF7F93B8), fontSize: 11.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Main Menu
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('القائمة الرئيسية', style: TextStyle(color: Color(0xFF5E739B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          _buildItem(0, Icons.grid_view_rounded, 'الرئيسية'),
          _buildItem(1, Icons.cloud_off_rounded, 'أوفلاين'),
          _buildItem(2, Icons.send_rounded, 'الصادر', badge: '5'),
          _buildItem(3, Icons.archive_rounded, 'الأرشيف'),
          _buildItem(4, Icons.bar_chart_rounded, 'التقارير المالية'),

          const SizedBox(height: 18),

          // Admin Menu
          if (canManageUsers || isSuperAdmin) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('الإدارة', style: TextStyle(color: Color(0xFF5E739B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            _buildItem(5, Icons.settings_rounded, 'الإعدادات والقوالب'),
            if (canManageUsers) _buildItem(6, Icons.people_alt_rounded, 'المستخدمون'),
            if (isSuperAdmin) _buildItem(7, Icons.security_rounded, 'النسخ الاحتياطي'),
          ],

          const Spacer(),

          // Sync Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x2DBE9A47), Color(0x0DBE9A47)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: AppColors.goldBright, size: 16),
                    SizedBox(width: 8),
                    Text('وضع المزامنة', style: TextStyle(color: AppColors.goldBright, fontWeight: FontWeight.bold, fontSize: 13.5)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('جميع البيانات محدّثة. آخر مزامنة قبل دقيقتين.', style: TextStyle(color: Color(0xFF9DB0D2), fontSize: 12, height: 1.6)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(value: 1.0, backgroundColor: Colors.white10, color: AppColors.goldBright, minHeight: 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(int index, IconData icon, String label, {String? badge}) {
    final isSelected = selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : const Color(0xFFA9BBD9)),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFA9BBD9),
                    fontSize: 14.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(99)),
                  child: Text(badge, style: const TextStyle(color: AppColors.navyDeep, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
