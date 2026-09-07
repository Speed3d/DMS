import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../models.dart';
import 'reports_activity_tab.dart';
import 'reports_detail_tabs.dart';
import 'reports_tasks_tab.dart';

/// شاشة التقارير — **تبويبات تتبع صلاحيات المستخدم** (ADR-031).
///
/// 🔐 التبويب لا يظهر إن كانت نقطتُه سترّد 403: النشاط لرئيس الشركة فأعلى، والتفصيليان
/// لمن يملك قسم وحدتهما مع قسم التقارير. **بندٌ يقود إلى 403 أسوأ من إخفائه** — القاعدة
/// نفسها المتّبعة في أقسام الموظفين والرواتب.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

/// 🔴 **التبويب المالي مخفيّ بقرار المالك (2026-08-12).**
///
/// سببه أن **المبالغ تُسجَّل في الصادر وحده** — لا في الوارد ولا في الأرشيف — فالتقرير
/// المالي (صادر + أرشيف) صار **نسخةً أفقر من «الصادر التفصيلي»**: يعرض المبالغ نفسها بلا
/// حالةٍ ولا مُنشئ ولا معتمِد. **وتقريران يقولان الشيء نفسه أسوأ من واحد** — يسأل قارئهما
/// أيّهما الصحيح حين يختلفان.
///
/// ⚠️ **مخفيّ لا محذوف**: النقاط الثلاث في `ReportsController` باقيةٌ ومختبَرة (ومعيار
/// القبول الثالث «التقرير المالي بالدينار» يبقى مستوفى)، والإظهار **تغييرُ هذا السطر وحده** —
/// نظير `_showWordExport` في تفاصيل الصادر (G9).
const bool kShowFinancialTab = false;

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);

    // ⚠️ تُبنى القائمة من الصلاحيات في كل بناء — فتبديل الشركة (ADR-017) يعيد حسابها،
    //    ولا يبقى تبويبٌ من شركةٍ سابقة معروضاً.
    final tabs = <({String title, IconData icon, Widget body})>[
      if (kShowFinancialTab)
        (title: 'المالي', icon: Icons.payments_outlined, body: const FinancialReportTab()),
      if (s.canSeeOutgoingDetailReport)
        (title: 'الصادر التفصيلي', icon: Icons.outbox_outlined, body: const OutgoingDetailTab()),
      if (s.canSeeArchiveDetailReport)
        (title: 'الأرشيف التفصيلي', icon: Icons.inventory_2_outlined, body: const ArchiveDetailTab()),
      if (s.canSeeTasksReport)
        (title: 'المهام', icon: Icons.task_alt, body: const TasksDetailTab()),
      if (s.canSeeActivityReport)
        (title: 'النشاط', icon: Icons.history, body: const ActivityReportTab()),
    ];

    // 🔴 **حالةٌ صارت ممكنة بعد إخفاء المالي**: مَن يملك قسم «التقارير» وحده بلا الصادر ولا
    //    الأرشيف لا يبقى له تبويب. وشاشةٌ فارغة تُقرأ عطلاً — فتُقال الحقيقة صراحةً.
    if (tabs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              const Text('لا تقارير متاحة بصلاحياتك الحالية.', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text(
                'كل تقرير يحتاج قسم «التقارير» مع قسم وحدته — راجع مسؤول النظام.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (tabs.length == 1) return tabs.first.body;

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(icon: Icon(t.icon, size: 18), text: t.title)],
            ),
          ),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.body])),
        ],
      ),
    );
  }
}

/// التقرير المالي — **لم يتغيّر منطقه** (تقريرٌ يعمل ومُثبَتٌ حيّاً لا يُعاد كتابته).
class FinancialReportTab extends ConsumerStatefulWidget {
  const FinancialReportTab({super.key});
  @override
  ConsumerState<FinancialReportTab> createState() => _FinancialState();
}

