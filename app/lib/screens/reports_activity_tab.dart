import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';
import 'reports_screen.dart';

/// تبويب **تقرير النشاط** من سجلّ التدقيق (ADR-031).
///
/// 🔐 لا يُبنى أصلاً إلا إذا كان `canSeeActivityReport` — والخادم يحرسه ثانيةً بـ403.
class ActivityReportTab extends ConsumerStatefulWidget {
  const ActivityReportTab({super.key});
  @override
  ConsumerState<ActivityReportTab> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<ActivityReportTab> {
  DateTime? _from, _to;
  int? _userId;
  String? _action, _entityType;
  int _take = 500;

  ActivityReport? _report;
  AuditVocabulary? _vocab;
  List<UserModel> _users = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = ref.read(apiClientProvider);
    // ⚠️ المفردات من الخادم لا مثبَّتةً هنا: قائمةٌ في الواجهة تشيخ كلّما أُضيف فعلٌ جديد،
    //    فيبحث المالك عن عمليةٍ يراها في السطور ولا يجدها في الفلتر.
    try { _vocab = await api.auditVocabulary(); } catch (_) {}
    try { _users = await api.users(); } catch (_) {}
    await _run();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      _report = await ref.read(apiClientProvider).activityReport(
          from: _from, to: _to, userId: _userId, action: _action, entityType: _entityType, take: _take);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).activityReportFile(format,
          from: _from, to: _to, userId: _userId, action: _action, entityType: _entityType, take: _take);
      await downloadBytes(bytes, reportFileName('activity-report', format), reportMime(format));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  void _clear() {
    setState(() { _from = null; _to = null; _userId = null; _action = null; _entityType = null; });
    _run();
  }

  bool get _hasFilters =>
      _from != null || _to != null || _userId != null || _action != null || _entityType != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تقرير النشاط', style: Theme.of(context).textTheme.headlineSmall),
          const Text('مَن فعل ماذا ومتى — من سجلّ التدقيق.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateFilterButton(label: 'من تاريخ', value: _from, onPick: (d) => setState(() => _from = d)),
            DateFilterButton(label: 'إلى تاريخ', value: _to, onPick: (d) => setState(() => _to = d)),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<int?>(
                initialValue: _userId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المستخدم', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل المستخدمين')),
                  ..._users.map((u) => DropdownMenuItem<int?>(
                      value: u.userId, child: Text(u.fullName, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _userId = v),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                initialValue: _action,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'العملية', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('كل العمليات')),
                  ...?_vocab?.actions.map((a) => DropdownMenuItem<String?>(
                      value: a.value, child: Text(a.label, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _action = v),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                initialValue: _entityType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'النوع', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('كل الأنواع')),
                  ...?_vocab?.entities.map((e) => DropdownMenuItem<String?>(
                      value: e.value, child: Text(e.label, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _entityType = v),
              ),
            ),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<int>(
                initialValue: _take,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'عدد السطور', isDense: true),
                items: const [
                  DropdownMenuItem(value: 100, child: Text('100')),
                  DropdownMenuItem(value: 500, child: Text('500')),
                  DropdownMenuItem(value: 2000, child: Text('2000')),
                ],
                onChanged: (v) => setState(() => _take = v ?? 500),
              ),
            ),
            FilledButton.icon(
                onPressed: _busy ? null : _run, icon: const Icon(Icons.search), label: const Text('عرض')),
            if (_hasFilters) TextButton(onPressed: _clear, child: const Text('مسح الفلاتر')),
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
    if (r.rows.isEmpty) return const Center(child: Text('لا نشاط ضمن الفلاتر المحددة.'));

    return Column(
      children: [
        Expanded(
          child: ReportTable(
            minWidth: 1000,
            columns: const ['التاريخ والوقت', 'المستخدم', 'العملية', 'النوع', 'المعرّف', 'التفاصيل'],
            rows: [
              for (final row in r.rows)
                [
                  // ⚠️ الوقت يصل UTC ويُعرض محليّاً — عرضُه كما جاء يُظهر عملَ الصباح فجراً.
                  DateFormat('yyyy-MM-dd HH:mm').format(row.timestamp.toLocal()),
                  row.userName,
                  row.actionLabel,
                  row.entityLabel,
                  row.entityId ?? '—',
                  row.details ?? '—',
                ],
            ],
          ),
        ),
        SummaryBar(items: [
          // 🔴 «المعروض من الإجمالي» لا العدد وحده: قارئٌ يظنّ أنه رأى كل شيء وهو رأى جزءاً
          //    يبني قراره على نقصٍ لا يعلمه.
          if (r.rows.length < r.totalCount)
            'المعروض: ${r.rows.length} من ${r.totalCount}'
          else
            'عدد العمليات: ${r.totalCount}',
          if (r.byAction.isNotEmpty) 'الأكثر: ${r.byAction.first.label} (${r.byAction.first.count})',
          if (r.byUser.isNotEmpty) 'الأنشط: ${r.byUser.first.label} (${r.byUser.first.count})',
        ]),
      ],
    );
  }
}
