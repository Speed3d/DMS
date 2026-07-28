import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات الأرشيف المشتركة (بطاقة لوحة التحكم).
///
/// Hint: في ملف محايد على نمط `outgoing_providers` و`incoming_providers` لتفادي دورات
/// الاستيراد، ويراقب الجلسة فيُعاد الجلب تلقائياً عند **تبديل الشركة** (ADR-017).

/// **عدسة الأرشيف** — الوارد المؤرشف + الأضابير الورقية معاً.
///
/// ⚠️ الفحص هنا **ليس أماناً** بل تفادٍ لطلب يردّ 403؛ الحماية الحقيقية في الباك-إند
/// (`RequireModule(AppModule.Archive)` + الحدّ المزدوج على صفوف الوارد).
///
/// Hint: لوحة التحكم تعدّ منها لا من `incomingListProvider` — فالأخيرة صارت تستبعد
/// المؤرشف من القائمة الافتراضية، ولو بقيت اللوحة تعدّ منها لعرضت **صفراً دائماً**.
final archiveLensProvider = FutureProvider.autoDispose<List<ArchiveLensItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.auth == null || !session.hasModule('Archive')) return <ArchiveLensItem>[];
  return ref.read(apiClientProvider).archiveLens();
});
