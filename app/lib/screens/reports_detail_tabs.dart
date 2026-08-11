import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';
import 'reports_screen.dart';

/// تبويب **الصادر التفصيلي** — كتبٌ بحالتها ومُنشئها ومعتمِدها (ADR-031).
class OutgoingDetailTab extends ConsumerStatefulWidget {
  const OutgoingDetailTab({super.key});
  @override
  ConsumerState<OutgoingDetailTab> createState() => _OutgoingDetailState();
}

class _OutgoingDetailState extends ConsumerState<OutgoingDetailTab> {
  DateTime? _from, _to;
  int? _entityId;
  String? _status;
  List<EntityModel> _entities = [];
  OutgoingDetailReport? _report;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try { _entities = await ref.read(apiClientProvider).entities(); } catch (_) {}
    await _run();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      _report = await ref.read(apiClientProvider)
          .outgoingDetailReport(from: _from, to: _to, entityId: _entityId, status: _status);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider)
          .outgoingDetailFile(format, from: _from, to: _to, entityId: _entityId, status: _status);
      await downloadBytes(bytes, reportFileName('outgoing-detail', format), reportMime(format));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الصادر التفصيلي', style: Theme.of(context).textTheme.headlineSmall),
          const Text('كل كتب الشركة بحالتها ومَن أنشأها ومَن اعتمدها.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateFilterButton(label: 'من تاريخ', value: _from, onPick: (d) => setState(() => _from = d)),
            DateFilterButton(label: 'إلى تاريخ', value: _to, onPick: (d) => setState(() => _to = d)),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int?>(
                initialValue: _entityId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الجهة', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الجهات')),
                  ..._entities.map((e) => DropdownMenuItem<int?>(
                      value: e.entityId, child: Text(e.name, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _entityId = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحالة', isDense: true),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                  DropdownMenuItem<String?>(value: 'Draft', child: Text('مسودّة')),
                  DropdownMenuItem<String?>(value: 'Final', child: Text('معتمد')),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            FilledButton.icon(
                onPressed: _busy ? null : _run, icon: const Icon(Icons.search), label: const Text('عرض')),
            if (_from != null || _to != null || _entityId != null || _status != null)
              TextButton(
                  onPressed: () {
                    setState(() { _from = null; _to = null; _entityId = null; _status = null; });
                    _run();
                  },
                  child: const Text('مسح الفلاتر')),
          ]),
          const SizedBox(height: 8),
          if (_report != null) ExportButtons(onExport: _export),
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
    if (r.rows.isEmpty) return const Center(child: Text('لا كتب صادرة ضمن الفلاتر المحددة.'));
    return Column(
      children: [
        Expanded(
          child: ReportTable(
            minWidth: 1100,
            columns: const ['الرقم', 'التاريخ', 'الموضوع', 'الجهة', 'الحالة', 'أنشأه', 'اعتمده', 'بالدينار'],
            rows: [
              for (final row in r.rows)
                [
                  row.number,
                  DateFormat('yyyy-MM-dd').format(row.date),
                  row.subject,
                  row.entityName,
                  row.statusLabel,
                  row.createdBy,
                  row.approvedBy ?? '—',
                  row.amountInIqd == null ? '—' : fmtNum(row.amountInIqd!),
                ],
            ],
          ),
        ),
        // 🔴 **المسودّات تُعدّ ولا تُجمع** (ADR-029): الإجمالي مُعنوَنٌ «إجمالي المعتمد»
        //    صراحةً — رقمٌ مخصوص تحت تسميةٍ عامّة هو نصفُ العيب.
        SummaryBar(items: [
          'عدد الكتب: ${r.count}',
          'معتمدة: ${r.approved} · مسودّات: ${r.drafts}',
          'إجمالي المعتمد: ${fmtNum(r.approvedTotalIqd)} د.ع',
        ]),
      ],
    );
  }
}

