import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/session.dart';
import 'screens/login_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/company_select_screen.dart';
import 'screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('dms_offline_drafts');
  await Hive.openBox('dms_cache');
  runApp(const ProviderScope(child: DmsApp()));
}

class DmsApp extends ConsumerWidget {
  const DmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'نظام إدارة الوثائق — DEN LAND',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B3D91)),
        useMaterial3: true,
        fontFamily: 'Tahoma',
      ),
      // فرض اتجاه RTL عربي على كامل التطبيق
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const _Gate(),
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    if (!s.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!s.isLoggedIn) return const LoginScreen();
    if (s.auth!.mustChangePassword) return const ChangePasswordScreen(forced: true);
    if (s.needsCompanySelection) return const CompanySelectScreen();
    return const HomeShell();
  }
}
