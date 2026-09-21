import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'session.dart';

/// نصُّ البحث في شاشة المعاملات — حالةٌ محلّية تعيش أطول من الشاشة.
///
/// ⚠️ `StateProvider` أُزيل في Riverpod 3، فالنمط المستقرّ في المستودع `NotifierProvider`
/// بصنفٍ يُعيد تعريف `set state` ليكون عامّاً.
class CaseSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  @override
  set state(String v) => super.state = v;
  @override
  String get state => super.state;
}

final caseSearchProvider =
    NotifierProvider<CaseSearchNotifier, String>(CaseSearchNotifier.new);

/// قائمة المعاملات في الشركة الفعّالة.
///
/// 🔐 **يحرس الجلسة بنفسه**: المعاملة تجمع نوعين، والخادم يشترط **أحد القسمين** —
/// فالحارس هنا مرآتُه. وطلبٌ نعلم أنه يُردّ لا يُطلَق.
final caseFilesProvider =
    FutureProvider.autoDispose<List<CaseFileListItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.auth == null) return const [];
  if (!session.hasModule('Incoming') && !session.hasModule('Outgoing')) return const [];

  final search = ref.watch(caseSearchProvider);
  return ref.read(apiClientProvider).caseFiles(search: search);
});

/// تفاصيل معاملة بعينها.
final caseFileDetailProvider =
    FutureProvider.autoDispose.family<CaseFileDetail, int>((ref, id) async =>
        ref.read(apiClientProvider).caseFileGet(id));

/// بطاقة «الكتب المرتبطة» لكتابٍ بعينه — `null` إن لم يكن في معاملة.
final relatedCaseProvider = FutureProvider.autoDispose
    .family<CaseFileDetail?, (CaseMemberKind, int)>((ref, key) async {
  final session = ref.watch(sessionProvider);
  if (session.auth == null) return null;
  if (!session.hasModule('Incoming') && !session.hasModule('Outgoing')) return null;

  return ref.read(apiClientProvider).caseFileRelated(key.$1, key.$2);
});

/// عدد المعاملات — **دالّةٌ نقيّة يناديها القارئ، لا مزوّدٌ مشتقّ**.
///
/// 🔴 **ADR-042**: `Provider` يراقب `FutureProvider` ⇒ حين يُستأنَف اشتراكُ قارئه **أثناء
/// طور البناء** (تبدّل `TickerMode` مع كل انتقال مسار أو فتح حوار) يُفلَش المصدر فيُبطل
/// التابعُ نفسه ⇒ «setState() called during build» **ويتوقّف الرسم**.
/// **والعلاج: لا سلسلة — يقرأ القارئُ المصدرَ مباشرةً ويحسب بدالّة.**
/// وحارسُه `test/provider_resume_test.dart`.
AsyncValue<int> caseFileCountOf(AsyncValue<List<CaseFileListItem>> src) =>
    src.whenData((list) => list.length);

/// إبطالٌ مركزيّ بعد كل عملية تمسّ المعاملات.
///
/// ⚠️ **ويُبطل قائمتَي الوارد والصادر معهما**: شارةُ المعاملة تُرسم من `caseFileId` في
/// صفّ القائمة، فضمٌّ أو إخراجٌ يغيّرها — وبلا هذا تبقى الشارة على حالها حتى إعادة التحميل.
void invalidateCaseFiles(WidgetRef ref) {
  ref.invalidate(caseFilesProvider);
  ref.invalidate(caseFileDetailProvider);
  ref.invalidate(relatedCaseProvider);
}
