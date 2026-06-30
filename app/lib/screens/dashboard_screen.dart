import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../models.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _State();
}

class _State extends ConsumerState<DashboardScreen> {
  late Future<List<OutgoingListItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).outgoingList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OutgoingListItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
        final items = snap.data ?? [];
        final drafts = items.where((e) => e.status == 'Draft').length;
        final finals = items.where((e) => e.status == 'Final').length;
        final totalIqd = items.fold<num>(0, (a, e) => a + (e.amountInIqd ?? 0));
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لوحة التحكم', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _card('إجمالي الصادر', '${items.length}', Icons.outbox, Colors.blue),
                  _card('بانتظار الاعتماد', '$drafts', Icons.pending_actions, Colors.orange),
                  _card('معتمدة', '$finals', Icons.verified, Colors.green),
                  _card('إجمالي المبالغ (د.ع)', _fmt(totalIqd), Icons.payments, Colors.teal),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String title, String value, IconData icon, Color color) => SizedBox(
        width: 230,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(title, style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  String _fmt(num n) {
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}
