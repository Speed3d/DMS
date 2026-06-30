import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';

class OfflineDraftsScreen extends ConsumerStatefulWidget {
  const OfflineDraftsScreen({super.key});
  @override
  ConsumerState<OfflineDraftsScreen> createState() => _State();
}

class _State extends ConsumerState<OfflineDraftsScreen> {
  bool _syncing = false;

  void _syncAll(List<Map<String, dynamic>> drafts) async {
    if (drafts.isEmpty) return;
    setState(() => _syncing = true);
    
    int success = 0;
    int failed = 0;
    
    for (final draft in drafts) {
      try {
        await ref.read(apiClientProvider).createOutgoing(draft['payload']);
        await ref.read(localStorageProvider).deleteDraft(draft['id']);
        success++;
      } catch (e) {
        failed++;
      }
    }
    
    if (mounted) {
      setState(() => _syncing = false);
      final msg = failed == 0 ? 'نجحت المزامنة ($success)' : 'تم مزامنة $success وفشل $failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مسودات الأوفلاين'),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('dms_offline_drafts').listenable(),
        builder: (context, box, child) {
          final storage = ref.read(localStorageProvider);
          final drafts = storage.getDrafts();
          
          return Column(
            children: [
              if (drafts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('يوجد ${drafts.length} مسودة لم تتم مزامنتها.'),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _syncing ? null : () => _syncAll(drafts),
                        icon: _syncing 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : const Icon(Icons.sync),
                        label: const Text('مزامنة الكل'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: drafts.isEmpty
                    ? const Center(child: Text('لا توجد مسودات أوفلاين غير مزامنة.', style: TextStyle(color: Colors.grey, fontSize: 16)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: drafts.length,
                        itemBuilder: (context, i) {
                          final draft = drafts[i];
                          final dateStr = draft['createdAt'] ?? '';
                          final date = DateTime.tryParse(dateStr);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(draft['subject'] ?? 'بدون عنوان'),
                              subtitle: Text(date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: _syncing ? null : () => storage.deleteDraft(draft['id']),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
