import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/screens/employee_list_screen.dart'
    show kEmpToolbarNarrow, kEmpToolbarNarrowWithChip;
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
///
/// 🔴 **العتبتان تُستوردان من الشاشة ولا تُكتبان هنا (2026-08-06).** كانت `kChipBreakpoint`
/// نسخةً محلّية بقيمة 920، فلو تغيّرت الشاشة وحدها لبقي الحارس يُثبت سلامة عتبةٍ **مهجورة**
/// ويمرّ أخضرَ بينما المستخدم يرى الفيض. النسخة المطابقة للودجات قيدٌ لا مفرّ منه (خاصّة
/// هي)، أمّا الأرقام فلا عذر في ازدواجها.

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
  Widget toolbar({required double width, required bool withChip, bool forceWide = false}) {
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
    // مطابقٌ لزرّ «إضافة موظف قائم» (ADR-027) — العنصر الخامس في الشريط.
    final link = SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.person_search_rounded, size: 18),
        label: const Text('إضافة موظف قائم',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
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

    final isSmall = !forceWide &&
        width < (withChip ? kEmpToolbarNarrowWithChip : kEmpToolbarNarrow);

    return SizedBox(
      width: width,
      child: isSmall
          ? Column(children: [
              Container(height: 48, color: Colors.grey.shade200),
              const SizedBox(height: 12),
              // `Wrap` لا `Row`: ثلاثة عناصر ثابتة العرض في صفٍّ تفيض عند الشاشات
              // الضيّقة جداً، والـ`Wrap` ينزل بها سطراً — فلا عتبةَ ثانية تُقاس وتُصان.
              Wrap(spacing: 12, runSpacing: 12, children: [filter, link, add]),
              if (withChip) ...[const SizedBox(height: 12), chip],
            ])
          : Row(children: [
              Expanded(child: Container(height: 48, color: Colors.grey.shade200)),
              if (withChip) ...[const SizedBox(width: 12), chip],
              const SizedBox(width: 12),
              filter,
              const SizedBox(width: 12),
              link,
              const SizedBox(width: 12),
              add,
            ]),
    );
  }

  // العروض المختبَرة تشمل **العتبتين بالضبط** — وهو أضيق عرضٍ يُرسم فيه الصفّ العريض،
  // أي أخطر نقطة فيه. و**420** حالةُ الفجوة G12 التي رصدها الحارس ولم يُبلّغ عنها المالك.
  for (final w in <double>[
    380, 420, 620, 700, 900,
    kEmpToolbarNarrow, kEmpToolbarNarrow + 1,
    1100, 1280,
    kEmpToolbarNarrowWithChip, kEmpToolbarNarrowWithChip + 1,
    1600,
  ]) {
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

  // ─────────── «يعمل أيضاً في»: اسم شركةٍ طويل لا يفيض ببطاقة الموظف (ADR-027) ───────────
  //
  // ⚠️ `Wrap` يحمي من **تعدّد** الرقاقات لا من **رقاقةٍ واحدة** أعرض من السطر. والبطاقة صارت
  //    تعرض أسماء شركاتٍ يكتبها المستخدم بلا حدّ طول — فالقصّ بثلاث نقاط هو الحارس.
  testWidgets('اسم شركةٍ طويل في رقاقة «يعمل أيضاً في» يُقصّ ولا يفيض', (tester) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // مطابقٌ لـ`_Chip` بعد إضافة `Flexible` — لو زال القصّ من الشاشة سقط هذا.
    Widget chipLike(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apartment_rounded, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    await pump(
      tester,
      SizedBox(
        width: 300,
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          const Text('يعمل أيضاً في:'),
          chipLike('شركة أرض العرين للتجارة والمقاولات العامة المحدودة — فرع بغداد'),
        ]),
      ),
    );

    expect(tester.takeException(), isNull, reason: 'اسم شركة طويل أفاض الرقاقة');
  });

  // ─────────── حارسٌ للعتبة نفسها: أنها فوق نقطة الفيض المقيسة ───────────
  //
  // 🔴 **لماذا هذا الحارس؟** الاختبارات أعلاه تُثبت أن الصفّ سليمٌ **عند العتبة الحالية** —
  //    ولو رفعها أحدٌ إلى 5000 لبقيت خضراء وهي تُخفي شريطاً لا يظهر أبداً. وهذا يُثبت
  //    الاتجاه الآخر: أن العتبة **ليست دون** نقطة الفيض، فتبقى مربوطةً بقياسٍ حقيقي.
  testWidgets('الصفّ العريض يفيض فعلاً دون نقطة الفيض المقيسة — فالعتبة ليست زينة',
      (tester) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 640 دون النقطة المقيسة (651) — نفرض الصفّ العريض بتجاوز `isSmall`.
    await pump(tester, toolbar(width: 640, withChip: false, forceWide: true));
    expect(tester.takeException(), isNotNull,
        reason: 'لو لم يَعُد يفيض هنا فقد تغيّرت الأحجام ⇒ أعِد قياس العتبتين');
  });
}
