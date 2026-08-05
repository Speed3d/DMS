import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/widgets/custom_card.dart';

/// حرّاس رسم شاشات الوحدة.
///
/// ⚠️ **سبب وجودها:** أبلغ المالك عن تأكيدٍ يرميه Flutter عند فتح إعدادات الوحدة:
/// «ListTile background color or ink splashes may be invisible».
/// السبب أن `ListTile` يرسم خلفيته وأثر النقر على **أقرب `Material` فوقه**، و`CustomCard`
/// هي `DecoratedBox` ذات خلفية تحجبهما. اختباراتُ العقد والوحدة لا تلتقط هذا **لأنها لا
/// ترسم** — يلتقطه بناءُ الشجرة فعلاً.
///
/// > **الدرس:** عطبُ التخطيط لا يُكتشف إلا بالرسم. اختبارٌ يتحقّق من البيانات وحدها
/// > يترك نصف الواجهة بلا حارس.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('SwitchListTile داخل CustomCard لا يرمي تأكيد Material', (tester) async {
    // هذا بالضبط تركيب شاشة إعدادات الوحدة ونموذج الموظف.
    await pump(
      tester,
      CustomCard(
        child: Column(
          children: [
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: true,
                title: const Text('تفعيل مكافأة نهاية الخدمة'),
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('تفعيل مكافأة نهاية الخدمة'), findsOneWidget);
  });

  testWidgets('وبدون Material يرمي التأكيد — إثبات أن الحارس له أسنان', (tester) async {
    await pump(
      tester,
      CustomCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: true,
          title: const Text('بلا Material'),
          onChanged: (_) {},
        ),
      ),
    );

    // لو توقّف Flutter عن رمي هذا التأكيد يوماً، يسقط الاختبار فنعلم أن الالتفاف
    // لم يعد لازماً — بدل أن يبقى في الكود بلا سبب معروف.
    expect(tester.takeException(), isA<FlutterError>());
  });
}
