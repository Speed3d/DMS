import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/form_drafts.dart';
import '../core/theme.dart';

/// هل فشلُ الإرسال **انتظارٌ** (الخادم غائب أو متوقّف) فتبقى المسوّدة لتُرسَل لاحقاً؟
///
/// ⚠️ **لا لغيره**: خطأ تحقّقٍ (400) أو صلاحية (403) يُعرض فوراً ليصحّحه صاحبُه — تأجيلُه
/// يعني أن يعود بعد ساعة فيجد الخطأ نفسه.
bool isDeferrableFailure(ApiException e) => e.isNetworkError || e.isMaintenance;

/// سببٌ مقروء يُحفظ مع المسوّدة.
String deferralReason(ApiException e) => e.isMaintenance
    ? 'النظام كان متوقّفاً للصيانة'
    : 'تعذّر الوصول إلى الخادم';

String _when(DateTime t) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? DateFormat('HH:mm').format(t) : DateFormat('yyyy/MM/dd HH:mm').format(t);
}

/// شريطٌ أعلى نموذجٍ جديد: «لديك مسوّدة لم تُرسَل — استعادة».
///
/// ⚠️ **«تجاهل» لا يحذف** — يُخفي الشريط وتبقى المسوّدة في «مسوّداتي». حذفُ ما كتبه
/// المستخدم بضغطةٍ على شريطٍ عابر أسوأ من شريطٍ يظهر ثانيةً.
class DraftRestoreBanner extends StatelessWidget {
  final FormDraft draft;
  final int othersCount;
  final VoidCallback onRestore;
  final VoidCallback onDismiss;

  const DraftRestoreBanner({
    super.key,
    required this.draft,
    required this.onRestore,
    required this.onDismiss,
    this.othersCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? AppColors.warnDark : AppColors.warn;
    final title = draft.title.trim().isEmpty ? 'بلا عنوان' : draft.title.trim();
    return Container(
      key: const Key('draft-restore-banner'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Icon(draft.failed ? Icons.cloud_off_rounded : Icons.history_rounded, color: accent),
          Text(
            draft.failed
                ? 'لم يُرسَل «$title» (${_when(draft.updatedAt)}) — ${draft.lastError}.'
                : 'لديك ما لم يُحفظ من ${_when(draft.updatedAt)}: «$title».',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (othersCount > 0)
            Text('ومعها $othersCount أخرى في «مسوّداتي».', style: Theme.of(context).textTheme.bodySmall),
          FilledButton.icon(
            key: const Key('draft-restore'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.action(context),
              foregroundColor: AppColors.onAction(context),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('استعادة'),
          ),
          TextButton(onPressed: onDismiss, child: const Text('ليس الآن')),
        ],
      ),
    );
  }
}

/// ما يختاره المستخدم عند مغادرة نموذجٍ فيه ما لم يُرسَل.
enum DraftExitChoice { keep, discard, stay }

/// «لديك ما لم يُرسَل» — **الإبقاء هو الافتراض** (أوّل زرّ وأبرزه): ما يضيع بالخطأ لا يعود.
Future<DraftExitChoice> showDraftExitDialog(BuildContext context) async {
  final r = await showDialog<DraftExitChoice>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('لم يُرسَل بعد'),
      content: const Text(
        'ما كتبته لم يُرسَل إلى النظام.\nاحفظه في «مسوّداتي» لتكمله لاحقاً، أو تجاهله.',
        style: TextStyle(height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, DraftExitChoice.discard),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('تجاهل ما كتبته'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, DraftExitChoice.stay),
          child: const Text('متابعة التحرير'),
        ),
        FilledButton(
          key: const Key('draft-exit-keep'),
          onPressed: () => Navigator.pop(c, DraftExitChoice.keep),
          child: const Text('احفظه في مسوّداتي'),
        ),
      ],
    ),
  );
  return r ?? DraftExitChoice.stay;
}

/// رسالةٌ بعد فشلٍ مؤجَّل: «لم يُرسَل — محفوظٌ في مسوّداتي».
void showDeferredSnack(BuildContext context, String reason) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 6),
    content: Text('$reason — لم يُرسَل، وحُفظ في «مسوّداتي». ستُنبَّه عند عودة الاتصال لتراجعه وترسله.'),
  ));
}
