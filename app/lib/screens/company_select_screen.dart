import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../models.dart';

/// اختيار الشركة الفعّالة (للسوبر أدمن فقط) قبل الدخول للنظام.
class CompanySelectScreen extends ConsumerStatefulWidget {
  const CompanySelectScreen({super.key});
  @override
  ConsumerState<CompanySelectScreen> createState() => _State();
}

class _State extends ConsumerState<CompanySelectScreen> {
  late Future<List<Company>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).companies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر الشركة'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            child: const Text('خروج', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<List<Company>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('خطأ: ${snap.error}'));
          }
          final companies = snap.data ?? [];
          if (companies.isEmpty) {
            return const Center(child: Text('لا توجد شركات. أنشئ شركة من الإعدادات أولاً.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: companies
                    .map((c) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.business),
                            title: Text(c.name),
                            subtitle: Text('الرمز: ${c.prefix}'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () =>
                                ref.read(sessionProvider.notifier).setActiveCompany(c.companyId),
                          ),
                        ))
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
