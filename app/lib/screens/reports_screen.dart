import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _State();
}

class _State extends ConsumerState<ReportsScreen> {
  DateTime? _from, _to;
  int? _entityId;
  String _source = 'All';
  List<EntityModel> _entities = [];
  FinancialReport? _report;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _entities = await ref.read(apiClientProvider).entities();
    } catch (_) {}
    await _run();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      _report = await ref.read(apiClientProvider).financialReport(
          from: _from, to: _to, entityId: _entityId, source: _source);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).financialReportFile(
          format, from: _from, to: _to, entityId: _entityId, source: _source);
      final name = format == 'pdf' ? 'financial-report.pdf' : 'financial-report.xlsx';
      final mime = format == 'pdf'
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      await downloadBytes(bytes, name, mime);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('التقرير المالي', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          // الفلاتر
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _from ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _from = d);
              },
              icon: const Icon(Icons.event),
              label: Text(_from == null ? 'من تاريخ' : DateFormat('yyyy-MM-dd').format(_from!)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _to ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _to = d);
              },
              icon: const Icon(Icons.event),
              label: Text(_to == null ? 'إلى تاريخ' : DateFormat('yyyy-MM-dd').format(_to!)),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int?>(
                initialValue: _entityId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الجهة', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الجهات')),
                  ..._entities.map((e) => DropdownMenuItem<int?>(value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _entityId = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(labelText: 'المصدر', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('الكل')),
                  DropdownMenuItem(value: 'Outgoing', child: Text('الصادر')),
                  DropdownMenuItem(value: 'Incoming', child: Text('الوارد')),
                  DropdownMenuItem(value: 'Archive', child: Text('الأرشيف')),
                ],
                onChanged: (v) => setState(() => _source = v ?? 'All'),
              ),
            ),
            FilledButton.icon(onPressed: _busy ? null : _run, icon: const Icon(Icons.search), label: const Text('عرض')),
            if ((_from != null || _to != null || _entityId != null))
              TextButton(onPressed: () { setState(() { _from = null; _to = null; _entityId = null; }); _run(); }, child: const Text('مسح الفلاتر')),
          ]),
          const SizedBox(height: 8),
          if (_report != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: () => _export('pdf'), icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF')),
                OutlinedButton.icon(onPressed: () => _export('excel'), icon: const Icon(Icons.table_chart), label: const Text('تصدير Excel')),
              ],
            ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          Expanded(child: _busy ? const Center(child: CircularProgressIndicator()) : _results()),
        ],
      ),
    );
  }

  Widget _results() {
    final r = _report;
    if (r == null) return const SizedBox.shrink();
    if (r.rows.isEmpty) return const Center(child: Text('لا توجد سجلات مالية ضمن الفلاتر المحددة.'));
    return Column(
      children: [
        Expanded(
          child: Card(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final table = DataTable(
                  columns: const [
                    DataColumn(label: Text('المصدر')),
                    DataColumn(label: Text('الرقم')),
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('الجهة')),
                    DataColumn(label: Text('المبلغ')),
                    DataColumn(label: Text('بالدينار')),
                  ],
                  rows: [
                    for (final row in r.rows)
                      DataRow(cells: [
                        DataCell(Text(row.source)),
                        DataCell(Text(row.number)),
                        DataCell(Text(DateFormat('yyyy-MM-dd').format(row.date))),
                        DataCell(Text(row.entityName)),
                        DataCell(Text(row.amount == null ? '—' : '${row.amount} ${row.currency == 'USD' ? 'دولار' : 'دينار'}')),
                        DataCell(Text(row.amountInIqd == null ? '—' : _fmt(row.amountInIqd!))),
                      ]),
                  ],
                );
                
                Widget content = SizedBox(width: double.infinity, child: table);
                if (constraints.maxWidth < 900) {
                  content = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 900),
                      child: table,
                    ),
                  );
                }
                
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: content,
                );
              }
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            children: [
              Text('عدد السجلات: ${r.count}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('الإجمالي بالدينار العراقي: ${_fmt(r.totalIqd)} د.ع',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
            ],
          ),
        ),
      ],
    );
  }
}
