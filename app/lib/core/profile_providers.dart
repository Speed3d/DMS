import 'dart:async';
import 'dart:typed_data';

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

/// يجلب البروفايل للمزوّدات المشتقّة منه — **بلا `ref.watch` على مزوّدٍ غير متزامن**.
///
/// 🔴 **العلّة التي عولجت (بلاغ المالك 2026-09-09):** مزوّدٌ غير متزامن يراقب مزوّداً غير
/// متزامن **يُبطل نفسه** حين يتغيّر مصدره. ولو وقع ذلك أثناء **استئناف اشتراكٍ موقوف في
/// طور البناء** — ويقع مع كل تبدّل `TickerMode` لعنصر Overlay: انتقالُ مسار، فتحُ حوار،
/// إقلاعُ التطبيق — طُلب إعادةُ بناء `ProviderScope` **داخل البناء نفسه**، فتُرمى
/// «setState() or markNeedsBuild() called during build» **ويتوقّف الرسم**.
/// **رابعُ ظهورٍ للعائلة** (شارتا الشريط الجانبي · ملخّص الرواتب · وهنا)، وأشدُّها أثراً
/// لأن الشريط العلوي يقرأ الصورة في **كل** شاشة.
///
/// ✅ **والعلاج:** تُراقَب **الجلسة** (مصدرٌ متزامن) ويُقرأ البروفايل بـ`ref.read`.
/// والتفاعل المطلوب محفوظ: **تبديلُ الشركة يُعيد بناء الثلاثة**، وبقيّةُ التحديثات تمرّ
/// من [invalidateProfile] الذي يُبطلها جميعاً معاً.
///
/// ⚠️ **ولا تُستبدل `ref.read` بـ`ref.watch` هنا** — حارسٌ في
/// `test/provider_resume_test.dart` يُثبت أن ذلك يُعيد العطل، **وقد رُئي فاشلاً قبل الإصلاح**.
Future<MyProfile?> _profileOrWait(Ref ref) {
  // 🔴 **يُراقَب المصدر المتزامن (الجلسة) ويُقرأ غيرُ المتزامن (البروفايل).**
  //    `ref.watch` على مزوّدٍ غير متزامن يجعل هذا المزوّد **يُبطل نفسه** حين يتغيّر مصدرُه،
  //    ولو وقع ذلك أثناء استئناف اشتراكٍ موقوف في طور البناء **سقط الرسم**.
  //    والمراقبةُ للجلسة تحفظ التفاعل المطلوب: **تبديلُ الشركة يُعيد بناء الثلاثة**.
  final session = ref.watch(sessionProvider);
  if (!session.isLoggedIn) return Future.value(null);
  session.effectiveCompanyId; // تبعيّةٌ مقصودة — تبديل الشركة يُعيد الجلب
  return ref.read(myProfileProvider.future);
}

final myLeavesProvider = FutureProvider.autoDispose<List<LeaveModel>>((ref) async {
  final profile = await _profileOrWait(ref);
  if (profile == null || !profile.isLinkedToEmployee) return <LeaveModel>[];
  return ref.read(apiClientProvider).myLeaves();
});

final myPayslipsProvider = FutureProvider.autoDispose<List<MyPayslip>>((ref) async {
  final profile = await _profileOrWait(ref);
  if (profile == null || !profile.isLinkedToEmployee) return <MyPayslip>[];
  return ref.read(apiClientProvider).myPayslips();
});

/// صورتي كبايتات — `null` لمن لا صورةَ له أو لا بطاقة (ADR-035).
///
/// ⚠️ **يُشتقّ من [myProfileProvider] لا يُجلب مباشرةً**: `hasPhoto` تُخبرنا سلفاً،
/// فلا نطلب صورةً نعلم أنها غير موجودة ثم نبتلع 404 في كل بناء.
/// ⚠️ **وفشلُه لا يُسقط شيئاً** — الشريط العلوي يعود للحرف الأول.
final myPhotoProvider = FutureProvider.autoDispose<Uint8List?>((ref) async {
  final profile = await _profileOrWait(ref);
  if (profile == null || !profile.hasPhoto) return null;
  try {
    return await ref.read(apiClientProvider).myPhoto();
  } catch (_) {
    return null;
  }
});

/// إبطال البروفايل كلّه — بعد طلب إجازة أو سحبها أو تبديل شركة أو **تغيير الصورة**.
void invalidateProfile(WidgetRef ref) {
  ref.invalidate(myProfileProvider);
  ref.invalidate(myLeavesProvider);
  ref.invalidate(myPayslipsProvider);
  ref.invalidate(myPhotoProvider);
}
