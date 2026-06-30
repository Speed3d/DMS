import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import 'change_password_screen.dart';
import 'archive_list_screen.dart';
import 'dashboard_screen.dart';
import 'offline_drafts_screen.dart';
import 'outgoing_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'users_screen.dart';
import 'backup_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

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
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('الرئيسية')),
      const NavigationRailDestination(icon: Icon(Icons.cloud_off), label: Text('أوفلاين')),
      const NavigationRailDestination(icon: Icon(Icons.outbox), label: Text('الصادر')),
      const NavigationRailDestination(icon: Icon(Icons.folder_copy), label: Text('الأرشيف')),
      const NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('التقارير')),
      const NavigationRailDestination(icon: Icon(Icons.settings), label: Text('الإعدادات')),
      if (canManageUsers)
        const NavigationRailDestination(icon: Icon(Icons.people), label: Text('المستخدمون')),
      if (isSuper)
        const NavigationRailDestination(icon: Icon(Icons.backup), label: Text('النسخ الاحتياطي')),
    ];
    if (_index >= pages.length) _index = 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام إدارة الوثائق — DEN LAND'),
        actions: [
          Center(child: Text('${auth.fullName} (${_roleLabel(auth.role)})')),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (v) {
              if (v == 'password') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen()));
              } else if (v == 'switch') {
                _switchCompany();
              } else if (v == 'logout') {
                ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'password', child: Text('تغيير كلمة المرور')),
              if (auth.isSuperAdmin)
                const PopupMenuItem(value: 'switch', child: Text('تبديل الشركة')),
              const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }

  void _switchCompany() async {
    final api = ref.read(apiClientProvider);
    final companies = await api.companies();
    if (!mounted) return;
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

  String _roleLabel(String r) => switch (r) {
        'SuperAdmin' => 'سوبر أدمن',
        'President' => 'رئيس الشركة',
        'Manager' => 'مدير',
        'Employee' => 'موظف',
        _ => 'قارئ',
      };
}
