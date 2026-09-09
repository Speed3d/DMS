import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/widgets/custom_card.dart';

/// حارس **«`ListTile` داخل بطاقة»** — عائلةٌ ظهرت ثلاث مرّات (بلاغ المالك 2026-09-09).
///
/// 🔴 **العلّة:** `ListTile` و`SwitchListTile` و`InkWell` يرسمون **خلفيتهم وأثر نقرهم على
/// أقرب `Material` فوقهم**. و[CustomCard] بطاقةٌ من `DecoratedBox` بلونٍ وظلال — فتحجبهما،
/// وترمي Flutter في وضع التصحيح:
/// «ListTile background color or ink splashes may be invisible».
///
/// ⚠️ **وعولجت مرّتين بلفٍّ يدويّ في شاشتين** (`employee_form` · `hr_settings`) فبقيت
/// **سبعة عشر موضعاً** تنتظر بلاغاً — حتى جاء. **فنُقل العلاج إلى البطاقة نفسها**، ومَن
/// يكتب شاشةً جديدة لا يحتاج أن يعرف القاعدة أصلاً.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: SizedBox(width: 600, child: child))),
        ),
      );

  group('🃏 البطاقة تُتيح سطحاً للرسم', () {
    testWidgets('`SwitchListTile` داخل [CustomCard]: بلا استثناء', (tester) async {
      await tester.pumpWidget(wrap(
        CustomCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('خيارٌ ما'),
            value: true,
            onChanged: (_) {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('و`CheckboxListTile` كذلك', (tester) async {
      await tester.pumpWidget(wrap(
        CustomCard(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('خيارٌ ما'),
            value: true,
            onChanged: (_) {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('و`ListTile` مُختاراً بخلفية', (tester) async {
      // 🔴 **الحالة التي ترمي فعلاً**: خلفيةٌ على البلاطة تحتاج سطحاً ترسم عليه.
      await tester.pumpWidget(wrap(
        const CustomCard(
          child: ListTile(
            selected: true,
            selectedTileColor: Color(0x22FFFFFF),
            title: Text('عنصرٌ مُختار'),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('🔒 والحارس يقيس شيئاً — التركيب الخاطئ يرمي فعلاً', () {
    // ⚠️ **بلا هذه الحالة يمرّ الحارسُ أعلاه ولو أُزيل العلاج** — فحارسٌ لا يُرى فاشلاً
    //    على العيب لا يُوثَق (قاعدة مسجَّلة). وهذه تُعيد بناء التركيب المعطوب **يدوياً**:
    //    `DecoratedBox` بلونٍ يلفّ البلاطة بلا `Material`.
    testWidgets('`DecoratedBox` بلونٍ بلا `Material` يرمي', (tester) async {
      await tester.pumpWidget(wrap(
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1B30),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const ListTile(
            selected: true,
            selectedTileColor: Color(0x22FFFFFF),
            title: Text('عنصرٌ مُختار'),
          ),
        ),
      ));
      expect(tester.takeException(), isNotNull,
          reason: 'لو لم يرمِ هنا فالحارس أعلاه لا يقيس شيئاً');
    });
  });
}
