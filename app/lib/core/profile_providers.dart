import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات البروفايل الشخصي (ADR-033).
///
/// ⚠️ **بلا أيّ حارس صلاحية هنا — وهذا مقصود**: البروفايل بياناتُ صاحب الجلسة، والخادم
/// يشتقّها من التوكن. وحارسٌ في الواجهة كان سيمنع مَن يحقّ له لا مَن لا يحقّ.
/// الحارس الوحيد المعروض هو [MyProfile.isLinkedToEmployee] — وهو **حقيقةُ ربطٍ لا صلاحية**:
/// من لا بطاقةَ له لا إجازاتٍ له ولا رواتب، فتُخفى التبويبتان.

/// هويّتي — تُراقب الشركة الفعّالة لأن البطاقة والصفة تخصّان شركةً بعينها (ADR-017).
final myProfileProvider = FutureProvider.autoDispose<MyProfile?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.isLoggedIn) return null;
  // ⚠️ قراءةُ `effectiveCompanyId` تجعل المزوّد يُعاد بناؤه عند تبديل الشركة.
  session.effectiveCompanyId;
  return ref.read(apiClientProvider).myProfile();
});

final myLeavesProvider = FutureProvider.autoDispose<List<LeaveModel>>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null || !profile.isLinkedToEmployee) return <LeaveModel>[];
  return ref.read(apiClientProvider).myLeaves();
});

final myPayslipsProvider = FutureProvider.autoDispose<List<MyPayslip>>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null || !profile.isLinkedToEmployee) return <MyPayslip>[];
  return ref.read(apiClientProvider).myPayslips();
});

/// إبطال البروفايل كلّه — بعد طلب إجازة أو سحبها أو تبديل شركة.
void invalidateProfile(WidgetRef ref) {
  ref.invalidate(myProfileProvider);
  ref.invalidate(myLeavesProvider);
  ref.invalidate(myPayslipsProvider);
}
