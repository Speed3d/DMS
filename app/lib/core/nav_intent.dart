import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **نيّة التنقّل** — ما يريده الضاغطُ من الشاشة الوجهة، لا مجرّد أيِّ شاشة يفتح.
///
/// ⚠️ **لماذا مزوّد لا وسيط في الدالّة؟** القشرة `home_shell` تمرّر `ValueChanged<int>`
/// **رقماً حرفياً** إلى `DashboardScreen`، والشاشات الوجهة `const` وحالتُها محلية. فتمريرُ
/// فلترٍ معها كان يستلزم تغيير توقيع التنقّل وكلَّ منادٍ له — ولهذا بقيت الفجوة **G11**
/// مفتوحة منذ 2026-07-28 موصوفةً بأنها «ليست سطراً واحداً».
///
/// المزوّد يفصل **الوجهة** عن **النيّة**: الضاغط يكتب نيّته ثم ينادي `onNavigate` كالعادة،
/// والوجهة تقرأ النيّة في `initState` **وتمسحها**. المسحُ شرطٌ لا تحسين: نيّةٌ باقية تجعل
/// الزيارة الثانية للشاشة تُطبّق فلتراً لم يطلبه أحد.
///
/// 🔴 **ولا يُوسَّع بلا داعٍ:** كل نيّة هنا وُلدت من بلاغٍ حقيقي — لا تُضاف نيّةٌ «قد تنفع».
sealed class NavIntent {
  const NavIntent();
}

/// افتح قائمة الصادر مقصورةً على حالةٍ بعينها (بطاقة «بانتظار الاعتماد» — G11).
final class OutgoingStatusIntent extends NavIntent {
  /// `Draft` أو `Final` — نفس قيم فلتر الشاشة.
  final String status;
  const OutgoingStatusIntent(this.status);
}

/// افتح قائمة الموظفين مقصورةً على مَن لهم إجازات معلّقة (بلاغ المالك ٨).
final class PendingLeavesIntent extends NavIntent {
  const PendingLeavesIntent();
}

/// النيّة المعلّقة — واحدةٌ في كل مرّة، لأن التنقّل واحد.
///
/// ⚠️ `Notifier` لا `StateProvider`: الأخيرة أُزيلت في Riverpod 3، والمستودع يستعمل
/// `NotifierProvider` في `session.dart` — **تُتبع السابقة العاملة**.
class NavIntentNotifier extends Notifier<NavIntent?> {
  @override
  NavIntent? build() => null;

  void set(NavIntent intent) => state = intent;

  /// يقرأ النيّة إن كانت من النوع المطلوب **بلا أن يمسّ الحالة** — آمنٌ داخل `initState`.
  ///
  /// ⚠️ **لا يقرأ نيّةً لغيره:** لو فُتحت شاشةٌ أخرى قبل الوجهة المقصودة لضاعت النيّة
  /// في الطريق، فتظهر الوجهة بلا فلترٍ ويبدو الزرّ معطوباً.
  T? peek<T extends NavIntent>() {
    final current = state;
    return current is T ? current : null;
  }

  /// يمسح النيّة **إن كانت ما تزال هي بعينها**.
  ///
  /// ⚠️ الشرط ليس احتياطاً زائداً: المسح مؤجَّلٌ إلى ما بعد الإطار، وقد يكتب المستخدم
  /// في تلك الأثناء نيّةً جديدة — فمسحٌ غير مشروط كان **يبتلع النيّة التالية**.
  void clearIf(NavIntent intent) {
    if (identical(state, intent)) state = null;
  }
}

final navIntentProvider =
    NotifierProvider<NavIntentNotifier, NavIntent?>(NavIntentNotifier.new);

/// اختصارٌ للوجهة: اقرأ نيّتك في `initState`، وتُمسَح **بعد اكتمال الإطار**.
///
/// 🔴 **لماذا التأجيل؟** كان المسح يقع فوراً داخل `initState`، فيرمي Riverpod
/// «Tried to modify a provider while the widget tree was building» — تعديلُ مزوّدٍ أثناء
/// البناء ممنوع لأنه قد يجعل ودجتَين تقرآن الحالة نفسها فتريان قيمتين مختلفتين.
/// (بلاغ المالك 2026-08-06 عند فتح «إجازات بانتظار الموافقة».)
///
/// 🔴 **ولماذا لم يكشفه اختباري؟** لأنه كان يستدعي `NavIntentNotifier` على
/// `ProviderContainer` مجرَّد **بلا شجرة ودجات**، فلا طورَ بناءٍ أصلاً ولا تأكيد.
/// اختبرتُ المنطق ولم أختبر **المكان الذي يُستدعى منه** — والحارس البديل في
/// `nav_intent_test.dart` صار يبني شجرةً حقيقية.
///
/// والقراءة تبقى **متزامنة** عمداً: الشاشة تحتاج الفلتر في أول بناء، ولو أُجّلت
/// القراءة أيضاً لظهرت القائمة كاملةً ثم قفزت — ووميضٌ كهذا يبدو عطلاً.
T? takeNavIntent<T extends NavIntent>(WidgetRef ref) {
  final notifier = ref.read(navIntentProvider.notifier);
  final intent = notifier.peek<T>();
  if (intent == null) return null;

  WidgetsBinding.instance.addPostFrameCallback((_) => notifier.clearIf(intent));
  return intent;
}
