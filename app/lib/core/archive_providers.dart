import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات الأرشيف المشتركة (بطاقة لوحة التحكم).
///
/// Hint: في ملف محايد على نمط `outgoing_providers` و`incoming_providers` لتفادي دورات
/// الاستيراد، ويراقب الجلسة فيُعاد الجلب تلقائياً عند **تبديل الشركة** (ADR-017).

/// أضابير الأرشيف — قائمة فارغة لمن لا يملك قسم «الأرشيف» في الشركة الفعّالة.
///
/// ⚠️ الفحص هنا **ليس أماناً** بل تفادٍ لطلب يردّ 403؛ الحماية الحقيقية في الباك-إند
/// (`RequireModule(AppModule.Archive)`). الغرض ألّا تُظهر اللوحة خطأً لمن لا يملك القسم.
final archiveListProvider = FutureProvider.autoDispose<List<ArchiveListItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.auth == null || !session.hasModule('Archive')) return <ArchiveListItem>[];
  return ref.read(apiClientProvider).archiveList();
});
