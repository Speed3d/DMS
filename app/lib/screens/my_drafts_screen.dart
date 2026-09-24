import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/form_drafts.dart';
import '../models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/custom_card.dart';
import 'incoming_form_screen.dart';
import 'outgoing_form_screen.dart';
import 'task_form_screen.dart';

/// «مسوّداتي» — ما كُتب ولم يُرسَل بعد (ADR-051). حلّت محلّ «مسوّدات الأوفلاين».
///
/// 🔐 **مسوّدات المستخدم الحاليّ وحده** — ومسوّداتُ شركاته الأخرى **بالعدد واسم الشركة** فقط
/// (نهج «المحجوب بالعدد» — ADR-046): تُرسَل من الشركة التي كُتبت فيها، فبدّل إليها أولاً.
///
/// 🔴 **ولا إرسالٌ صامت** (قرار المالك): «فتح» يعيد المسوّدة إلى نموذجها ممتلئةً، فيراجعها
/// صاحبها ثم يضغط الإرسال بنفسه. الإرسال التلقائيّ قد يُنشئ كتاباً لم يعُد صاحبُه يريده.
class MyDraftsScreen extends ConsumerWidget {
  const MyDraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final userId = session.auth?.userId;
    final companyId = session.effectiveCompanyId;
    final store = ref.watch(formDraftStoreProvider);
    if (userId == null) return const SizedBox();

    return ValueListenableBuilder(
      valueListenable: store.listenable(),
      builder: (context, _, _) {
        final split = splitByCompany(draftsOf(store.all(), userId), companyId);
        final here = split.here;
        final elsewhere = split.elsewhere;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _intro(context, here.length),
            const SizedBox(height: 16),
            if (elsewhere.isNotEmpty) ...[
              _OtherCompaniesCard(elsewhere: elsewhere),
              const SizedBox(height: 16),
            ],
            if (here.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text('لا مسوّدات في هذه الشركة — كلُّ ما كتبته أُرسل.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              )
            else
              for (final d in here) _DraftCard(draft: d),
          ],
        );
      },
    );
  }

  Widget _intro(BuildContext context, int count) => Text(
        count == 0
            ? 'ما تكتبه في الصادر والوارد والمهام يُحفظ هنا تلقائياً حتى يُرسَل.'
            : 'ما كتبته ولم يُرسَل بعد ($count). افتح المسوّدة لتراجعها ثم أرسلها، أو احذفها.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      );
}

/// مسوّداتٌ في شركاتٍ أخرى — **بالعدد والاسم فقط**.
class _OtherCompaniesCard extends ConsumerStatefulWidget {
  final Map<int, ({String? name, int count})> elsewhere;
  const _OtherCompaniesCard({required this.elsewhere});

  @override
  ConsumerState<_OtherCompaniesCard> createState() => _OtherCompaniesCardState();
}

class _OtherCompaniesCardState extends ConsumerState<_OtherCompaniesCard> {
  late final Future<List<Company>> _companies =
      ref.read(apiClientProvider).companies().catchError((_) => <Company>[]);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Company>>(
        future: _companies,
        builder: (context, snap) => _card(context, snap.data ?? const []),
      );

  Widget _card(BuildContext context, List<Company> companies) {
    final elsewhere = widget.elsewhere;
    // الأسماء من قائمة الشركات (المسموحة لهذا المستخدم)، وإلا الاسمُ المحفوظ مع المسوّدة.
    String nameOf(int id, String? saved) =>
        companies.where((c) => c.companyId == id).map((c) => c.name).firstOrNull ?? saved ?? 'شركة أخرى';
    return CustomCard(
      key: const Key('drafts-other-companies'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz_rounded, color: AppColors.action(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${[
                for (final e in elsewhere.entries) '${e.value.count} في «${nameOf(e.key, e.value.name)}»'
              ].join(' · ')}\nتُرسَل من الشركة التي كُتبت فيها — بدّل إليها من القائمة لتراها هنا.',
              style: const TextStyle(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  final FormDraft draft;
  const _DraftCard({required this.draft});

  IconData get _icon => switch (draft.kind) {
        DraftKind.outgoing => Icons.send_rounded,
        DraftKind.incoming => Icons.inbox_rounded,
        DraftKind.task => Icons.task_alt_rounded,
      };

  /// مرآةٌ لحرّاس الشريط الجانبيّ — لا يُفتح نموذجٌ يردّه الخادم بـ403.
  bool _canOpen(SessionState s) => switch (draft.kind) {
        DraftKind.outgoing => s.hasModule('Outgoing'),
        DraftKind.incoming => s.hasModule('Incoming'),
        DraftKind.task => s.canSeeTasks,
      };

  Widget _formFor() => switch (draft.kind) {
        DraftKind.outgoing => OutgoingFormScreen(draftId: draft.id),
        DraftKind.incoming => IncomingFormScreen(draftId: draft.id),
        DraftKind.task => TaskFormScreen(draftId: draft.id),
      };

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف المسوّدة؟'),
        content: Text('«${draft.title.isEmpty ? 'بلا عنوان' : draft.title}» — لا يمكن استعادتها بعد الحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(formDraftStoreProvider).delete(draft.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canOpen = _canOpen(session);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final warn = dark ? AppColors.warnDark : AppColors.warn;
    final fmt = DateFormat('yyyy/MM/dd HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomCard(
        key: Key('draft-${draft.id}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_icon, color: AppColors.action(context)),
                const SizedBox(width: 10),
                Text(draftKindLabel(draft.kind), style: theme.textTheme.labelLarge),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    draft.title.isEmpty ? 'بلا عنوان' : draft.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(fmt.format(draft.updatedAt), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (draft.failed)
                  _Chip(icon: Icons.cloud_off_rounded, text: 'لم يُرسَل — ${draft.lastError}', color: warn)
                else
                  _Chip(icon: Icons.edit_note_rounded, text: 'قيد الكتابة — لم يُرسَل بعد', color: AppColors.action(context)),
                if (draft.createdRecordId != null)
                  _Chip(
                      icon: Icons.check_circle_rounded,
                      text: 'سُجّل في النظام — بقيت مرفقات',
                      color: dark ? AppColors.successDark : AppColors.success),
                if (draft.missingFiles.isNotEmpty)
                  _Chip(
                      icon: Icons.attach_file_rounded,
                      text: 'يلزم إعادة إرفاق ${draft.missingFiles.length}',
                      color: warn),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmDelete(context, ref),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('حذف'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: canOpen ? '' : 'لم تعُد تملك هذا القسم في هذه الشركة',
                  child: FilledButton.icon(
                    key: Key('open-draft-${draft.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.action(context),
                      foregroundColor: AppColors.onAction(context),
                    ),
                    onPressed: !canOpen
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _formFor())),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('فتح ومراجعة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
        ]),
      );
}
