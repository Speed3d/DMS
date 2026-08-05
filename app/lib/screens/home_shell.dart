import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../core/outgoing_providers.dart';
import '../core/incoming_providers.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

import 'change_password_screen.dart';
import 'archive_list_screen.dart';
import 'dashboard_screen.dart';
import 'offline_drafts_screen.dart';
import 'outgoing_list_screen.dart';
import 'incoming_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'users_screen.dart';
import 'backup_screen.dart';
import 'employee_list_screen.dart';
import 'payroll_years_screen.dart';

import '../models.dart';

final activeCompanyProvider = FutureProvider.autoDispose<Company?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final session = ref.watch(sessionProvider);
  if (session.effectiveCompanyId == null) return null;
  try {
    final companies = await api.companies();
    return companies.where((c) => c.companyId == session.effectiveCompanyId).firstOrNull;
  } catch (_) {
    return null;
  }
});

/// Hint: الهيكل الرئيسي للتطبيق (Shell) الذي يجمع القائمة الجانبية والشريط العلوي مع محتوى الشاشات
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _isSidebarOpen = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      if (MediaQuery.of(context).size.width < 900) {
        _isSidebarOpen = false;
      }
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final auth = session.auth!;
    final canManageUsers = const ['SuperAdmin', 'President', 'Manager'].contains(auth.role);
    final isSuper = auth.isSuperAdmin;

    // قائمة ثابتة المؤشرات (0..10) — الإظهار/الإخفاء يُدار في الـ Sidebar حسب صلاحيات الأقسام.
    //
    // 🔴 **الوحدات الجديدة تُلحَق في آخر القائمة ولا تُدرَج في وسطها** مهما بدا موضعها
    //    الطبيعي أنسب: المؤشرات مرجعيةٌ ثابتة يعتمد عليها `_isIndexAllowed` وعناوين الشاشات
    //    و`Sidebar`، **و`dashboard_screen` ينادي `onNavigate(2)` و`(3)` برقم حرفي**. إدراج
    //    بندٍ في الوسط يُزيح كل ما بعده فيفتح زرٌّ شاشةً غير التي يَعِد بها.
    //    الترتيب **البصري** يحدّده الشريط الجانبي وحده، لا ترتيب هذه القائمة.
    final pages = <Widget>[
      DashboardScreen(onNavigate: (i) => setState(() => _index = i)),
      const OfflineDraftsScreen(),
      const OutgoingListScreen(),
      const IncomingListScreen(),
      const ArchiveListScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
      const UsersScreen(),
      const BackupScreen(),
      const EmployeeListScreen(),   // 9  — الموظفون
      const PayrollYearsScreen(),   // 10 — الرواتب
    ];

    if (_index >= pages.length) _index = 0;
    // إن كان القسم الحالي غير مسموح، عُد للرئيسية.
    if (!_isIndexAllowed(_index, session, canManageUsers, isSuper)) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          // Hint: القائمة الجانبية (Sidebar) مع حركة انزلاق ناعمة
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isSidebarOpen ? 266 : 0,
            child: ClipRect(
              child: OverflowBox(
                minWidth: 266,
                maxWidth: 266,
                alignment: Alignment.centerRight,
                child: Sidebar(
                  selectedIndex: _index,
                  onSelected: (i) => setState(() => _index = i),
                  canManageUsers: canManageUsers,
                  isSuperAdmin: isSuper,
                  modules: session.modules,
                  canSeeEmployees: session.canSeeEmployees,
                  canSeePayroll: session.canSeePayroll,
                ),
              ),
            ),
          ),
          
          // Hint: القسم الأيسر (الرئيسي) يحتوي الشريط العلوي + محتوى الصفحة
          Expanded(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, child) {
                    final company = ref.watch(activeCompanyProvider).value;
                    final companyName = company?.name ?? 'جاري التحميل...';
                    final logoUrl = company?.logoImageKey != null && company!.logoImageKey!.isNotEmpty
                        ? '$kApiBaseUrl/companies/${company.companyId}/logo'
                        : null;
                    return Topbar(
                      title: '${_getPageTitle(_index, canManageUsers, isSuper)} - $companyName',
                      subtitle: _getPageSubtitle(_index, canManageUsers, isSuper),
                      logoUrl: logoUrl,
                      onProfileTap: _showProfileMenu,
                      onMenuTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                    );
                  },
                ),
                Expanded(
                  child: ClipRect( // لمنع المحتوى من التجاوز
                    child: Consumer(
                      builder: (context, ref, child) {
                        final session = ref.watch(sessionProvider);
                        return KeyedSubtree(
                          key: ValueKey(session.effectiveCompanyId),
                          child: pages[_index],
                        );
                      }
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu() {
    final auth = ref.read(sessionProvider).auth!;
    // عرض القائمة أسفل ملف المستخدم
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(26, 70, 26, 0),
      items: [
        const PopupMenuItem(value: 'password', child: Text('تغيير كلمة المرور')),
        if (auth.isSuperAdmin || auth.companyIds.length > 1) const PopupMenuItem(value: 'switch', child: Text('تبديل الشركة')),
        const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج', style: TextStyle(color: Colors.red))),
      ],
    ).then((v) {
      if (!mounted) return;
      if (v == 'password') {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
      } else if (v == 'switch') {
        _switchCompany();
      } else if (v == 'logout') {
        ref.read(sessionProvider.notifier).logout();
      }
    });
  }

  void _switchCompany() async {
    final api = ref.read(apiClientProvider);
    final companies = await api.companies();
    if (!mounted) return;
    if (!context.mounted) return;
    
    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر الشركة'),
        children: companies
            .map((c) => SimpleDialogOption(
                  onPressed: () {
                    ref.read(sessionProvider.notifier).setActiveCompany(c.companyId);
                    // إبطال مزوّدات الشركة ليُعاد جلبها فوراً بالشركة الجديدة
                    // (يمنع ظهور إشعارات/بيانات الشركة السابقة).
                    invalidateOutgoing(ref);
                    invalidateIncoming(ref);
                    ref.invalidate(activeCompanyProvider);
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: Text('${c.name} (${c.prefix})'),
                ))
            .toList(),
      ),
    );
  }

  bool _isIndexAllowed(int index, SessionState session, bool canManageUsers, bool isSuper) => switch (index) {
        0 || 1 => true,
        2 => session.hasModule('Outgoing'),
        3 => session.hasModule('Incoming'),
        4 => session.hasModule('Archive'),
        5 => session.hasModule('Reports'),
        6 => canManageUsers && session.hasModule('Settings'),
        7 => canManageUsers && session.hasModule('Users'),
        8 => isSuper && session.hasModule('Backup'),
        // ⚠️ **كل مؤشّر بحارسه** (ADR-025): فتحُ قسمٍ لا يفتح الآخر، ولو جُمعا هنا
        //    لفتح قسمُ الموظفين شاشةَ الرواتب — وهو ما جاء الفصل ليمنعه.
        9 => session.canSeeEmployees,
        10 => session.canSeePayroll,
        _ => false,
      };

  String _getPageTitle(int index, bool canManageUsers, bool isSuper) => switch (index) {
        0 => 'الرئيسية',
        1 => 'المسودات (أوفلاين)',
        2 => 'الصادر',
        3 => 'الوارد',
        4 => 'الأرشيف',
        5 => 'التقارير المالية',
        6 => 'الإعدادات والقوالب',
        7 => 'المستخدمون',
        8 => 'النسخ الاحتياطي',
        9 => 'الموظفون',
        10 => 'الرواتب',
        _ => '',
      };

  String _getPageSubtitle(int index, bool canManageUsers, bool isSuper) => switch (index) {
        0 => 'نظرة عامة على نشاط الشركة',
        1 => 'الكتب المحفوظة محلياً بانتظار الاتصال',
        2 => 'إدارة الكتب الصادرة والاعتمادات',
        3 => 'إدارة الكتب الواردة الواردة إلى الشركة',
        4 => 'أرشفة الوثائق السابقة والبحث فيها',
        5 => 'إحصائيات مالية للصادر والوارد',
        6 => 'إدارة إعدادات النظام وقوالب الطباعة',
        7 => 'إدارة صلاحيات وحسابات الموظفين',
        8 => 'أخذ نسخ احتياطية واستعادتها',
        9 => 'بطاقات الموظفين وشروط عملهم في هذه الشركة',
        10 => 'كشوف الرواتب الشهرية وإيصالات الاستلام',
        _ => '',
      };
}
