import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/session.dart';
import '../models.dart';
import 'outgoing_form_screen.dart';
import 'outgoing_detail_screen.dart';

class OutgoingListScreen extends ConsumerStatefulWidget {
  const OutgoingListScreen({super.key});
  @override
  ConsumerState<OutgoingListScreen> createState() => _State();
}

class _State extends ConsumerState<OutgoingListScreen> {
  late Future<List<OutgoingListItem>> _future;
  String? _status;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).outgoingList(status: _status, search: _search.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const OutgoingFormScreen()));
          if (created == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('كتاب جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _reload(),
                    decoration: const InputDecoration(
                      labelText: 'بحث (الموضوع/الرقم)',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String?>(
                  value: _status,
                  hint: const Text('الكل'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('الكل')),
                    DropdownMenuItem(value: 'Draft', child: Text('مسودّة')),
                    DropdownMenuItem(value: 'Final', child: Text('معتمد')),
                  ],
                  onChanged: (v) { _status = v; _reload(); },
                ),
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<OutgoingListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  final items = snap.data ?? [];
                  if (items.isEmpty) return const Center(child: Text('لا توجد كتب.'));
                  return Card(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final isFinal = it.status == 'Final';
                        return ListTile(
                          leading: Icon(isFinal ? Icons.verified : Icons.edit_note,
                              color: isFinal ? Colors.green : Colors.orange),
                          title: Text(it.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${it.entityName} • ${DateFormat('yyyy-MM-dd').format(it.date)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(it.number ?? 'مسودّة',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (it.amountInIqd != null)
                                Text('${_fmt(it.amountInIqd!)} د.ع',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => OutgoingDetailScreen(id: it.outgoingId)));
                            _reload();
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
