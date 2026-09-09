import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../core/outgoing_providers.dart';
import '../core/incoming_providers.dart';
import '../core/hr_providers.dart';
import '../core/task_providers.dart';
import '../core/backup_providers.dart';
import '../core/company_providers.dart';
import 'backup_alert.dart';

/// Hint: القائمة الجانبية (Sidebar) المحدثة بتصميم فاخر
class Sidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool canManageUsers;
  final bool isSuperAdmin;
  final List<String> modules;

  /// قسم الموظفين — **القسم مع الدور** (فوق القارئ)، مرآةُ `[RequireHrModule]` (ADR-025).
  final bool canSeeEmployees;

  /// قسم الرواتب — **مستقلٌّ عن الموظفين**: يُمنح أحدهما بلا الآخر.
  final bool canSeePayroll;

  /// قسم المهام — القسم **مع** دورٍ فوق القارئ (ADR-037).
  final bool canSeeTasks;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.canManageUsers,
    required this.isSuperAdmin,
    required this.modules,
    this.canSeeEmployees = false,
    this.canSeePayroll = false,
    this.canSeeTasks = false,
  });

  bool get _showSettings => canManageUsers && modules.contains('Settings');
  bool get _showUsers => canManageUsers && modules.contains('Users');
  bool get _showBackup => isSuperAdmin && modules.contains('Backup');
  bool get _showAdminSection => _showSettings || _showUsers || _showBackup;

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
      // ⚠️ الشريط يمتلئ بحسب صلاحيات المستخدم: السوبر أدمن يرى كل البنود + قسم الإدارة،
      // فيتجاوز المحتوى ارتفاعَ الشاشة على المقاسات المتوسّطة (ظهر كـ«RenderFlex overflowed
      // by 0.8 pixels» على ارتفاع 667). و`Spacer` وحده لا يُنقذ لأنه ينكمش إلى صفر ثم يفيض.
      // الحل: يُمرَّر ارتفاع الشاشة كحدٍّ أدنى داخل ScrollView — فيبقى `Spacer` يدفع بطاقة
      // المزامنة للأسفل حين يتّسع المكان، ويتحوّل الشريط إلى قابل للتمرير حين يضيق.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          // 🏢 **صدرُ القائمة يتبع الشركة الفعّالة** (طلب المالك 2026-09-09): اسمُها
          //    وشعارُها لا اسمَ النظام — **والنظام متعدّد الشركات، فاسمٌ ثابت يجعل موظف
          //    الشركة الثانية يرى شعار الأولى فوق بياناته**. ويتبدّلان بتبديل الشركة لأن
          //    `activeCompanyProvider` يُبطَل حينها.
          //
          // ⚠️ **والسطر الثاني «إدارة الوثائق» يصف النظام لا الشركة** — فيبقى كما هو.
          _CompanyHeader(),
          const SizedBox(height: 24),

          // Main Menu
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('القائمة الرئيسية', style: TextStyle(color: Color(0xFF5E739B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          _buildItem(0, Icons.grid_view_rounded, 'الرئيسية'),
          _buildItem(1, Icons.cloud_off_rounded, 'أوفلاين'),

          if (modules.contains('Outgoing'))
            Consumer(
              builder: (context, ref, child) {
                final countAsync = outgoingCountOf(ref.watch(pendingDraftsProvider));
                final badge = countAsync.whenOrNull(data: (count) => count > 0 ? count.toString() : null);
                return _buildItem(2, Icons.send_rounded, 'الصادر', badge: badge);
              },
            ),
          if (modules.contains('Incoming'))
            Consumer(
              builder: (context, ref, child) {
                final countAsync = incomingCountOf(ref.watch(pendingIncomingProvider));
                final badge = countAsync.whenOrNull(data: (count) => count > 0 ? count.toString() : null);
                return _buildItem(3, Icons.inbox_rounded, 'الوارد', badge: badge);
              },
            ),
          if (modules.contains('Archive')) _buildItem(4, Icons.archive_rounded, 'الأرشيف'),
          if (modules.contains('Reports')) _buildItem(5, Icons.bar_chart_rounded, 'التقارير المالية'),

          // ⚠️ **المؤشران 9 و10 لا 6 و7** — البندان مُلحقان في آخر قائمة الشاشات وموضعُهما
          //    البصري هنا. الترتيب الظاهر يحدّده هذا الملف، لا ترتيب `pages` في `HomeShell`.
          // ⚠️ **بندٌ لكلٍّ بحارسه** (ADR-025): مَن يملك الموظفين وحدهم يرى بندَهم فقط.
          if (canSeeEmployees) _buildItem(9, Icons.groups_2_rounded, 'الموظفون'),
          if (canSeePayroll)
            Consumer(
              builder: (context, ref, child) {
                final countAsync = unpaidMonthsOf(ref.watch(hrSummaryProvider));
                final badge = countAsync.whenOrNull(
                    data: (count) => count > 0 ? count.toString() : null);
                return _buildItem(10, Icons.payments_rounded, 'الرواتب', badge: badge);
              },
            ),

          // ⚠️ **المؤشّر 12** — البند مُلحقٌ في آخر قائمة الشاشات وموضعُه البصري هنا،
          //    والشارة تعرض **المتأخّرة** لا الإجمالي: رقمٌ يعني «يحتاج تدخّلك الآن».
          if (canSeeTasks)
            Consumer(
              builder: (context, ref, child) {
                final countAsync = overdueTasksCountOf(ref.watch(taskSummaryProvider));
                final badge = countAsync.whenOrNull(
                    data: (count) => count > 0 ? count.toString() : null);
                return _buildItem(12, Icons.task_alt_rounded, 'المهام', badge: badge);
              },
            ),

          // ⚠️ **المؤشّر 13** — لوحة الكانبان (الدفعة ٧). بندٌ ثانٍ لا تبويبٌ داخل القائمة
          //    لأن اللوحة **عرضٌ مستقلّ بحجم الشاشة** لا وجهٌ آخر للقائمة، وحارسُها هو
          //    حارسُ المهام نفسه — قسمٌ ودورٌ فوق القارئ.
          if (canSeeTasks)
            _buildItem(13, Icons.view_kanban_outlined, 'لوحة المهام'),

          const SizedBox(height: 18),

          // Admin Menu
          if (_showAdminSection) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('الإدارة', style: TextStyle(color: Color(0xFF5E739B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            if (_showSettings) _buildItem(6, Icons.settings_rounded, 'الإعدادات والقوالب'),
            if (_showUsers) _buildItem(7, Icons.people_alt_rounded, 'المستخدمون'),
            // 🔴 **شارةُ تأخّر النسخة الكاملة** (طلب المالك 2026-09-09) — للسوبر أدمن
            //    وحده، وتحمل **عدد الأيام** بلونٍ يتصاعد مع الإلحاح. والبند نفسه محجوبٌ
            //    عن غيره أصلاً، فالشارة لا تُسرّب شيئاً.
            if (_showBackup)
              Consumer(
                builder: (context, ref, child) {
                  final alert = backupAlertOf(ref.watch(backupCoverageProvider));
                  return _buildItem(8, Icons.security_rounded, 'النسخ الاحتياطي',
                      badge: alert == null ? null : (alert.daysSince?.toString() ?? '!'),
                      badgeColor:
                          alert == null ? null : backupUrgencyColor(alert.urgency));
                },
              ),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int index, IconData icon, String label,
      {String? badge, Color? badgeColor}) {
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
                  // ⚠️ **اللون يُمرَّر ولا يُثبَّت**: شارةُ تأخّر النسخ تتصاعد من الأصفر
                  //    إلى الأحمر، ولونٌ واحد لا يفرّق بين «اقترب» و«مضى شهران».
                  decoration: BoxDecoration(
                      color: badgeColor ?? AppColors.gold,
                      borderRadius: BorderRadius.circular(99)),
                  // ⚠️ **كحليٌّ في الوضعين**: الشارة نفسها ذهبية/ملوّنة، فالنصّ فوقها داكنٌ دائماً.
                  child: Text(badge, style: const TextStyle(color: AppColors.navyDeep, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// صدر القائمة الجانبية — شعار الشركة الفعّالة واسمها.
///
/// ⚠️ **الاسم يتبع سابقة الشريط العلوي حرفياً** (`company?.name ?? 'جاري التحميل...'`) —
/// فاسمان مختلفان لحالةٍ واحدة يجعلان الشاشة تبدو مضطربة أثناء التحميل.
///
/// 🔴 **وفشلُ الشعار لا يُفرغ الصدر**: تعذّرُ تحميل الصورة (شبكةٌ منقطعة · ملفٌّ محذوف)
/// يعود بالأيقونة العامّة — **وصدرٌ فارغ يُقرأ عطلاً في البرنامج لا نقصاً في صورة**.
class _CompanyHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).asData?.value;
    final logoUrl = companyLogoUrl(company);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(4),
          child: logoUrl == null
              ? const Icon(Icons.business, color: AppColors.navy, size: 28)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.business, color: AppColors.navy, size: 28),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                company?.name ?? 'جاري التحميل...',
                // ⚠️ **سطران وقصٌّ** — أسماء الشركات الرسمية طويلة («أرض العرين للتجارة
                //    والمقاولات»)، وسطرٌ واحد يقصّها عند أول كلمتين.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    height: 1.25,
                    letterSpacing: 0.2),
              ),
              const Text('إدارة الوثائق',
                  style: TextStyle(color: Color(0xFF7F93B8), fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}
