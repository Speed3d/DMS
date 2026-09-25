import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/outgoing_providers.dart';
import '../core/theme.dart';

/// هل يرى المستخدم سجلّ حركة الصادر؟ — **كلُّ الأدوار عدا القارئ**، كالوارد (قرار المالك 2026-09-25).
/// مرآةٌ لحارس الخادم في `OutgoingService.GetMovementsAsync` (ADR-056) — **ولا يُطلب ما سيُردّ 403**.
bool canViewOutgoingMovements(String? role) => role != null && role.isNotEmpty && role != 'Reader';

/// سجلّ حركة الكتاب الصادر — مَن أنشأه وعدّله واعتمده وربطه ومتى (ADR-056).
///
/// 🔐 **رقم الوارد المرتبط يصل لمن يراه وحده** — والخادم يقرّر ذلك (G20 — ADR-053)؛ هنا يُعرض إن وصل.
class OutgoingMovementsSection extends ConsumerWidget {
  const OutgoingMovementsSection({super.key, required this.outgoingId});
  final int outgoingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    final asyncLog = ref.watch(outgoingMovementsProvider(outgoingId));
    return Column(
      key: const Key('outgoing-movements'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: muted),
            const SizedBox(width: 8),
            const Text('سجل الحركة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 16),
        asyncLog.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          error: (e, _) => Text('تعذّر تحميل سجل الحركة.', style: const TextStyle(color: AppColors.danger)),
          data: (list) {
            // الكتب الأقدم من السجلّ (أُنشئت قبل تفعيله) بلا حركات — يُقال ذلك لا فراغٌ صامت.
            if (list.isEmpty) {
              return Text('لا حركات مسجَّلة لهذا الكتاب بعد.', style: TextStyle(color: muted, fontSize: 13));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in list) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 5, end: 12),
                        child: CircleAvatar(radius: 4, backgroundColor: AppColors.action(context)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.relatedIncomingNumber == null
                                  ? m.description
                                  : '${m.description} (${m.relatedIncomingNumber})',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m.performedByUserName} • ${DateFormat('yyyy/MM/dd HH:mm').format(m.performedAt.toLocal())}',
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (m != list.last) const Divider(height: 18),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
