import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/hr_providers.dart';
import '../core/nav_intent.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'employee_detail_screen.dart';
import 'employee_form_screen.dart';
import 'employee_link_dialog.dart';

/// عتبة تضييق شريط الأدوات بلا مِرشَّح الإجازات — **مقيسة بالرسم** في `hr_render_test.dart`.
///
/// 🔴 **تُصدَّر ليستوردها الحارس بدل أن يُعيد كتابتها.** الحارس نسخةٌ مطابقة للشريط، وقد
/// حذّر تعليقُه من أن نسختين تتباعدان — **ورقمان متباعدان أخطر من ودجتين**، لأن الحارس
/// حينها يُثبت سلامة عتبةٍ لا تستعملها الشاشة.
/// **مقيسة:** الفيض يبدأ عند **651**، والزيادة إلى 860 تُبقي لحقل البحث ~200 بكسل يظلّ
/// معها صالحاً للكتابة — وهو الهامش نفسه الذي التزمته العتبة السابقة (426 مقيسة ⇐ 620).
const double kEmpToolbarNarrow = 860;

/// وعتبتُه حين يظهر مِرشَّح «إجازات بانتظار الموافقة» — العنصر الخامس يرفعها.
///
/// **مقيسة:** الفيض يبدأ عند **1101** بالخمسة مجتمعة، وبالهامش نفسه ⇐ 1310.
const double kEmpToolbarNarrowWithChip = 1310;

