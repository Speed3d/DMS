import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/session.dart';
import '../models.dart';
import 'archive_form_screen.dart';
import 'archive_detail_screen.dart';

class ArchiveListScreen extends ConsumerStatefulWidget {
  const ArchiveListScreen({super.key});
  @override
  ConsumerState<ArchiveListScreen> createState() => _State();
}

class _State extends ConsumerState<ArchiveListScreen> {
  late Future<List<ArchiveListItem>> _future;
  final _search = TextEditingController();
  DateTime? _from, _to;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).archiveList(search: _search.text, from: _from, to: _to);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ArchiveFormScreen()));
          if (created == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('مستند جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _reload(),
                  decoration: const InputDecoration(labelText: 'بحث (عنوان/كلمات/رقم)', prefixIcon: Icon(Icons.search), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _from ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) { _from = d; _reload(); }
                },
                icon: const Icon(Icons.event), label: Text(_from == null ? 'من تاريخ' : DateFormat('yyyy-MM-dd').format(_from!)),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _to ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) { _to = d; _reload(); }
                },
                icon: const Icon(Icons.event), label: Text(_to == null ? 'إلى تاريخ' : DateFormat('yyyy-MM-dd').format(_to!)),
              )),
              if (_from != null || _to != null)
                IconButton(onPressed: () { _from = null; _to = null; _reload(); }, icon: const Icon(Icons.clear)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<ArchiveListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  final items = snap.data ?? [];
                  if (items.isEmpty) return const Center(child: Text('لا توجد مستندات.'));
                  return Card(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        return ListTile(
                          leading: const Icon(Icons.folder, color: Colors.amber),
                          title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(it.bookDate != null ? DateFormat('yyyy-MM-dd').format(it.bookDate!) : '—'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(it.archiveNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (it.amountInIqd != null)
                                Text('${_fmt(it.amountInIqd!)} د.ع', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArchiveDetailScreen(id: it.archiveId)));
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

  String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
