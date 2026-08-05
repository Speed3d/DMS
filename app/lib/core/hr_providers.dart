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

/// إبطال كل مزوّدات الوحدة (بعد إضافة موظف · تسديد · تبديل شركة).
void invalidateHr(WidgetRef ref) {
  ref.invalidate(employeesProvider);
  ref.invalidate(hrSummaryProvider);
  ref.invalidate(unpaidMonthsProvider);
}
