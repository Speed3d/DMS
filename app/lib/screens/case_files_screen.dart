import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/case_file_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/search_field.dart';
import 'incoming_detail_screen.dart';
import 'outgoing_detail_screen.dart';

/// **شاشة المعاملات** — استعراضُ الخيوط وإعادة تسميتها (ADR-045).
///
/// ⚠️ **مدخلان لا واحد** (قرار المالك): هذه للاستعراض والبحث، وزرُّ «يخصّ كتاباً سابقاً»
/// داخل الكتاب للعمل اليوميّ. والثاني هو المستعمَل غالباً، وهذه لمن يفكّر بالملفّات.
class CaseFilesScreen extends ConsumerWidget {
  const CaseFilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(caseFilesProvider);
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: DebouncedSearchField(
              hintText: 'بحث بعنوان المعاملة',
              onChanged: (v) => ref.read(caseSearchProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'المعاملة خيطُ مراسلاتٍ يجمع الوارد والصادر في قضيةٍ واحدة.',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('تعذّر جلب المعاملات: $e',
                      style: TextStyle(color: AppColors.danger))),
              data: (items) => items.isEmpty
                  ? _empty(context, muted)
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _CaseRow(item: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, Color? muted) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 56, color: muted),
            const SizedBox(height: 14),
            Text('لا توجد معاملات بعد.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 8),
            // 🔑 **الفراغ يشرح المدخل**: نمط «ميزة بلا مدخل» تكرّر ثماني مرّات في المستودع،
            //    وشاشةٌ فارغة بلا إرشاد هي أحد وجوهه.
            Text(
              'افتح أيّ كتابٍ وارد أو صادر، ثم اضغط «يخصّ كتاباً سابقاً».',
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
          ],
        ),
      );
}

class _CaseRow extends ConsumerWidget {
  const _CaseRow({required this.item});
  final CaseFileListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return CustomCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CaseFileDetailScreen(id: item.caseFileId))),
      child: Row(
        children: [
          Icon(Icons.account_tree_rounded, color: AppColors.action(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  '${item.visibleCount} كتاباً'
                  '${item.hiddenCount > 0 ? ' · و${item.hiddenCount} خارج صلاحيتك' : ''}'
                  ' · ${DateFormat('yyyy/MM/dd').format(item.createdAt.toLocal())}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 15),
        ],
      ),
    );
  }
}

/// تفاصيل معاملة — أعضاؤها المرئيّون، وإعادة التسمية، وإخراج كتاب.
class CaseFileDetailScreen extends ConsumerStatefulWidget {
  const CaseFileDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<CaseFileDetailScreen> createState() => _CaseFileDetailScreenState();
}

class _CaseFileDetailScreenState extends ConsumerState<CaseFileDetailScreen> {
  bool _busy = false;

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? AppColors.danger : null));
  }

  Future<void> _rename(CaseFileDetail d) async {
    final ctrl = TextEditingController(text: d.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إعادة تسمية المعاملة'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'العنوان'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).caseFileRename(widget.id, ctrl.text.trim());
      invalidateCaseFiles(ref);
      _snack('تم حفظ العنوان.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CaseMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إخراج من المعاملة'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('سيخرج الكتاب ${m.number ?? '#${m.bookId}'} من هذه المعاملة. '
            'ولا يتغيّر شيءٌ في الكتاب نفسه — لا حالتُه ولا رقمُه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إخراج')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final still = await ref
          .read(apiClientProvider)
          .caseFileRemoveMember(widget.id, m.kind, m.bookId);
      invalidateCaseFiles(ref);
      if (!mounted) return;
      if (still == null) {
        // ⚠️ خرج آخر كتاب فطُويت المعاملة — والشاشة لم يعُد لها موضوع.
        _snack('أُخرج الكتاب، وطُويت المعاملة لأنها فرغت.');
        Navigator.of(context).pop();
        return;
      }
      _snack('أُخرج الكتاب من المعاملة.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(caseFileDetailProvider(widget.id));
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    final canManage = ref.watch(sessionProvider).canManageIncoming;

    return Scaffold(
      appBar: AppBar(title: const Text('المعاملة'), centerTitle: true),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('تعذّر فتح المعاملة: $e', style: TextStyle(color: AppColors.danger))),
        data: (d) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(d.title,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          if (canManage)
                            IconButton(
                              tooltip: 'إعادة التسمية',
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              onPressed: _busy ? null : () => _rename(d),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${d.members.length} كتاباً'
                        '${d.hiddenCount > 0 ? ' · و${d.hiddenCount} خارج صلاحيتك' : ''}',
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final m in d.members) ...[
                  CustomCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(m.number ?? '#${m.bookId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                                const SizedBox(width: 8),
                                Text(m.kind.label,
                                    style: TextStyle(fontSize: 11, color: muted)),
                                const SizedBox(width: 8),
                                Text(DateFormat('yyyy/MM/dd').format(m.date),
                                    style: TextStyle(fontSize: 11, color: muted)),
                              ]),
                              const SizedBox(height: 3),
                              Text(m.subject,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: muted)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'فتح الكتاب',
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => m.kind == CaseMemberKind.incoming
                                  ? IncomingDetailScreen(id: m.bookId)
                                  : OutgoingDetailScreen(id: m.bookId))),
                        ),
                        if (canManage)
                          IconButton(
                            tooltip: 'إخراج من المعاملة',
                            icon: const Icon(Icons.link_off_rounded, size: 18),
                            color: AppColors.danger,
                            onPressed: _busy ? null : () => _remove(m),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (d.hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(Icons.lock_outline_rounded, size: 15, color: muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'و${d.hiddenCount} كتاباً في هذه المعاملة خارج صلاحيتك — '
                          'يظهر عددها ولا تظهر تفاصيلها.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
