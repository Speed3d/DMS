import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'archive_bulk_import_screen.dart';
import 'archive_form_screen.dart';
import 'archive_detail_screen.dart';
import 'incoming_detail_screen.dart';

/// Hint: شاشة قائمة الأرشيف - عرض المستندات بأسلوب جدول عصري وأنيق
class ArchiveListScreen extends ConsumerStatefulWidget {
  const ArchiveListScreen({super.key});
  @override
  ConsumerState<ArchiveListScreen> createState() => _ArchiveListScreenState();
}

class _ArchiveListScreenState extends ConsumerState<ArchiveListScreen> {
  late Future<List<ArchiveLensItem>> _future;
  final _search = TextEditingController();

  /// سنة مختارة للفلترة — `null` = كل السنوات.
  int? _year;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Hint: تُجلب من **عدسة الأرشيف** لا من `/archive` وحدها — فالقسم يجمع مصدرين:
  /// الوارد المؤرشف (يبقى كتاباً وارداً، لا يُنقل) والأضابير الورقية القديمة.
  void _reload() {
    _future = ref.read(apiClientProvider).archiveLens(search: _search.text, year: _year);
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
            // Hint: شريط الأدوات العلوي (بحث، فلترة، إضافة)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
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
                            hintText: 'ابحث بعنوان المستند، رقم الكتاب، أو الكلمات المفتاحية...',
                            border: InputBorder.none,
                            hintStyle: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final buttonWidget = SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(builder: (_) => const ArchiveFormScreen()));
                      if (created == true) _reload();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('أرشفة مستند جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

                // زرّ الاستيراد بالجملة — المدخل الوحيد لإدخال الأرشيف الورقي القديم
                // (آلاف الملفات؛ إدخالها فرادى لا يكتمل عملياً).
                final bulkWidget = SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ArchiveBulkImportScreen()));
                      _reload();
                    },
                    icon: const Icon(Icons.drive_folder_upload_rounded),
                    label: const Text('استيراد دفعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyDeep,
                      side: BorderSide(color: AppColors.navyDeep.withValues(alpha: 0.5), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                );

                if (isSmall) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchWidget,
                      const SizedBox(height: 16),
                      bulkWidget,
                      const SizedBox(height: 16),
                      buttonWidget,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchWidget),
                    const SizedBox(width: 16),
                    bulkWidget,
                    const SizedBox(width: 12),
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
                child: FutureBuilder<List<ArchiveLensItem>>(
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
                                  _headerCell('الرقم والمصدر', flex: 2),
                                  _headerCell('العنوان', flex: 3),
                                  _headerCell('القسم', flex: 2),
                                  _headerCell('تاريخ الأرشفة', flex: 2),
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
                                    onTap: () => _open(it),
                                    hoverColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // الرقم + شارة المصدر (وارد مؤرشف / أضبارة ورقية)
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(it.number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: (it.isIncoming ? AppColors.success : AppColors.navyDeep).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    it.isIncoming ? 'وارد مؤرشف' : 'أضبارة ورقية',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: it.isIncoming ? AppColors.success : AppColors.navyDeep,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // العنوان ونوع المستند
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5)),
                                                if (it.documentTypeName != null || it.entityName != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [it.documentTypeName, it.entityName].where((e) => e != null).join(' · '),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(fontSize: 11.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),

                                          // القسم — قد يكون فارغاً أو متعدّداً (ADR-018)
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              it.departmentNames.isEmpty ? 'بلا قسم' : it.departmentNames.join('، '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: it.departmentNames.isEmpty ? FontWeight.normal : FontWeight.w600,
                                                color: it.departmentNames.isEmpty
                                                    ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.45)
                                                    : null,
                                              ),
                                            ),
                                          ),

                                          // تاريخ الأرشفة
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              DateFormat('yyyy/MM/dd').format(it.archivedAt),
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                                                onPressed: () => _open(it),
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
          Icon(Icons.inventory_2_rounded, size: 80, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('لا توجد مستندات في الأرشيف مطابقة لبحثك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('انقر على زر "أرشفة مستند جديد" لإنشاء أول مستند لك', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  /// يفتح الصفّ في شاشته الصحيحة حسب مصدره.
  ///
  /// ⚠️ الكتاب المؤرشف يُفتح في **شاشة الوارد** لا في شاشة الأرشيف — لأنه لم يُنقل:
  /// مرفقاته وسجل حركته وربطه بالصادر كلها هناك. فتحُه في شاشة الأرشيف كان سيُظهر
  /// نصف الحقيقة.
  void _open(ArchiveLensItem it) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => it.isIncoming
          ? IncomingDetailScreen(id: it.id)
          : ArchiveDetailScreen(id: it.id),
    ));
    _reload();
  }
}
