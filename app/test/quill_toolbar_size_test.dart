// حارسُ **مقاس شريط أدوات المحرر** — بلاغ المالك 2026-09-21: «يأخذ الكثير من المساحة».
//
// 🔴 **ولماذا يحرس الإعدادَ لا الارتفاعَ المقيس؟** حاولتُ قياس الارتفاع فعلاً، فتبيّن أن
//    `QuillSimpleToolbar` **يتمدّد ليملأ ما يُعطى**: قِيس **1000** بارتفاعٍ محدود
//    و**100000** بغير محدود — أي أن القياس يقيس **القيد لا المحتوى**، و`Wrap` الداخليّ
//    لا يظهر للباحث في شجرة الاختبار.
//    🔑 **وحارسٌ يقيس الشيء الخطأ أسوأ من غيابه**، فحُرس **القرار** نفسه: الأرقام التي
//    صُغِّرت، والأدوات التي **لم** تُحذف.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/quill_toolbar.dart';

void main() {
  group('📏 المقاس صُغِّر — والأرقام مثبّتة', () {
    test('🔴 الزرّ: أيقونة **13** وعامل **1.45** ⇒ ~18.85 بكسلاً', () {
      // الافتراض في `flutter_quill`: 15 × 1.6 ⇒ 24 بكسلاً. أي **~21٪ أقصر في كل صفّ**.
      final base = kQuillButtonOptions.base;
      expect(base.iconSize, 13);
      expect(base.iconButtonFactor, 1.45);

      final buttonPx = base.iconSize! * base.iconButtonFactor!;
      expect(buttonPx, lessThan(24), reason: 'يجب أن يكون أصغر من الافتراض 15×1.6');
      // ⚠️ **وحدٌّ أدنى مقصود**: الزرُّ هدفُ نقرٍ بالفأرة، ودون ~18 بكسلاً تحتاج
      //    الإصابة تصويباً — **ومساحةٌ تُكسب بخطأٍ في النقر ليست مكسباً**.
      expect(buttonPx, greaterThanOrEqualTo(18));
    });

    test('🔑 والمكسبُ الأكبر في **عدد الصفوف** لا حجم الزرّ', () {
      // الشريط `Wrap`: كلُّ ما يُضيّق العنصر يُدخل أزراراً أكثر في الصفّ
      // **فيسقط صفٌّ كامل دفعةً واحدة**.
      expect(kQuillToolbarConfig.showDividers, isFalse,
          reason: 'الفواصل زينةٌ تأخذ عرضاً — والأقسام تتمايز بالتباعد');
      expect(kQuillToolbarConfig.toolbarSectionSpacing, 2);
      expect(kQuillToolbarConfig.toolbarRunSpacing, 2);
    });
  });

  group('🧰 وما لم يتغيّر — الوظائف', () {
    test('🔑 لم يُحذف زرٌّ واحد: التقليصُ في المقاس لا في الأدوات', () {
      // حذفُ الأزرار يوفّر مساحةً اليوم و**يكلّف بلاغاً غداً** حين يحتاجها المستخدم.
      expect(kQuillToolbarConfig.showAlignmentButtons, isTrue);
      expect(kQuillToolbarConfig.showFontFamily, isTrue);
      expect(kQuillToolbarConfig.showFontSize, isTrue);
      expect(kQuillToolbarConfig.showBoldButton, isTrue);
      expect(kQuillToolbarConfig.showItalicButton, isTrue);
      expect(kQuillToolbarConfig.showUnderLineButton, isTrue);
      expect(kQuillToolbarConfig.showColorButton, isTrue);
      expect(kQuillToolbarConfig.showListBullets, isTrue);
      expect(kQuillToolbarConfig.showListNumbers, isTrue);
    });

    test('🔴 و`multiRowsDisplay` باقٍ — فلا يختفي زرٌّ خلف حافةِ تمرير', () {
      // صفٌّ واحد يُمرَّر أفقياً يُخفي نصف الأزرار **بلا أن يعلم المستخدم أن خلفها شيئاً**.
      // 🔑 **وإخفاءُ أداةٍ أسوأ من إظهارها صغيرة.**
      expect(kQuillToolbarConfig.multiRowsDisplay, isTrue);
    });

    test('📐 والأحجام والخطوط كما هي', () {
      expect(kQuillFontSizes.length, greaterThanOrEqualTo(16));
      expect(kQuillFontSizes.keys, contains('72'));
      expect(kQuillFontFamilies.keys, contains('Amiri'));
      expect(kQuillFontFamilies.keys, contains('Times New Roman'));
    });

    test('⚠️ وما كان مخفياً يبقى مخفياً — فلا يعود ما أُزيل عمداً', () {
      expect(kQuillToolbarConfig.showCodeBlock, isFalse);
      expect(kQuillToolbarConfig.showInlineCode, isFalse);
      expect(kQuillToolbarConfig.showQuote, isFalse);
      expect(kQuillToolbarConfig.showSearchButton, isFalse);
      expect(kQuillToolbarConfig.showSubscript, isFalse);
      expect(kQuillToolbarConfig.showSuperscript, isFalse);
      expect(kQuillToolbarConfig.showListCheck, isFalse);
    });
  });

  group('🖼️ الرسمُ والارتفاع المقيس', () {
    // 🔴 **`FlutterQuillLocalizations.delegate` إلزاميّ** — بدونه يرمي كلُّ زرٍّ
    //    `MissingFlutterQuillLocalizationException` فلا يُبنى الشريط أصلاً.
    //    🔑 **وهو ما جعل القياس الأوّل يعود بارتفاع الشاشة**: كان يقيس هيكلاً فارغاً.
    Future<double> build(WidgetTester tester, double w) async {
      final controller = quill.QuillController.basic();
      addTearDown(controller.dispose);

      tester.view.physicalSize = Size(w, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        // ⚠️ **الإنجليزية في الاختبار عمداً**:  لا يدعم العربية في كل
        //    `flutter_quill` لا يدعم العربية في كل مفوّضاته فيُطلق تحذيراً يُفشل
        //    `takeException`. والفروق نصّيةٌ في تلميحات
        //    لا في مقاس الأزرار — **فالقياس لا يتأثّر**.
        supportedLocales: const [Locale('en')],
        locale: const Locale('en'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: quill.QuillSimpleToolbar(
              controller: controller,
              config: kQuillToolbarConfig,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final wrap = find.descendant(
        of: find.byType(quill.QuillSimpleToolbar),
        matching: find.byType(Wrap),
      );
      return wrap.evaluate().isEmpty ? -1 : tester.getSize(wrap.first).height;
    }

    for (final w in <double>[440, 620, 900, 1300]) {
      testWidgets('يُرسم بلا استثناء عند ${w.toInt()} بكسل', (tester) async {
        await build(tester, w);
        expect(tester.takeException(), isNull);
      });
    }

    // 🔴 **سقوفٌ مقيسةٌ بالتشغيل — لا مُقدَّرة.** قِيس الارتفاع بالإعداد القديم
    //    (أيقونة 15 · عامل 1.6 · فواصل ظاهرة · تباعد 4) ثم بالجديد:
    //
    //        العرض 620  :  152 ⟵ **98**   (ثلاثةُ صفوفٍ صارت صفّين)
    //        العرض 900  :  100 ⟵ **98**
    //        العرض 1300 :  100 ⟵ **48**   (صفّان صارا **صفّاً واحداً**)
    //
    // 🔑 **والمكسبُ في عدد الصفوف لا في حجم الزرّ** — ولهذا يقفز عند عرضٍ دون آخر.
    // ⚠️ والسقوف أعلى بقليلٍ من المقيس، فلا يسقط الحارس بفروق رسمٍ طفيفة.
    for (final (w, cap) in const <(double, double)>[(620, 105), (900, 105), (1300, 55)]) {
      testWidgets('📐 عند ${w.toInt()} لا يتجاوز ${cap.toInt()} بكسلاً', (tester) async {
        final h = await build(tester, w);
        expect(h, greaterThan(0), reason: 'لم يُبنَ الشريط');
        expect(h, lessThanOrEqualTo(cap),
            reason: 'ارتفاع الشريط $h عند عرض $w — تجاوز السقف $cap');
      });
    }

    testWidgets('🔴 ويقصر كلّما اتّسع العرض — فالصفوف تُلفّ لا تُقصّ', (tester) async {
      final narrow = await build(tester, 620);
      final wide = await build(tester, 1300);
      expect(narrow, greaterThan(0), reason: 'لم يُبنَ الشريط');
      expect(wide, lessThan(narrow));
    });
  });
}
