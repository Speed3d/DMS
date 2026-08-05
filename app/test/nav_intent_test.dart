import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/nav_intent.dart';

/// **نيّة التنقّل** — الآلية التي أغلقت الفجوة G11 وبلاغ المالك ٨ معاً.
///
/// ⚠️ سلوكها الحرج ليس «تصل النيّة» بل **«تُمسح بعد الوصول»** و**«لا يأخذها غير صاحبها»**.
/// الأولى بلا حارس تجعل الزيارة الثانية للشاشة تُطبّق فلتراً لم يطلبه أحد؛ والثانية تجعل
/// شاشةً تبتلع نيّة شاشةٍ أخرى فيبدو الزرّ الأصلي معطوباً.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  NavIntentNotifier get() => container.read(navIntentProvider.notifier);

  test('لا نيّة في البداية', () {
    expect(container.read(navIntentProvider), isNull);
  });

  test('النيّة تصل إلى صاحبها بقيمتها', () {
    get().set(const OutgoingStatusIntent('Draft'));

    final taken = get().take<OutgoingStatusIntent>();
    expect(taken, isNotNull);
    expect(taken!.status, 'Draft');
  });

  test('🔴 النيّة تُمسح بعد أخذها — فلا تلتصق بالزيارة الثانية', () {
    get().set(const OutgoingStatusIntent('Draft'));

    expect(get().take<OutgoingStatusIntent>(), isNotNull);
    // الزيارة الثانية للشاشة نفسها: لا نيّة، فتُعرض القائمة كاملةً كما يتوقّع المستخدم.
    expect(get().take<OutgoingStatusIntent>(), isNull);
    expect(container.read(navIntentProvider), isNull);
  });

  test('🔴 شاشةٌ لا تبتلع نيّة شاشةٍ أخرى', () {
    get().set(const PendingLeavesIntent());

    // شاشة الصادر تُفتح في الطريق: لا تأخذ النيّة ولا تمسحها.
    expect(get().take<OutgoingStatusIntent>(), isNull);
    expect(container.read(navIntentProvider), isA<PendingLeavesIntent>());

    // فتصل سليمةً إلى صاحبتها.
    expect(get().take<PendingLeavesIntent>(), isNotNull);
  });

  test('نيّةٌ جديدة تحلّ محلّ القديمة — التنقّل واحد', () {
    get().set(const OutgoingStatusIntent('Draft'));
    get().set(const OutgoingStatusIntent('Final'));

    expect(get().take<OutgoingStatusIntent>()!.status, 'Final');
    expect(container.read(navIntentProvider), isNull);
  });
}
