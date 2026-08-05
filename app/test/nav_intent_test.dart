import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/nav_intent.dart';

/// **نيّة التنقّل** — الآلية التي أغلقت الفجوة G11 وبلاغ المالك ٨ معاً.
///
/// ⚠️ سلوكها الحرج ليس «تصل النيّة» بل **«تُمسح بعد الوصول»** و**«لا يأخذها غير صاحبها»**.
/// الأولى بلا حارس تجعل الزيارة الثانية للشاشة تُطبّق فلتراً لم يطلبه أحد؛ والثانية تجعل
/// شاشةً تبتلع نيّة شاشةٍ أخرى فيبدو الزرّ الأصلي معطوباً.
///
/// 🔴 **ودرسُ هذا الملف نفسه (بلاغ المالك 2026-08-06):** كانت اختباراته كلها على
/// `ProviderContainer` مجرَّد — **بلا شجرة ودجات**. فمرّت خضراء بينما التطبيق يرمي
/// «Tried to modify a provider while the widget tree was building» عند أول فتحٍ حقيقي،
/// لأن `takeNavIntent` كان يمسح الحالة داخل `initState`.
/// ⇒ **اختبارُ المنطق لا يختبر المكان الذي يُستدعى منه.** أُضيفت أدناه اختباراتٌ
/// **تبني شجرةً وتستدعيه من `initState`** كما يفعل التطبيق بالضبط.
void main() {
  group('المنطق المجرَّد', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    NavIntentNotifier get() => container.read(navIntentProvider.notifier);

    test('لا نيّة في البداية', () {
      expect(container.read(navIntentProvider), isNull);
    });

    test('النيّة تصل إلى صاحبها بقيمتها', () {
      get().set(const OutgoingStatusIntent('Draft'));
      expect(get().peek<OutgoingStatusIntent>()?.status, 'Draft');
    });

    test('🔴 شاشةٌ لا تقرأ نيّة شاشةٍ أخرى ولا تمسحها', () {
      get().set(const PendingLeavesIntent());

      expect(get().peek<OutgoingStatusIntent>(), isNull);
      expect(container.read(navIntentProvider), isA<PendingLeavesIntent>());

      expect(get().peek<PendingLeavesIntent>(), isNotNull);
    });

    test('🔴 المسح مشروطٌ بأنها ما تزال هي — فلا يبتلع نيّةً جديدة', () {
      const first = OutgoingStatusIntent('Draft');
      get().set(first);
      // نيّةٌ جديدة قبل أن يقع المسح المؤجَّل للأولى.
      get().set(const PendingLeavesIntent());

      get().clearIf(first);
      expect(container.read(navIntentProvider), isA<PendingLeavesIntent>(),
          reason: 'مسحٌ غير مشروط كان سيبتلع النيّة التالية');
    });

    test('نيّةٌ جديدة تحلّ محلّ القديمة — التنقّل واحد', () {
      get().set(const OutgoingStatusIntent('Draft'));
      get().set(const OutgoingStatusIntent('Final'));
      expect(get().peek<OutgoingStatusIntent>()!.status, 'Final');
    });
  });

  // ───────────────── الاستدعاء من شجرةٍ حقيقية — حيث سكن العيب ─────────────────

  group('داخل شجرة ودجات حقيقية', () {
    testWidgets('🔴 `takeNavIntent` من `initState` لا يرمي تأكيد Riverpod', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(navIntentProvider.notifier).set(const OutgoingStatusIntent('Draft'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Destination<OutgoingStatusIntent>()),
      ));

      // هذا بالضبط ما فشل عند المالك: التأكيد يُرمى أثناء بناء الشجرة.
      expect(tester.takeException(), isNull);
      expect(find.text('Draft'), findsOneWidget,
          reason: 'الفلتر يجب أن يُطبَّق في **أول** بناء، لا بعد وميض');
    });

    testWidgets('🔴 وتُمسح بعد اكتمال الإطار فلا تلتصق بالزيارة الثانية', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(navIntentProvider.notifier).set(const OutgoingStatusIntent('Draft'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Destination<OutgoingStatusIntent>()),
      ));
      // قبل انتهاء الإطار ما تزال موجودة؛ وبعده تُمسح.
      await tester.pump();

      expect(container.read(navIntentProvider), isNull,
          reason: 'نيّةٌ باقية تجعل الزيارة التالية تُطبّق فلتراً لم يطلبه أحد');
    });

    testWidgets('شاشةٌ لا تخصّها النيّة لا تمسحها من الشجرة أيضاً', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(navIntentProvider.notifier).set(const PendingLeavesIntent());

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Destination<OutgoingStatusIntent>()),
      ));
      await tester.pump();

      expect(container.read(navIntentProvider), isA<PendingLeavesIntent>());
      expect(find.text('بلا نيّة'), findsOneWidget);
    });
  });
}

/// شاشةُ وجهةٍ مصغَّرة تستدعي `takeNavIntent` من `initState` **كما تفعل الشاشات الحقيقية**.
class _Destination<T extends NavIntent> extends ConsumerStatefulWidget {
  const _Destination();
  @override
  ConsumerState<_Destination<T>> createState() => _DestinationState<T>();
}

class _DestinationState<T extends NavIntent> extends ConsumerState<_Destination<T>> {
  NavIntent? _intent;

  @override
  void initState() {
    super.initState();
    _intent = takeNavIntent<T>(ref);
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_intent) {
      OutgoingStatusIntent(:final status) => status,
      PendingLeavesIntent() => 'إجازات',
      _ => 'بلا نيّة',
    };
    return Scaffold(body: Center(child: Text(label)));
  }
}
