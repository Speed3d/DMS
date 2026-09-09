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
/// 🔴 **دالّةٌ نقيّة لا مزوّدٌ مشتقّ** (بلاغ المالك 2026-09-09، وأُعيد إنتاجه في
/// `provider_resume_test.dart`): `Provider` يراقب `FutureProvider` ⇒ حين يُستأنَف اشتراكُ
/// قارئه **أثناء طور البناء** (تبدّل `TickerMode` مع كل انتقال مسار أو فتح حوار) يُفلَش
/// المصدر فيُبطل التابعُ نفسه ⇒ «setState() called during build» **ويتوقّف الرسم**.
///
/// 🔴 **وهذا يصحّح الدرس المسجَّل**: لم تكن العلّة «غيرُ متزامنٍ يراقب غيرَ متزامن» — بل
/// **أيُّ سلسلةِ `watch` بين مزوّدين**، ولو كان التابع متزامناً وبسيطاً كهذا.
/// **والعلاج: لا سلسلة — يقرأ القارئُ المصدرَ مباشرةً ويحسب بدالّة.**
AsyncValue<int> outgoingCountOf(AsyncValue<List<OutgoingListItem>> drafts) =>
    drafts.whenData((list) => list.length);

/// إبطال كل مزوّدات الصادر ليُعاد جلبها فوراً (بعد اعتماد/إنشاء/تعديل/حذف أو تبديل شركة).
void invalidateOutgoing(WidgetRef ref) {
  ref.invalidate(outgoingListProvider);
  ref.invalidate(pendingDraftsProvider);
}
