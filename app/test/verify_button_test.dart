import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاس **زرّ التحقق من QR** (ADR-043).
///
/// 🔴 **العيب الذي وُلدوا منه**: كان الزرّ `onPressed: () {}` — **قشرةً فارغة تُرسم وتستجيب
/// بصرياً ولا تفعل شيئاً**، ونقطةُ `POST /api/verify` جاهزةٌ في الخادم منذ Phase 0 **بلا
/// عميلٍ يستدعيها**. وهذا **سابع تكرارٍ** لنمط «ميزةٌ بلا مدخل» في المشروع.
///
/// 🔑 **ولا يكفي حارسٌ يبني الشاشة**: الشاشة كانت ستُبنى سليمةً وهي لا تُفتح من أحد.
/// فالحرّاس هنا تفحص **الوصل** لا الرسم.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('🔗 الزرّ موصولٌ فعلاً', () {
    test('🔴 لا `onPressed: () {}` فارغة في الشريط العلوي', () {
      final src = read('lib/widgets/topbar.dart');

      // ⚠️ تُتجاهل التعليقات — فالنمط مذكورٌ فيها بوصفه العيب المُعالَج.
      final offenders = <String>[];
      for (final line in src.split(String.fromCharCode(10))) {
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        if (RegExp(r'onPressed:\s*\(\)\s*\{\s*\}').hasMatch(code)) offenders.add(code.trim());
      }

      expect(offenders, isEmpty,
          reason: 'زرٌّ يُرسم ولا يفعل شيئاً — وهو بعينه العيب الذي عالجه ADR-043');
    });

    test('وزرّ التحقق يفتح شاشة التحقق', () {
      final src = read('lib/widgets/topbar.dart');
      expect(src, contains('VerifyScreen'),
          reason: 'الشريط العلوي لا يعرف شاشة التحقق أصلاً');
      expect(src, contains('_openVerify'));
    });

    test('🔴 وتُفتح بمسارٍ لا بحوار', () {
      // قاعدةٌ مسجَّلة: حقولُ النصّ داخل `showDialog` تُسقط الرسم على الويب.
      final src = read('lib/screens/verify_screen.dart');
      expect(src, contains('TextField'));
      expect(read('lib/widgets/topbar.dart'), contains('MaterialPageRoute'));
    });
  });

  group('📱 ولا يغيب عن الشاشة الضيّقة', () {
    test('🔴 للزرّ مدخلٌ ثانٍ دون 900 بكسل', () {
      // **كان يختفي كلّيّاً دون 900** — فتغيب الميزة عمّن يفتح النظام من هاتفه، وهو
      // أوّل من يحتاج ماسحاً. الآن أيقونةٌ في الوضع الضيّق.
      final src = read('lib/widgets/topbar.dart');
      expect(src, contains('isMedium && !isVerySmall'),
          reason: 'لا مدخل للتحقق على الشاشة الضيّقة');
    });
  });

  group('🌐 والعميل يستدعي النقطة الجاهزة', () {
    test('`verifyQr` موجودة وتنادي `/verify`', () {
      final src = read('lib/core/api_client.dart');
      expect(src, contains('verifyQr'), reason: 'لا دالّة تحقّق في عميل الـAPI');
      expect(src, contains("'/verify'"));
    });

    test('🔴 والشاشة تفرّق بين ثلاث حالات لا اثنتين', () {
      // توقيعٌ صحيحٌ لكتابٍ مسحوب **ليس «صحيحاً»** — ودمجُ الحالتين يُخفي معلومةً
      // يحتاجها من يقرّر الاعتماد على الورقة.
      final src = read('lib/screens/verify_screen.dart');
      expect(src, contains('foundInDb'));
      expect(src, contains('تم التلاعب بالكتاب'));
      expect(src, contains('تم إصدار هذا الكتاب فعلاً من الشركة'));
      expect(src, contains('ليس في السجلّ'));
    });
  });
}