class _FinancialState extends ConsumerState<FinancialReportTab> {
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
      await downloadBytes(bytes, reportFileName('financial-report', format), reportMime(format));
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
          Text('التقرير المالي', style: Theme.of(context).textTheme.headlineSmall),
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
                  // Hint: «الوارد» أُزيل من مصادر التقرير المالي بقرار المالك (2026-07-25).
                  DropdownMenuItem(value: 'All', child: Text('الكل')),
                  DropdownMenuItem(value: 'Outgoing', child: Text('الصادر')),
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
    if (r.rows.isEmpty) return const Center(child: Text('لا توجد سجلات مالية ضمن الفلاتر المحددة.'));
    return Column(
      children: [
        Expanded(
          child: ReportTable(
            minWidth: 900,
            columns: const ['المصدر', 'الرقم', 'التاريخ', 'الجهة', 'المبلغ', 'بالدينار'],
            rows: [
              for (final row in r.rows)
                [
                  row.source,
                  row.number,
                  DateFormat('yyyy-MM-dd').format(row.date),
                  row.entityName,
                  row.amount == null ? '—' : '${row.amount} ${row.currency == 'USD' ? 'دولار' : 'دينار'}',
                  row.amountInIqd == null ? '—' : fmtNum(row.amountInIqd!),
                ],
            ],
          ),
        ),
        SummaryBar(items: [
          'عدد السجلات: ${r.count}',
          'الإجمالي بالدينار العراقي: ${fmtNum(r.totalIqd)} د.ع',
        ]),
      ],
    );
  }
}

// ══════════════════ عناصر مشتركة بين التبويبات ══════════════════
//
// 🔴 **مشتركة عمداً**: أربعة تقارير بأربع نسخٍ من الجدول والتصدير والملخّص تعني أربعة
//    أماكن يُصلَح فيها فيضُ التخطيط والتنسيق — وهو نمط «القاعدة المنسوخة» في الواجهة.

String fmtNum(num n) =>
    n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

String reportFileName(String base, String format) => format == 'pdf' ? '$base.pdf' : '$base.xlsx';

String reportMime(String format) => format == 'pdf'
    ? 'application/pdf'
    : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class DateFilterButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  const DateFilterButton({super.key, required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100));
          if (d != null) onPick(d);
        },
        icon: const Icon(Icons.event),
        label: Text(value == null ? label : DateFormat('yyyy-MM-dd').format(value!)),
      );
}

class ExportButtons extends StatelessWidget {
  final Future<void> Function(String format) onExport;
  const ExportButtons({super.key, required this.onExport});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
              onPressed: () => onExport('pdf'),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('تصدير PDF')),
          OutlinedButton.icon(
              onPressed: () => onExport('excel'),
              icon: const Icon(Icons.table_chart),
              label: const Text('تصدير Excel')),
        ],
      );
}

/// جدول تقريرٍ بأعمدة نصّية — **يمرّر أفقياً تحت `minWidth`** بدل أن يفيض.
///
/// ⚠️ الفيض تحت العرض الضيّق عطبٌ متكرّر في هذا المستودع (G12 وجدول الرواتب)، وعلاجه
/// الثابت: تمريرٌ أفقيّ بحدٍّ أدنى **محسوبٍ من عدد الأعمدة** لا مكتوبٍ بيد لكل جدول.
class ReportTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;
  final double minWidth;
  const ReportTable({super.key, required this.columns, required this.rows, this.minWidth = 900});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(builder: (context, constraints) {
        final table = DataTable(
          columns: [for (final c in columns) DataColumn(label: Text(c))],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                for (var i = 0; i < columns.length; i++)
                  // خليّةٌ ناقصة تُزحزح الجدول كلَّه — نملأ الفراغ بدل أن نكسر المحاذاة.
                  DataCell(Text(i < r.length ? r[i] : '')),
              ]),
          ],
        );
        Widget content = SizedBox(width: double.infinity, child: table);
        if (constraints.maxWidth < minWidth) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(constraints: BoxConstraints(minWidth: minWidth), child: table),
          );
        }
        return SingleChildScrollView(scrollDirection: Axis.vertical, child: content);
      }),
    );
  }
}

/// شريط الملخّص أسفل التقرير — `Wrap` لا `Row` لئلا يفيض تحت العرض الضيّق.
class SummaryBar extends StatelessWidget {
  final List<String> items;
  const SummaryBar({super.key, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (final t in items)
              Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          ],
        ),
      );
}