/// تبويب **الأرشيف التفصيلي** — من عدسة الأرشيف نفسها (وارد مؤرشف + أضابير).
class ArchiveDetailTab extends ConsumerStatefulWidget {
  const ArchiveDetailTab({super.key});
  @override
  ConsumerState<ArchiveDetailTab> createState() => _ArchiveDetailState();
}

class _ArchiveDetailState extends ConsumerState<ArchiveDetailTab> {
  final _searchCtrl = TextEditingController();
  int? _year, _month;
  String _source = 'All';
  ArchiveDetailReport? _report;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      _report = await ref.read(apiClientProvider).archiveDetailReport(
          search: _searchCtrl.text.trim(), year: _year, month: _month, source: _source);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).archiveDetailFile(format,
          search: _searchCtrl.text.trim(), year: _year, month: _month, source: _source);
      await downloadBytes(bytes, reportFileName('archive-detail', format), reportMime(format));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final thisYear = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الأرشيف التفصيلي', style: Theme.of(context).textTheme.headlineSmall),
          const Text('الوارد المؤرشف والأضابير الورقية معاً — بمحور السنة والشهر.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(labelText: 'بحث', isDense: true, prefixIcon: Icon(Icons.search)),
                onSubmitted: (_) => _run(),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<int?>(
                initialValue: _year,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'السنة', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل السنوات')),
                  for (var y = thisYear; y >= thisYear - 10; y--)
                    DropdownMenuItem<int?>(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => _year = v),
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int?>(
                initialValue: _month,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الشهر', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الأشهر')),
                  for (var m = 1; m <= 12; m++) DropdownMenuItem<int?>(value: m, child: Text('$m')),
                ],
                onChanged: (v) => setState(() => _month = v),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _source,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المصدر', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('الكل')),
                  DropdownMenuItem(value: 'Incoming', child: Text('وارد مؤرشف')),
                  DropdownMenuItem(value: 'Paper', child: Text('أضابير ورقية')),
                ],
                onChanged: (v) => setState(() => _source = v ?? 'All'),
              ),
            ),
            FilledButton.icon(
                onPressed: _busy ? null : _run, icon: const Icon(Icons.search), label: const Text('عرض')),
            if (_year != null || _month != null || _source != 'All' || _searchCtrl.text.isNotEmpty)
              TextButton(
                  onPressed: () {
                    setState(() { _year = null; _month = null; _source = 'All'; _searchCtrl.clear(); });
                    _run();
                  },
                  child: const Text('مسح الفلاتر')),
          ]),
          const SizedBox(height: 8),
          if (_report != null) ExportButtons(onExport: _export),
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
    if (r.rows.isEmpty) return const Center(child: Text('لا سجلات أرشيف ضمن الفلاتر المحددة.'));
    return Column(
      children: [
        Expanded(
          // 🔴 **بلا عمود مبالغ (قرار المالك 2026-08-12):** المبالغ تُسجَّل في **الصادر وحده**،
          //    فعمودٌ فارغٌ دائماً في الأرشيف **ليس حيادياً**: يوحي بأن ثمّة مبلغاً يُنتظر
          //    إدخاله، ويسرق عرضاً يحتاجه العنوان. والحقل باقٍ في العقد لو عاد الحكم.
          child: ReportTable(
            minWidth: 1000,
            columns: const ['المصدر', 'الرقم', 'التاريخ', 'العنوان', 'الجهة', 'النوع', 'القسم'],
            rows: [
              for (final row in r.rows)
                [
                  row.sourceLabel,
                  row.number,
                  DateFormat('yyyy-MM-dd').format(row.date),
                  row.title,
                  row.entityName ?? '—',
                  row.documentType ?? '—',
                  row.departments,
                ],
            ],
          ),
        ),
        SummaryBar(items: [
          'عدد السجلات: ${r.count}',
          'وارد مؤرشف: ${r.incomingCount} · أضابير: ${r.paperCount}',
        ]),
      ],
    );
  }
}