/// Hint: قائمة موظفي الشركة الفعّالة — بحث وفلتر حالة وجدول عصري (نمط قائمة الأرشيف).
class EmployeeListScreen extends ConsumerStatefulWidget {
  const EmployeeListScreen({super.key});
  @override
  ConsumerState<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends ConsumerState<EmployeeListScreen> {
  late Future<List<EmployeeListItem>> _future;
  final _search = TextEditingController();

  _EmpFilter _filter = _EmpFilter.active;

  /// وضع «مَن ينتظر بتّ إجازته» — يحلّ محلّ الجدول العادي، ولا يُخفي بقية الشاشة.
  bool _pendingLeavesOnly = false;

  @override
  void initState() {
    super.initState();
    // نيّة التنقّل: بطاقة «إجازات بانتظار الموافقة» تفتح الشاشة **على أصحاب الطلبات**.
    // كانت تفتح القائمة كاملةً بلا دلالة، فمع مئة موظف لا سبيل لمعرفة مَن طلب.
    _pendingLeavesOnly = takeNavIntent<PendingLeavesIntent>(ref) != null;
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    final api = ref.read(apiClientProvider);
    // 🔴 **مفكوكو الإسناد لهم نقطةٌ أخرى** (ADR-028): إسنادُهم محذوفٌ ناعماً فيحجبه الفلتر
    //    العام، ونقطتُهم تتجاوزه بشرط شركةٍ مكتوبٍ يدوياً.
    _future = _filter == _EmpFilter.unlinked
        ? api.unlinkedEmployees()
        : api.employees(activeOnly: _filter.activeOnly, search: _search.text);
    setState(() {});
  }

  Future<void> _openForm({int? employeeId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employeeId: employeeId)),
    );
    if (saved == true) {
      _reload();
      invalidateHr(ref);
    }
  }

  Future<void> _openDetail(int employeeId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employeeId: employeeId)),
    );
    if (changed == true) {
      _reload();
      invalidateHr(ref);
    }
  }

  /// سجلّ تغييرات موظفٍ فُكّ إسناده — **الوعد الذي قطعته نافذةُ الفكّ** (ADR-028).
  Future<void> _openUnlinkedLog(EmployeeListItem e) async {
    showDialog(
      context: context,
      builder: (_) => _UnlinkedLogDialog(employeeId: e.employeeId, name: e.fullName),
    );
  }

  /// «إضافة موظف قائم» — بحثٌ بالهوية ثم إسنادٌ إلى الشركة الفعّالة (ADR-027).
  ///
  /// ⚠️ **مساران لا مسارٌ واحد:** إن كان مُسنَداً هنا أصلاً فُتحت بطاقتُه، وإلّا فُتح نموذج
  /// الإسناد. النافذة تُرجع أيّهما، فلا تُقرّر الشاشةُ نيابةً عنها.
  Future<void> _openLinkExisting() async {
    final result = await showDialog<EmployeeLinkResult>(
      context: context,
      builder: (_) => const EmployeeLinkDialog(),
    );
    if (result == null || !mounted) return;

    if (result.alreadyHere) {
      await _openDetail(result.employeeId);
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeFormScreen(
          link: LinkExistingEmployee(
              employeeId: result.employeeId, fullName: result.fullName),
        ),
      ),
    );
    if (saved == true) {
      _reload();
      invalidateHr(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(sessionProvider).canManageEmployees;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hint: شريط الأدوات (بحث · فلتر الحالة · إضافة)
            LayoutBuilder(
              builder: (context, constraints) {
                // مِرشَّح «مَن ينتظر بتّ إجازته» — يظهر **متى وُجد طلبٌ معلّق** فقط، فلا
                // يزحم الشريط بزرٍّ لا يفعل شيئاً في الأيام العادية.
                final pending = ref.watch(hrSummaryProvider)
                        .whenOrNull(data: (s) => s?.pendingLeaves) ??
                    0;
                final showLeavesChip = pending > 0 || _pendingLeavesOnly;

                // ⚠️ **العتبة ترتفع حين يظهر المِرشَّح**: الشريط الأفقيّ يسع بحثاً وفلتراً
                //    وزرّي إضافة، وإقحامُ عنصرٍ خامس عرضه ~240 بكسل يُنتج
                //    «RIGHT OVERFLOWED» — وهو صنف العطل الذي بلّغ عنه المالك في جدول
                //    الرواتب. العرض المطلوب **يُحسب من المحتوى** لا يُخمَّن.
                // 🔴 والعتبتان **مقيستان بالرسم** (انظر ثابتَيهما أعلى الملف): خُمّنت
                //    الأولى 880 يوماً فكشف الحارسُ فيضاً عند 880 بالضبط.
                final isSmall = constraints.maxWidth <
                    (showLeavesChip ? kEmpToolbarNarrowWithChip : kEmpToolbarNarrow);

                final searchWidget = Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onSubmitted: (_) => _reload(),
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم، رقم الهوية، أو الصفة...',
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                                fontSize: 14,
                                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final filterWidget = _StatusFilter(
                  value: _filter,
                  onChanged: (v) {
                    _filter = v ?? _EmpFilter.active;
                    _reload();
                  },
                );

                final addWidget = SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    // ⚠️ الزرّ يظهر لمن يملك الكتابة فقط — القسم يفتح الرؤية والعلَم الكتابة.
                    onPressed: canManage ? () => _openForm() : null,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('موظف جديد',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyDeep,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      shadowColor: AppColors.navyDeep.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                );

                // 🔴 **الباب الذي كان مفقوداً (ADR-027):** الربط بين الشركات كان يعمل خلف
                //    زرّ «موظف جديد» — وهو آخر مكانٍ يُبحَث فيه عن موظفٍ **قائم**. زرٌّ
                //    باسم فعله يُغني عن أن يعرف المستخدم حيلةً.
                final linkWidget = SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: canManage ? _openLinkExisting : null,
                    icon: const Icon(Icons.person_search_rounded, size: 18),
                    label: const Text('إضافة موظف قائم',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyDeep,
                      side: BorderSide(color: AppColors.navyDeep.withValues(alpha: 0.35), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                );

                final leavesWidget = !showLeavesChip
                    ? null
                    : _PendingLeavesChip(
                        count: pending,
                        active: _pendingLeavesOnly,
                        onTap: () => setState(() => _pendingLeavesOnly = !_pendingLeavesOnly),
                      );

                if (isSmall) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchWidget,
                      const SizedBox(height: 12),
                      // ⚠️ **`Wrap` لا `Row` بعد إضافة الزرّ الثاني**: صفٌّ بثلاثة عناصر
                      //    ثابتة العرض يفيض حين تضيق الشاشة، و`Wrap` ينزل بها سطراً بدل
                      //    أن يرمي. هذا يُلغي عتبةً ثانيةً كان يلزم قياسها وصيانتها.
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [filterWidget, linkWidget, addWidget],
                      ),
                      if (leavesWidget != null) ...[
                        const SizedBox(height: 12),
                        Align(alignment: AlignmentDirectional.centerStart, child: leavesWidget),
                      ],
                    ],
                  );
                }
                return Row(children: [
                  Expanded(child: searchWidget),
                  if (leavesWidget != null) ...[
                    const SizedBox(width: 12),
                    leavesWidget,
                  ],
                  const SizedBox(width: 12),
                  filterWidget,
                  const SizedBox(width: 12),
                  linkWidget,
                  const SizedBox(width: 12),
                  addWidget,
                ]);
              },
            ),
            const SizedBox(height: 24),

            if (_pendingLeavesOnly)
              Expanded(
                child: _PendingLeavesList(
                  onOpen: (employeeId) => _openDetail(employeeId),
                  onExit: () => setState(() => _pendingLeavesOnly = false),
                ),
              )
            else
            Expanded(
              child: FutureBuilder<List<EmployeeListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message(
                      icon: Icons.error_outline_rounded,
                      title: 'تعذّر جلب الموظفين',
                      subtitle: '${snap.error}',
                      color: AppColors.danger,
                    );
                  }
                  final items = snap.data ?? const <EmployeeListItem>[];
                  if (items.isEmpty && _filter == _EmpFilter.unlinked) {
                    return _Message(
                      icon: Icons.link_off_rounded,
                      title: 'لا أحد فُكّ إسناده',
                      subtitle: 'مَن تفكّ إسناده عن هذه الشركة يظهر هنا، '
                          'ويبقى سجلّ تغييراته مقروءاً.',
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
                    );
                  }
                  if (items.isEmpty) {
                    return _Message(
                      icon: Icons.groups_2_outlined,
                      title: 'لا يوجد موظفون',
                      subtitle: canManage
                          ? 'أضِف موظفاً جديداً، أو أسنِد موظفاً يعمل في شركة أخرى '
                              'إلى هذه الشركة برقم هويته.'
                          : 'لا تملك صلاحية إضافة موظفين.',
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
                      // 🔴 **هنا يقف المالك أول مرّة في شركةٍ جديدة** — شركةٌ بلا موظفين هي
                      //    بالضبط الحال التي يُراد فيها إسنادُ موظفٍ قائم، فالزرّ في متن
                      //    الرسالة لا في الشريط وحده.
                      action: canManage
                          ? OutlinedButton.icon(
                              onPressed: _openLinkExisting,
                              icon: const Icon(Icons.person_search_rounded, size: 18),
                              label: const Text('إضافة موظف قائم في شركة أخرى',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.navyDeep,
                                side: BorderSide(
                                    color: AppColors.navyDeep.withValues(alpha: 0.35), width: 1.5),
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            )
                          : null,
                    );
                  }
                  // 🔴 **المفكوك يفتح سجلّه لا بطاقته**: بطاقته تردّ 404 بعد الفكّ (لم يعد
                  //    مُسنَداً هنا)، والمطلوب أصلاً هو **سجلّ تغييراته** — وهو يبقى مقروءاً.
                  return _EmployeeTable(
                    items: items,
                    unlinked: _filter == _EmpFilter.unlinked,
                    onTap: (e) => _filter == _EmpFilter.unlinked
                        ? _openUnlinkedLog(e)
                        : _openDetail(e.employeeId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// فلتر الحالة الثلاثي (الكل · على رأس العمل · منتهو الخدمة).
/// مِرشَّح «إجازات بانتظار الموافقة» — بشارة عدد، ويُبرز نفسه حين يكون فعّالاً.
class _PendingLeavesChip extends StatelessWidget {
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _PendingLeavesChip({required this.count, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? AppColors.warnDark : AppColors.warn;

    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.beach_access_rounded, size: 18, color: active ? Colors.white : color),
        label: Text(
          count > 0 ? 'إجازات بانتظار الموافقة ($count)' : 'إجازات بانتظار الموافقة',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: active ? Colors.white : color),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? color : Colors.transparent,
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }
}

/// قائمة مَن ينتظر بتّ إجازته — **الإجازة هي السطر لا الموظف**، لأن السؤال «ما الذي
/// ينتظر قراري؟» لا «مَن من الموظفين له طلب».
class _PendingLeavesList extends ConsumerStatefulWidget {
  final ValueChanged<int> onOpen;
  final VoidCallback onExit;
  const _PendingLeavesList({required this.onOpen, required this.onExit});
  @override
  ConsumerState<_PendingLeavesList> createState() => _PendingLeavesListState();
}

class _PendingLeavesListState extends ConsumerState<_PendingLeavesList> {
  late Future<List<PendingLeave>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).pendingLeaves();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final warn = isDark ? AppColors.warnDark : AppColors.warn;
    final d = DateFormat('yyyy-MM-dd');

    return FutureBuilder<List<PendingLeave>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Message(
              icon: Icons.error_outline_rounded,
              title: 'تعذّر جلب الإجازات',
              subtitle: '${snap.error}',
              color: AppColors.danger);
        }
        final items = snap.data ?? const <PendingLeave>[];
        if (items.isEmpty) {
          return const _Message(
              icon: Icons.check_circle_outline_rounded,
              title: 'لا توجد إجازات بانتظار الموافقة',
              subtitle: 'كل الطلبات مبتوتة.');
        }

        return CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.beach_access_rounded, size: 18, color: warn),
                  const SizedBox(width: 8),
                  Text('${items.length} إجازة بانتظار الموافقة',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: widget.onExit,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('كل الموظفين'),
                  ),
                ]),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 18),
                  itemBuilder: (context, i) {
                    final l = items[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      // فتحُ ملفّ الموظف هو موضع البتّ (الموافقة/الرفض) — لا نُكرّر
                      // إجراءَ المراجعة هنا فيصير له مساران يتباعدان.
                      onTap: () => widget.onOpen(l.employeeId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.employeeName,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w800)),
                                if (l.position.isNotEmpty)
                                  Text(l.position,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: theme.textTheme.bodyMedium?.color
                                              ?.withValues(alpha: 0.6))),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(l.leaveTypeLabel, style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('${d.format(l.fromDate)} ← ${d.format(l.toDate)}',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text('${l.durationDays} يوم',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                          if (l.deductFromSalary)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 6),
                              child: Tooltip(
                                message: 'تُحسم من الراتب',
                                child: Icon(Icons.money_off_rounded,
                                    size: 16, color: AppColors.danger),
                              ),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_left_rounded, size: 18),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// مِرشَّح قائمة الموظفين — أربعُ حالات لا ثلاث بعد ADR-028.
enum _EmpFilter {
  active('على رأس العمل', true),
  terminated('منتهو الخدمة', false),
  all('الكل', null),

  /// مَن فُكّ إسنادهم — **قائمةٌ من نقطةٍ أخرى** لأن إسنادهم محذوفٌ ناعماً.
  /// وهي ما يجعل «كل شيء مذكور في سجل تغييراته» قابلاً للقراءة بعد الفكّ (شرط المالك).
  unlinked('مفكوكو الإسناد', null);

  const _EmpFilter(this.label, this.activeOnly);
  final String label;
  final bool? activeOnly;
}

class _StatusFilter extends StatelessWidget {
  final _EmpFilter value;
  final ValueChanged<_EmpFilter?> onChanged;
  const _StatusFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_EmpFilter>(
          value: value,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color),
          items: _EmpFilter.values
              .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// سجلّ تغييرات موظفٍ فُكّ إسناده — يُقرأ ولا يُعدَّل (ADR-028).
class _UnlinkedLogDialog extends ConsumerStatefulWidget {
  final int employeeId;
  final String name;
  const _UnlinkedLogDialog({required this.employeeId, required this.name});

  @override
  ConsumerState<_UnlinkedLogDialog> createState() => _UnlinkedLogDialogState();
}

class _UnlinkedLogDialogState extends ConsumerState<_UnlinkedLogDialog> {
  late Future<List<EmployeeLogItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).employeeLog(widget.employeeId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = DateFormat('yyyy-MM-dd HH:mm');

    return AlertDialog(
      title: Text('سجلّ تغييرات — ${widget.name}'),
      content: SizedBox(
        width: 560,
        height: 380,
        child: FutureBuilder<List<EmployeeLogItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('${snap.error}',
                  style: const TextStyle(color: AppColors.danger)));
            }
            final items = snap.data ?? const <EmployeeLogItem>[];
            if (items.isEmpty) return const Center(child: Text('لا توجد تغييرات مسجّلة.'));

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, i) {
                final l = items[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.description, style: const TextStyle(fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(d.format(l.changedAt),
                        style: TextStyle(
                            fontSize: 11.5,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.55))),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}

class _EmployeeTable extends StatelessWidget {
  final List<EmployeeListItem> items;
  final ValueChanged<EmployeeListItem> onTap;

  /// قائمة مفكوكي الإسناد — عمود الحالة يقول «فُكّ إسناده» لا حالة عمل.
  final bool unlinked;

  const _EmployeeTable({required this.items, required this.onTap, this.unlinked = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0.##');
    final date = DateFormat('yyyy-MM-dd');

    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ترويسة الجدول
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: const [
                SizedBox(width: 46),
                Expanded(flex: 3, child: _Head('الموظف')),
                Expanded(flex: 2, child: _Head('الصفة')),
                Expanded(flex: 2, child: _Head('تاريخ التعيين')),
                Expanded(flex: 2, child: _Head('الراتب الأساسي')),
                SizedBox(width: 120, child: _Head('الحالة')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
              itemBuilder: (context, i) {
                final e = items[i];
                return InkWell(
                  onTap: () => onTap(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        _Avatar(employeeId: e.employeeId, hasPhoto: e.hasPhoto, name: e.fullName),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              if (e.nationalId != null && e.nationalId!.isNotEmpty)
                                Text('هوية: ${e.nationalId}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: theme.textTheme.bodyMedium?.color
                                            ?.withValues(alpha: 0.55))),
                            ],
                          ),
                        ),
                        Expanded(
                            flex: 2,
                            child: Text(e.position,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13))),
                        Expanded(
                            flex: 2,
                            child: Text(date.format(e.hireDate),
                                style: const TextStyle(fontSize: 13))),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${money.format(e.baseSalary)} ${e.salaryCurrency == 'USD' ? '\$' : 'د.ع'}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(
                            width: 120,
                            child: unlinked
                                ? const _UnlinkedPill()
                                : _EmployeeStatus(item: e)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// الحرف الأول من اسم الموظف في دائرة.
///
/// ⚠️ **الصورة الحقيقية تُعرض في ملفّ الموظف لا في القائمة عمداً:** نقطة الصورة مصادَقة،
/// فجلبُها يلزمه طلبٌ بالتوكن لكل صفّ (`Image.network` على الويب لا يمرّر الترويسات).
/// قائمةٌ من خمسين موظفاً كانت ستُطلق خمسين طلباً عند كل فتح.
class _Avatar extends StatelessWidget {
  final int employeeId;
  final bool hasPhoto;
  final String name;
  const _Avatar({required this.employeeId, required this.hasPhoto, required this.name});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 19,
        backgroundColor: AppColors.navy.withValues(alpha: 0.12),
        child: Text(
          name.trim().isNotEmpty ? name.trim().characters.first : '؟',
          style: const TextStyle(
              fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 15),
        ),
      );
}

/// شارة «فُكّ إسناده» — حالةٌ ثالثة لا حالةُ عملٍ في هذه الشركة.
class _UnlinkedPill extends StatelessWidget {
  const _UnlinkedPill();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.link_off_rounded, size: 13, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text('فُكّ إسناده',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _EmployeeStatus extends StatelessWidget {
  final EmployeeListItem item;
  const _EmployeeStatus({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    late Color color;
    late String label;
    if (item.isTerminated) {
      color = isDark ? AppColors.dangerDark : AppColors.danger;
      label = 'منتهي الخدمة';
    } else if (!item.isActive) {
      color = isDark ? AppColors.warnDark : AppColors.warn;
      label = 'موقوف';
    } else {
      color = isDark ? AppColors.successDark : AppColors.success;
      label = 'على رأس العمل';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
      ));
}

/// رسالة وسط الشاشة (فارغ/خطأ) — بنفس أسلوب بقية الشاشات.
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;

  /// إجراءٌ اختياري أسفل الرسالة — رسالةُ «لا يوجد شيء» أنفعُ حين تحمل مخرجاً.
  final Widget? action;

  const _Message(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.color,
      this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          // النصّ محدود العرض: رسالةٌ من سطرين تمتدّ على شاشةٍ عريضة تصير سطراً واحداً
          // طويلاً يصعب تتبّعه بالعين.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
