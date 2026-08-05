import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/nav_intent.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';
import 'outgoing_form_screen.dart';
import 'outgoing_detail_screen.dart';

/// Hint: شاشة قائمة الصادر - عرض الكتب بأسلوب جدول عصري وأنيق
class OutgoingListScreen extends ConsumerStatefulWidget {
  const OutgoingListScreen({super.key});
  @override
  ConsumerState<OutgoingListScreen> createState() => _OutgoingListScreenState();
}

class _OutgoingListScreenState extends ConsumerState<OutgoingListScreen> {
  late Future<List<OutgoingListItem>> _future;
  String? _status;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // نيّة التنقّل (G11): بطاقة «بانتظار الاعتماد» تطلب المسودّات وحدها، فتفتح الشاشة
    // **بفلترها** بدل أن تعرض كل الصادر وتُكذّب الرقم الذي ضُغط عليه.
    _status = takeNavIntent<OutgoingStatusIntent>(ref)?.status;
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).outgoingList(status: _status, search: _search.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hint: شريط الأدوات العلوي (بحث، فلترة، إضافة)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isMedium = width < 800;
                final isSmall = width < 500;

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
                      Icon(Icons.search_rounded, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onSubmitted: (_) => _reload(),
                          decoration: InputDecoration(
                            hintText: 'ابحث برقم الكتاب، الموضوع، أو اسم الجهة...',
                            border: InputBorder.none,
                            hintStyle: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final filterWidget = Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _status,
                      isExpanded: true,
                      hint: const Text('حالة الكتاب', style: TextStyle(fontSize: 14)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('جميع الحالات')),
                        DropdownMenuItem(value: 'Draft', child: Text('مسودّة فقط')),
                        DropdownMenuItem(value: 'Pending', child: Text('قيد الاعتماد')),
                        DropdownMenuItem(value: 'Final', child: Text('معتمد فقط')),
                      ],
                      onChanged: (v) { _status = v; _reload(); },
                    ),
                  ),
                );

                final buttonWidget = SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(builder: (_) => const OutgoingFormScreen()));
                      if (created == true) _reload();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('كتاب جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

                if (isSmall) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchWidget,
                      const SizedBox(height: 16),
                      filterWidget,
                      const SizedBox(height: 16),
                      buttonWidget,
                    ],
                  );
                } else if (isMedium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchWidget,
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: filterWidget),
                          const SizedBox(width: 16),
                          Expanded(child: buttonWidget),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 3, child: searchWidget),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: filterWidget),
                    const SizedBox(width: 16),
                    buttonWidget,
                  ],
                );
              }
            ),
            const SizedBox(height: 32),

            // Hint: عرض البيانات داخل CustomCard كجدول
            Expanded(
              child: CustomCard(
                padding: EdgeInsets.zero,
                child: FutureBuilder<List<OutgoingListItem>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                    }
                    if (snap.hasError) {
                      return Center(child: Text('حدث خطأ أثناء تحميل البيانات: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
                    }
                    final items = snap.data ?? [];
                    if (items.isEmpty) {
                      return _buildEmptyState();
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final minWidth = 900.0;
                        final needsScroll = constraints.maxWidth < minWidth;

                        Widget tableContent = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ترويسة الجدول (Header)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.navyDeepDark : theme.colorScheme.surfaceContainerHighest,
                                border: Border(bottom: BorderSide(color: theme.dividerColor)),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  _headerCell('رقم وتاريخ الكتاب', flex: 2),
                                  _headerCell('الجهة المقصودة', flex: 2),
                                  _headerCell('الموضوع', flex: 3),
                                  _headerCell('المبلغ (د.ع)', flex: 2),
                                  _headerCell('الحالة', flex: 1),
                                  _headerCell('إجراءات', flex: 1, align: TextAlign.center),
                                ],
                              ),
                            ),
                            
                            // محتوى الجدول
                            Expanded(
                              child: ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                                itemBuilder: (_, i) {
                                  final it = items[i];
                                  return InkWell(
                                    onTap: () => _openDetail(it.outgoingId),
                                    hoverColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // الرقم والتاريخ
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(it.number ?? 'مسودة (بلا رقم)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                const SizedBox(height: 4),
                                                Text(DateFormat('yyyy/MM/dd').format(it.date), style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          
                                          // الجهة
                                          Expanded(
                                            flex: 2,
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                                  child: const Icon(Icons.business_rounded, size: 16, color: AppColors.gold),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(it.entityName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                              ],
                                            ),
                                          ),

                                          // الموضوع
                                          Expanded(
                                            flex: 3,
                                            child: Text(it.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.5)),
                                          ),

                                          // المبلغ
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              it.amountInIqd != null && it.amountInIqd! > 0 ? '${_fmt(it.amountInIqd!)} د.ع' : '-',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                            ),
                                          ),

                                          // الحالة
                                          Expanded(
                                            flex: 1,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: StatusPill(status: it.status),
                                            ),
                                          ),

                                          // إجراءات
                                          Expanded(
                                            flex: 1,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: IconButton(
                                                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                                                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
                                                onPressed: () => _openDetail(it.outgoingId),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );

                        if (needsScroll) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: minWidth,
                              height: constraints.maxHeight,
                              child: tableContent,
                            ),
                          );
                        }

                        return tableContent;
                      }
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String title, {required int flex, TextAlign align = TextAlign.start}) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        textAlign: align,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7F93B8)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 80, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('لا توجد كتب صادرة مطابقة لبحثك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('انقر على زر "كتاب جديد" لإنشاء أول كتاب لك', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  void _openDetail(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutgoingDetailScreen(id: id)));
    _reload();
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
