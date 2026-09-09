import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاس **إعداد النشر** — وُلدوا من مراجعة دليل النشر قبل شراء السيرفر.
///
/// 🔑 **ما يميّزهم:** كلُّ ما يحرسونه **يعمل تماماً على جهاز التطوير ويسقط في الإنتاج
/// وحده**. فلا اختبارٌ وظيفيّ ولا تشغيلٌ محليّ يكشفه — يكشفه المالك بعد النشر أو لا يُكشف.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('🌐 عنوان الـAPI يُحقن عند البناء', () {
    test('🔴 لا عنوان `localhost` ثابتاً في الكود', () {
      // **العيب**: حزمة الويب تُنفَّذ في متصفّح الزائر، فعنوانٌ ثابت على `localhost`
      // يعني أن كل مستخدمٍ يطلب الـAPI **من جهازه هو**. شاشة الدخول تظهر ولا يعمل الدخول.
      final src = read('lib/core/session.dart');
      expect(src, contains("String.fromEnvironment("),
          reason: 'عنوان الـAPI ثابت — لا يمكن توجيهه إلى السيرفر عند البناء');
      expect(src, contains("'API_BASE_URL'"),
          reason: 'اسم وسم البناء مختلف عمّا توثّقه خطة النشر');
    });

    test('ويبقى الافتراض بيئة التطوير كما كانت', () {
      // ⚠️ الحقن يجب ألّا يغيّر شيئاً لمن يشغّل النظام محلياً بلا وسوم.
      expect(read('lib/core/session.dart'), contains('http://localhost:5080/api'));
    });
  });

  group('🗂️ ملف IIS يُبنى مع الواجهة', () {
    test('🔴 `web/web.config` موجود — فينسخه كل `flutter build web`', () {
      expect(File('web/web.config').existsSync(), isTrue,
          reason: 'بلا هذا الملف يجب أن يُنشأ يدوياً على السيرفر بعد كل تحديث — ويُنسى');
    });

    test('🔴 ويعرّف نوع `.wasm`', () {
      // IIS لا يعرفه افتراضياً ⇒ 404 على canvaskit.wasm ⇒ **صفحةٌ بيضاء بلا خطأ مفهوم**.
      final cfg = read('web/web.config');
      expect(cfg, contains('.wasm'));
      expect(cfg, contains('application/wasm'));
    });

    test('⚠️ وبلا قاعدة `rewrite` — الوحدة غير مثبّتة على IIS افتراضياً', () {
      // قاعدةٌ تحتاج URL Rewrite تجعل الموقع يردّ **500 على كل طلب** لا على المسارات
      // غير الموجودة وحدها.
      // ⚠️ **تُنزَع تعليقات XML أولاً** — القرار مشروحٌ داخل الملف بذكر الوسم نفسه،
      //    وحارسٌ يسقط على توثيقه حارسٌ يُعلّم حذفَ الشرح لا إصلاحَ العيب.
      final xml = read('web/web.config').replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(xml.contains('<rewrite'), isFalse,
          reason: 'قاعدة rewrite تُسقط الموقع كلَّه إن لم تُثبَّت الوحدة');
    });

    test('🔴 والتوجيه يبقى بـ`#/` — وإلا لزمت قاعدة rewrite فعلاً', () {
      // الحارسان مقترنان: غيابُ `usePathUrlStrategy` **هو** ما يجعل غياب rewrite سليماً.
      // فمن يضيفها لاحقاً يجب أن يسقط هنا لا أن يكتشفها من صفحةٍ بيضاء بعد النشر.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('usePathUrlStrategy')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'مسارات المتصفّح صارت بلا `#` — يلزم rewrite في web.config ووحدةٌ على IIS');
    });
  });
}
