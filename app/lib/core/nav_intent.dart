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

  /// يقرأ النيّة إن كانت من النوع المطلوب **ويمسحها**، وإلا يُعيد `null` ولا يمسّ شيئاً.
  ///
  /// ⚠️ **لا يمسح نيّةً لغيره:** لو فُتحت شاشةٌ أخرى قبل الوجهة المقصودة لضاعت النيّة
  /// في الطريق، فتظهر الوجهة بلا فلترٍ ويبدو الزرّ معطوباً.
  T? take<T extends NavIntent>() {
    final current = state;
    if (current is! T) return null;
    state = null;
    return current;
  }
}

final navIntentProvider =
    NotifierProvider<NavIntentNotifier, NavIntent?>(NavIntentNotifier.new);

/// اختصارٌ للوجهة: اقرأ نيّتك وامسحها في `initState`.
T? takeNavIntent<T extends NavIntent>(WidgetRef ref) =>
    ref.read(navIntentProvider.notifier).take<T>();
