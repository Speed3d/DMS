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
const double kChipBreakpoint = 920;

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

  // ─────────── الدفعة ٢: شريط أدوات قائمة الموظفين بعد إضافة مِرشَّح الإجازات ───────────
  //
  // ⚠️ **الخطر الحقيقي في هذه الدفعة**: أُقحم عنصرٌ رابع (~240 بكسل) في شريطٍ أفقيّ يسع
  //    بحثاً وفلتراً وزرّ إضافة. وهذا **بالضبط** صنف العطل الذي بلّغ عنه المالك في جدول
  //    الرواتب («RIGHT OVERFLOWED BY 94 PIXELS»). العلاج رفعُ عتبة التضييق حين يظهر
  //    المِرشَّح، والحارس هنا يُثبت أن العتبة تكفي فعلاً **بالرسم لا بالحساب الذهني**.

  /// يبني شريط الأدوات بالتركيب نفسه المستعمل في `employee_list_screen.dart`.
  ///
  /// ⚠️ **نسخةٌ مطابقة، وهذا قيدُها:** الودجات هناك خاصّة (`_StatusFilter` و
  /// `_PendingLeavesChip`) فلا تُستورَد. فإن تغيّر أحدها ولم يتغيّر هنا **صار الحارس
  /// يحرس شيئاً آخر**. وقد وقع ذلك فعلاً أول مرّة: كتبتُ الفلتر `SegmentedButton` بثلاث
  /// تسميات (~450 بكسل) وهو في الواقع **قائمة منسدلة** (~180)، فأبلغ الاختبار عن فيضٍ
  /// في تخطيطٍ سليم. ⇒ **أيُّ تعديلٍ على الشريط يُنسَخ إلى هنا في النَّفَس نفسه.**
  Widget toolbar({required double width, required bool withChip}) {
    // مطابقٌ لـ`_PendingLeavesChip`.
    final chip = SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.beach_access_rounded, size: 18),
        label: const Text('إجازات بانتظار الموافقة (12)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
      ),
    );
    // مطابقٌ لـ`_StatusFilter`: قائمة منسدلة داخل إطارٍ بحشو أفقي 14.
    final filter = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool?>(
          value: true,
          items: const [
            DropdownMenuItem(value: true, child: Text('على رأس العمل')),
            DropdownMenuItem(value: false, child: Text('منتهو الخدمة')),
            DropdownMenuItem(value: null, child: Text('الكل')),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    final add = SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('موظف جديد',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );

    final isSmall = width < (withChip ? kChipBreakpoint : 620);

    return SizedBox(
      width: width,
      child: isSmall
          ? Column(children: [
              Container(height: 48, color: Colors.grey.shade200),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: filter), const SizedBox(width: 12), add]),
              if (withChip) ...[const SizedBox(height: 12), chip],
            ])
          : Row(children: [
              Expanded(child: Container(height: 48, color: Colors.grey.shade200)),
              if (withChip) ...[const SizedBox(width: 12), chip],
              const SizedBox(width: 12),
              filter,
              const SizedBox(width: 12),
              add,
            ]),
    );
  }

  for (final w in <double>[620, 700, 880, 900, 920, 1100, 1600]) {
    for (final withChip in [false, true]) {
      testWidgets(
        'شريط أدوات الموظفين لا يفيض عند $w بكسل ${withChip ? "مع" : "بلا"} مِرشَّح الإجازات',
        (tester) async {
          tester.view.physicalSize = Size(w, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await pump(tester, toolbar(width: w, withChip: withChip));

          // فيضُ التخطيط في Flutter استثناءٌ يُرمى وقت الرسم — فيلتقطه `takeException`.
          expect(tester.takeException(), isNull,
              reason: 'فيض تخطيط عند العرض $w');
        },
      );
    }
  }
}
