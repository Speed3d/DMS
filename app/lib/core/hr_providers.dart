import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// مزوّدات وحدة الموظفين والرواتب (ADR-023) — في ملف محايد لتفادي دورات الاستيراد،
/// على نمط `outgoing_providers.dart`.
///
/// كلها تراقب الجلسة/الشركة الفعّالة، وتُبطَّل مركزياً عبر [invalidateHr] بعد أي عملية
/// أو تبديل شركة.

/// موظفو الشركة الفعّالة الفعّالون (لوحة التحكم والقوائم المنسدلة).
final employeesProvider = FutureProvider.autoDispose<List<EmployeeListItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  // ⚠️ الحدّان معاً (القسم **والدور**) — مرآةٌ لـ`[RequireHrModule]`؛ الطلب بلا أحدهما يردّ 403.
  if (!session.canSeeEmployees) return <EmployeeListItem>[];
  return ref.read(apiClientProvider).employees(activeOnly: true);
});

/// ملخّص الوحدة (بطاقة لوحة التحكم).
final hrSummaryProvider = FutureProvider.autoDispose<HrSummary?>((ref) async {
  final session = ref.watch(sessionProvider);
  // الملخّص يخدم القسمين، والخادم يُفرغ ما لا يخصّ الطالب — فيكفي أيُّهما.
  if (!session.canSeeAnyHr) return null;
  return ref.read(apiClientProvider).hrSummary();
});

/// عدد الأشهر غير المُسدَّدة (شارة الشريط الجانبي).
///
/// ⚠️ **مشتقّ من `AsyncValue` مباشرةً لا عبر `await ref.watch(x.future)`** — انتظارُ
/// `.future` يُنشئ `ProxyProviderListenable` يُبطل نفسه أثناء طور البناء فيرمي
/// «setState() called during build». (الدرس نفسه المسجَّل في `outgoing_providers.dart`.)
final unpaidMonthsProvider = Provider.autoDispose<AsyncValue<int>>((ref) =>
    ref.watch(hrSummaryProvider).whenData((s) => s?.unpaidMonths ?? 0));

/// صورة موظفٍ بعينه — بايتاتٌ أو `null` لمن لا صورةَ له.
///
/// 🔴 **لماذا مزوّدٌ مُخزَّن (بلا `autoDispose`)؟** لأن قائمة الموظفين تُعيد بناء صفوفها
/// مع كل تمرير وفلترة، ومزوّدٌ يتلاشى يعني **طلبَ صورةٍ جديداً لكل صفٍّ في كل مرّة** —
/// عشرون موظفاً تصير عشرين طلباً تتكرّر بلا نهاية. التخزين يجعلها **طلباً واحداً للصورة
/// طوال الجلسة**.
///
/// ⚠️ **وثمنُه ذاكرة**: تبقى الصور محمَّلةً حتى تُبطَل. مقبولٌ لعشرات الموظفين
/// (الصور صغيرة وحدُّها 5 م.ب)، و**يُعاد النظر فيه لو صاروا مئات**.
///
/// ⚠️ **ولا تُطلب لمن `hasPhoto == false`** — الشرط في مُستدعيها: طلبُ صورةٍ نعلم
/// أنها غير موجودة يُنتج 404 في كل صفّ.
/// ⚠️ **وفشلُها لا يُسقط صفّاً** — يعود الحرف الأول.
final employeePhotoProvider =
    FutureProvider.family<Uint8List?, int>((ref, employeeId) async {
  try {
    final bytes = await ref.read(apiClientProvider).employeePhoto(employeeId);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
});

/// إبطال كل مزوّدات الوحدة (بعد إضافة موظف · تسديد · تبديل شركة · **تغيير صورة**).
void invalidateHr(WidgetRef ref) {
  ref.invalidate(employeesProvider);
  ref.invalidate(hrSummaryProvider);
  ref.invalidate(unpaidMonthsProvider);
  // ⚠️ **العائلة كلّها**: لا نعرف أيّ بطاقةٍ تغيّرت صورتها، وإبقاءُ صورةٍ قديمة
  //    مخزَّنةً يجعل المستخدم يظنّ الرفع فشل.
  ref.invalidate(employeePhotoProvider);
}
