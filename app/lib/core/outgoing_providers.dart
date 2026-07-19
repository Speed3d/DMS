import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات الصادر المشتركة (لوحة التحكم/الإشعارات/الشارة) — في ملف محايد لتفادي دورات الاستيراد.
/// كلها تراقب الجلسة/الشركة الفعّالة، وتُبطَّل مركزياً عبر [invalidateOutgoing] بعد أي عملية أو تبديل شركة.

/// قائمة الصادر الكاملة (لوحة التحكم).
final outgoingListProvider = FutureProvider.autoDispose<List<OutgoingListItem>>((ref) async {
  final auth = ref.watch(sessionProvider).auth;
  if (auth == null || !auth.hasModule('Outgoing')) return <OutgoingListItem>[];
  return ref.read(apiClientProvider).outgoingList();
});

/// المسودات المعلّقة (إشعارات الشريط العلوي).
final pendingDraftsProvider = FutureProvider.autoDispose<List<OutgoingListItem>>((ref) async {
  final auth = ref.watch(sessionProvider).auth;
  if (auth == null || !auth.hasModule('Outgoing')) return <OutgoingListItem>[];
  final items = await ref.read(apiClientProvider).outgoingList();
  return items.where((e) => e.status.toLowerCase().contains('draft')).toList();
});

/// عدد المسودات (شارة الشريط الجانبي).
final outgoingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final list = await ref.watch(pendingDraftsProvider.future);
  return list.length;
});

/// إبطال كل مزوّدات الصادر ليُعاد جلبها فوراً (بعد اعتماد/إنشاء/تعديل/حذف أو تبديل شركة).
void invalidateOutgoing(WidgetRef ref) {
  ref.invalidate(outgoingListProvider);
  ref.invalidate(pendingDraftsProvider);
  ref.invalidate(outgoingCountProvider);
}
