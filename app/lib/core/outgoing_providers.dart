import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات الصادر المشتركة (لوحة التحكم/الإشعارات/الشارة) — في ملف محايد لتفادي دورات الاستيراد.
/// كلها تراقب الجلسة/الشركة الفعّالة، وتُبطَّل مركزياً عبر [invalidateOutgoing] بعد أي عملية أو تبديل شركة.

/// قائمة الصادر الكاملة (لوحة التحكم).
final outgoingListProvider = FutureProvider.autoDispose<List<OutgoingListItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  final auth = session.auth;
  if (auth == null || !session.hasModule('Outgoing')) return <OutgoingListItem>[];
  return ref.read(apiClientProvider).outgoingList();
});

/// المسودات المعلّقة (إشعارات الشريط العلوي).
final pendingDraftsProvider = FutureProvider.autoDispose<List<OutgoingListItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  final auth = session.auth;
  if (auth == null || !session.hasModule('Outgoing')) return <OutgoingListItem>[];
  final items = await ref.read(apiClientProvider).outgoingList();
  return items.where((e) => e.status.toLowerCase().contains('draft')).toList();
});

/// عدد المسودات (شارة الشريط الجانبي).
///
/// ⚠️ **مشتقّ من `AsyncValue` مباشرةً، لا عبر `await ref.watch(x.future)`.**
/// انتظارُ `.future` يُنشئ `ProxyProviderListenable`؛ وحين يُستأنَف اشتراكٌ موقوف
/// **أثناء طور البناء** — وهذا يحدث كلما تبدّل `TickerMode` لعنصر Overlay، أي عند
/// كل انتقال بين المسارات وعند إقلاع التطبيق — يُبطل هذا المزوّد نفسه فوراً فيُستدعى
/// `setState` على `UncontrolledProviderScope` أثناء البناء، ويرمي Riverpod:
///   «setState() or markNeedsBuild() called during build».
/// الاشتقاق المتزامن يُلغي السلسلة غير المتزامنة فلا يبقى ما يُبطِل نفسه أثناء البناء.
final outgoingCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) =>
    ref.watch(pendingDraftsProvider).whenData((list) => list.length));

/// إبطال كل مزوّدات الصادر ليُعاد جلبها فوراً (بعد اعتماد/إنشاء/تعديل/حذف أو تبديل شركة).
void invalidateOutgoing(WidgetRef ref) {
  ref.invalidate(outgoingListProvider);
  ref.invalidate(pendingDraftsProvider);
  ref.invalidate(outgoingCountProvider);
}
