import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

import 'change_password_screen.dart';
import 'archive_list_screen.dart';
import 'dashboard_screen.dart';
import 'offline_drafts_screen.dart';
import 'outgoing_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'users_screen.dart';
import 'backup_screen.dart';

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
    final auth = ref.watch(sessionProvider).auth!;
    final canManageUsers = const ['SuperAdmin', 'President', 'Manager'].contains(auth.role);
    final isSuper = auth.isSuperAdmin;

    final pages = <Widget>[
      const DashboardScreen(),
      const OfflineDraftsScreen(),
      const OutgoingListScreen(),
      const ArchiveListScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
      if (canManageUsers) const UsersScreen(),
      if (isSuper) const BackupScreen(),
    ];

    if (_index >= pages.length) _index = 0;

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
                ),
              ),
            ),
          ),
          
          // Hint: القسم الأيسر (الرئيسي) يحتوي الشريط العلوي + محتوى الصفحة
          Expanded(
            child: Column(
              children: [
                Topbar(
                  title: _getPageTitle(_index, canManageUsers, isSuper),
                  subtitle: _getPageSubtitle(_index, canManageUsers, isSuper),
                  onProfileTap: _showProfileMenu,
                  onMenuTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                ),
                Expanded(
                  child: ClipRect( // لمنع المحتوى من التجاوز
                    child: pages[_index],
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
        if (auth.isSuperAdmin) const PopupMenuItem(value: 'switch', child: Text('تبديل الشركة')),
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
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: Text('${c.name} (${c.prefix})'),
                ))
            .toList(),
      ),
    );
  }

  String _getPageTitle(int index, bool canManageUsers, bool isSuper) {
    if (index == 0) return 'الرئيسية';
    if (index == 1) return 'المسودات (أوفلاين)';
    if (index == 2) return 'الصادر';
    if (index == 3) return 'الأرشيف';
    if (index == 4) return 'التقارير المالية';
    if (index == 5) return 'الإعدادات والقوالب';
    if (canManageUsers && index == 6) return 'المستخدمون';
    if (isSuper && index == (canManageUsers ? 7 : 6)) return 'النسخ الاحتياطي';
    return '';
  }

  String _getPageSubtitle(int index, bool canManageUsers, bool isSuper) {
    if (index == 0) return 'نظرة عامة على نشاط الشركة';
    if (index == 1) return 'الكتب المحفوظة محلياً بانتظار الاتصال';
    if (index == 2) return 'إدارة الكتب الصادرة والاعتمادات';
    if (index == 3) return 'أرشفة الوثائق السابقة والبحث فيها';
    if (index == 4) return 'إحصائيات مالية للصادر والوارد';
    if (index == 5) return 'إدارة إعدادات النظام وقوالب الطباعة';
    if (canManageUsers && index == 6) return 'إدارة صلاحيات وحسابات الموظفين';
    if (isSuper && index == (canManageUsers ? 7 : 6)) return 'أخذ نسخ احتياطية واستعادتها';
    return '';
  }
}
