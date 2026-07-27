import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/incoming_providers.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';
import 'incoming_form_screen.dart';
import 'incoming_detail_screen.dart';

/// Hint: شاشة عرض قائمة الكتب الواردة
class IncomingListScreen extends ConsumerWidget {
  const IncomingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final asyncList = ref.watch(incomingListProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط الأدوات العلوي
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isSmall = width < 500;
              final isMedium = width < 800;

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
                        onSubmitted: (val) {
                          ref.read(incomingSearchQueryProvider.notifier).state = val;
                        },
                        decoration: InputDecoration(
                          hintText: 'ابحث برقم الكتاب، الموضوع، أو اسم الجهة...',
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

              final filterWidget = Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor, width: 1.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final status = ref.watch(incomingStatusFilterProvider);
                      return DropdownButton<String?>(
                        value: status,
                        isExpanded: true,
                        hint: const Text('حالة الكتاب', style: TextStyle(fontSize: 14)),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        // Hint: تُبنى من الثوابت المشتركة لتشمل كل الحالات دائماً (بما فيها «مغلق»)
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('جميع الحالات')),
                          ...kIncomingStatuses.entries.map(
                              (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) {
                          ref.read(incomingStatusFilterProvider.notifier).state = v;
                        },
                      );
                    },
                  ),
                ),
              );

              // فلتر القسم — يعرض الأقسام المحال إليها، ليتابع المدير عمل كل قسم.
              final deptFilterWidget = Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor, width: 1.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final deptsAsync = ref.watch(departmentsListProvider);
                      final selected = ref.watch(incomingDepartmentFilterProvider);
                      final depts = deptsAsync.asData?.value ?? const <DepartmentModel>[];
                      return DropdownButton<int?>(
                        value: selected,
                        isExpanded: true,
                        hint: const Text('القسم', style: TextStyle(fontSize: 14)),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('كل الأقسام')),
                          ...depts.map((d) => DropdownMenuItem<int?>(value: d.departmentId, child: Text(d.name))),
                        ],
                        onChanged: (v) => ref.read(incomingDepartmentFilterProvider.notifier).state = v,
                      );
                    },
                  ),
                ),
              );

              final buttonWidget = SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const IncomingFormScreen()));
                    if (created == true) {
                      invalidateIncoming(ref);
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('تسجيل وارد جديد',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 8,
                    shadowColor: AppColors.gold.withValues(alpha: 0.5),
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
                    deptFilterWidget,
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
                        Expanded(child: deptFilterWidget),
                      ],
                    ),
                    const SizedBox(height: 16),
                    buttonWidget,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: searchWidget),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: filterWidget),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: deptFilterWidget),
                  const SizedBox(width: 16),
                  buttonWidget,
                ],
              );
            }),
            const SizedBox(height: 32),

            // محتوى الجدول
            Expanded(
              child: CustomCard(
                padding: EdgeInsets.zero,
                child: asyncList.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
                  error: (err, _) => Center(
                      child: Text('حدث خطأ أثناء تحميل البيانات: $err',
                          style: const TextStyle(color: AppColors.danger))),
                  data: (items) {
                    if (items.isEmpty) return _buildEmptyState(context);

                    return LayoutBuilder(builder: (context, constraints) {
                      final minWidth = 900.0;
                      final needsScroll = constraints.maxWidth < minWidth;

                      Widget tableContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // الترويسة
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.navyDeepDark
                                  : theme.colorScheme.surfaceContainerHighest,
                              border: Border(bottom: BorderSide(color: theme.dividerColor)),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Row(
                              children: [
                                _headerCell('رقم وتاريخ الوارد', flex: 2),
                                _headerCell('جهة الإصدار', flex: 2),
                                _headerCell('الموضوع', flex: 3),
                                _headerCell('القسم المحال إليه', flex: 2),
                                _headerCell('الحالة', flex: 1),
                                _headerCell('إجراءات', flex: 1, align: TextAlign.center),
                              ],
                            ),
                          ),
                          // القائمة
                          Expanded(
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: theme.dividerColor),
                              itemBuilder: (_, i) {
                                final it = items[i];
                                return InkWell(
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => IncomingDetailScreen(id: it.incomingId)));
                                    invalidateIncoming(ref);
                                  },
                                  hoverColor: theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // الرقم والتاريخ
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(it.incomingNumber ?? 'بلا رقم',
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold, fontSize: 13.5)),
                                              const SizedBox(height: 4),
                                              Text(DateFormat('yyyy/MM/dd').format(it.receivedDate),
                                                  style: TextStyle(
                                                      color: theme.textTheme.bodyMedium?.color
                                                          ?.withValues(alpha: 0.6),
                                                      fontSize: 12)),
                                            ],
                                          ),
                                        ),

                                        // الجهة المرسلة
                                        Expanded(
                                          flex: 2,
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                    color:
                                                        AppColors.gold.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6)),
                                                child: const Icon(Icons.business_rounded,
                                                    size: 16, color: AppColors.gold),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                  child: Text(it.entityName,
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis)),
                                            ],
                                          ),
                                        ),

                                        // الموضوع
                                        Expanded(
                                          flex: 3,
                                          child: Text(it.subject,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 13, height: 1.5)),
                                        ),

                                        // الأقسام المحال إليها — قد تكون أكثر من واحد (ADR-018)
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            it.departmentNames.isEmpty
                                                ? 'غير محال'
                                                : it.departmentNames.join('، '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: it.departmentNames.isEmpty
                                                    ? Colors.grey
                                                    : theme.textTheme.bodyMedium?.color),
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

                                        // الإجراءات
                                        Expanded(
                                          flex: 1,
                                          child: Align(
                                            alignment: Alignment.center,
                                            child: IconButton(
                                              icon: const Icon(Icons.arrow_forward_ios_rounded,
                                                  size: 16),
                                              color: theme.textTheme.bodyMedium?.color
                                                  ?.withValues(alpha: 0.4),
                                              onPressed: () async {
                                                await Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                        builder: (_) => IncomingDetailScreen(
                                                            id: it.incomingId)));
                                                invalidateIncoming(ref);
                                              },
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
                    });
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
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7F93B8)),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded,
              size: 80,
              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('لا توجد كتب واردة مطابقة لبحثك',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('انقر على زر "تسجيل وارد جديد" لإضافة كتاب',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
