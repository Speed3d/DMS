// حرّاس **الشريط الماليّ** — بلاغ المالك 2026-09-21.
//
// 🔴 كان بطاقةً في **أسفل** عمود البيانات فلا تُرى إلا بتمرير — ومَن لا يرى الحقل لا
//    يملؤه. والقرار: **شريطٌ ممتدّ فوق الأعمدة الثلاثة**، وودجةٌ واحدة للشاشات الثلاث.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/widgets/financial_bar.dart';

void main() {
  late TextEditingController amount;
  late TextEditingController rate;

  setUp(() {
    amount = TextEditingController();
    rate = TextEditingController();
  });

  tearDown(() {
    amount.dispose();
    rate.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    String? currency = 'IQD',
    double width = 1100,
    ValueChanged<bool>? onEnabled,
    ValueChanged<String>? onCurrency,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FinancialBar(
            enabled: enabled,
            onEnabledChanged: onEnabled ?? (_) {},
            amount: amount,
            rate: rate,
            currency: currency,
            onCurrencyChanged: onCurrency ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('🔌 المفتاح', () {
    testWidgets('🔴 مطفأً: لا حقولَ إطلاقاً — **وشرحٌ يقول ماذا يقع لو أُشعل**',
        (tester) async {
      await pump(tester, enabled: false);

      expect(find.byType(TextField), findsNothing);
      // ⚠️ مفتاحٌ بلا شرحٍ يُترك مطفأً — وهو سببُ ألّا يُملأ الحقل أصلاً.
      expect(find.textContaining('فعّله لإدخال مبلغ'), findsOneWidget);
      expect(find.text('التفاصيل المالية'), findsOneWidget);
    });

    testWidgets('✅ مشتعلاً: المبلغ والعملة يظهران', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(TextField, 'المبلغ'), findsOneWidget);
      expect(find.text('دينار'), findsOneWidget);
      expect(find.text('دولار'), findsOneWidget);
    });

    testWidgets('🔀 والضغط يُبلّغ صاحب الشاشة — **ولا يحتفظ الشريط بالحالة**',
        (tester) async {
      // 🔑 الحالة ملكُ الشاشة لأنها تحفظها وتقرؤها من الخادم (`amount != null`).
      bool? got;
      await pump(tester, enabled: false, onEnabled: (v) => got = v);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(got, isTrue);
      // ولم يتغيّر المعروض: الشريط عرضٌ لا حالة.
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('💱 سعرُ الصرف', () {
    testWidgets('🔴 يغيب بالدينار — حقلٌ لا معنى له يُربك ويُملأ خطأً', (tester) async {
      await pump(tester, currency: 'IQD');
      expect(find.widgetWithText(TextField, 'سعر الصرف للدينار'), findsNothing);
    });

    testWidgets('✅ ويظهر بالدولار', (tester) async {
      await pump(tester, currency: 'USD');
      expect(find.widgetWithText(TextField, 'سعر الصرف للدينار'), findsOneWidget);
    });

    testWidgets('⚠️ وعملةٌ لم تُختَر بعد (`null`) لا تُسقط الشريط', (tester) async {
      // شاشةُ الإنشاء تبدأ بلا عملة — وحقلٌ غيرُ لاغٍ كان يُجبرها على اختيارٍ لم يقع.
      await pump(tester, currency: null);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, 'المبلغ'), findsOneWidget);
    });
  });

  group('📏 لا فيضَ عند أيّ عرض', () {
    // 🔴 **مقيسٌ لا مُدَّعى**: بُدّل `Wrap` بـ`Row` فسقطت المقاسات الضيّقة بفيضٍ حقيقيّ.
    for (final w in <double>[360, 480, 720, 900, 1400]) {
      testWidgets('بالدولار عند ${w.toInt()} بكسل (ثلاثةُ حقول)', (tester) async {
        await pump(tester, currency: 'USD', width: w);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ومطفأً عند 360 بكسل — والنصّ يُقصّ ولا يفيض', (tester) async {
      await pump(tester, enabled: false, width: 360);
      expect(tester.takeException(), isNull);
    });
  });

  group('🌙 الوضع الليليّ', () {
    testWidgets('🔴 يُرسم بلا استثناء — ولا لونَ ثابتٍ لعنصرٍ تفاعليّ (ADR-041)',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FinancialBar(
            enabled: true,
            onEnabledChanged: (_) {},
            amount: amount,
            rate: rate,
            currency: 'USD',
            onCurrencyChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, 'سعر الصرف للدينار'), findsOneWidget);
    });
  });
}
