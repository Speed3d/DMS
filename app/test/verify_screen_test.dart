import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/qr_scan/qr_scan.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/verify_screen.dart';

/// شاشة التحقق من ختم QR (ADR-061): الخياران متجاوران · الرابط يُتحقَّق منه داخل النظام · **نتيجةٌ واضحة لكل حالةٍ من الثلاث**.
void main() {
  late _Api api;

  Future<void> pump(WidgetTester tester, {Size size = const Size(1200, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VerifyScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('verify-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-run')));
    await tester.pumpAndSettle();
  }

  setUp(() => api = _Api());

  testWidgets('الخياران ظاهران: الكاميرا واللصق — واللصق مفتوحٌ افتراضاً', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('verify-mode-camera')), findsOneWidget);
    expect(find.byKey(const Key('verify-mode-paste')), findsOneWidget);
    expect(find.byKey(const Key('verify-input')), findsOneWidget);
    // خارج المتصفّح لا كاميرا — البطاقة ظاهرةٌ معطَّلةً بسببها، فلا يُوعد بما لا يعمل
    expect(qrCameraSupported, isFalse);
    expect(find.text('متاحٌ في نسخة المتصفّح'), findsOneWidget);
  });

  testWidgets('📷 الرابط المطبوع على الختم يُتحقَّق منه داخل النظام — كتابٌ صحيح ببياناته وبلا مبلغ', (tester) async {
    api.next = VerifyResult(
      isValid: true, message: 'تم إصدار هذا الكتاب فعلاً من الشركة', foundInDb: true,
      number: 'DEN-OUT-2026-00007', date: '2026-10-05', entity: 'وزارة النقل',
      verdictCode: 'Genuine', title: 'تم إصدار هذا الكتاب فعلاً من الشركة',
      note: 'طابِق البيانات أدناه مع الورقة التي بين يديك.', companyName: 'أرض العرين', versionNo: 2,
    );
    await pump(tester);
    await paste(tester, 'https://dms.nociraq.com/v/AAAAB3n6Tq8xYk2ZpQ9wLA');
    expect(api.sent, 'https://dms.nociraq.com/v/AAAAB3n6Tq8xYk2ZpQ9wLA', reason: 'يُرسَل الرابط كما هو — والخادم يحكم');
    expect(find.byKey(const Key('verify-verdict-Genuine')), findsOneWidget);
    expect(find.text('كتابٌ صحيح'), findsOneWidget);
    expect(find.text('DEN-OUT-2026-00007'), findsOneWidget);
    expect(find.text('أرض العرين'), findsOneWidget);
    expect(find.text('عُدِّل بعد اعتماده — هذا الإصدار 2'), findsOneWidget);
    expect(find.text('المبلغ بالدينار'), findsNothing, reason: 'الرابط بلا مبلغ كصفحة الهاتف (قرار المالك)');
    expect(find.byKey(const Key('verify-open-page')), findsOneWidget, reason: 'صفحة الكتاب لتنزيل نسخته');
  });

  testWidgets('كتابٌ مسحوب: برتقاليّ «انتبه» — لا «صحيح» ولا «مزوّر»', (tester) async {
    api.next = VerifyResult(isValid: true, message: '', foundInDb: false, number: 'DEN-OUT-2026-00003', verdictCode: 'Withdrawn',
        title: 'هذا الكتاب لم يعُد ضمن سجلّات الشركة', note: 'قد يكون سُحب أو أُلغي.');
    await pump(tester);
    await paste(tester, 'https://dms.nociraq.com/v/AAAAB3n6Tq8xYk2ZpQ9wLA');
    expect(find.byKey(const Key('verify-verdict-Withdrawn')), findsOneWidget);
    expect(find.text('انتبه'), findsOneWidget);
    expect(find.byKey(const Key('verify-open-page')), findsNothing);
  });

  testWidgets('ختمٌ مزوَّر: أحمر «غير صحيح» — بلا أيّ بيانات', (tester) async {
    api.next = VerifyResult(isValid: false, message: 'التوقيع غير صالح', foundInDb: false, number: 'X',
        verdictCode: 'Tampered', title: 'تم التلاعب بالكتاب', note: 'لا تعتمد على هذه الورقة.');
    await pump(tester);
    await paste(tester, 'DMS2|xxx');
    expect(find.byKey(const Key('verify-verdict-Tampered')), findsOneWidget);
    expect(find.text('غير صحيح'), findsOneWidget);
    expect(find.text('تم التلاعب بالكتاب'), findsOneWidget);
    expect(find.text('رقم الكتاب'), findsNothing, reason: 'المزوَّر لا يُعرض له رقمٌ يُطمئن');
  });

  testWidgets('خادمٌ أقدم بلا حقل الحكم: يُشتقّ من isValid/foundInDb — والمحتوى الخامّ يُظهر المبلغ', (tester) async {
    api.next = VerifyResult(isValid: true, message: 'ok', foundInDb: true, number: 'N-1', amountInIqd: '1,500,000');
    await pump(tester);
    await paste(tester, 'DMS2|raw');
    expect(find.byKey(const Key('verify-verdict-Genuine')), findsOneWidget);
    expect(find.text('1,500,000'), findsOneWidget);
  });

  testWidgets('«تحقّق من ختم آخر» يمسح النتيجة والحقل · وخطأ الاتصال يظهر بلا نتيجة', (tester) async {
    api.next = VerifyResult(isValid: true, message: '', foundInDb: true, number: 'N-2', verdictCode: 'Genuine');
    await pump(tester);
    await paste(tester, 'DMS2|a');
    await tester.tap(find.byKey(const Key('verify-again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verify-verdict-Genuine')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('verify-input'))).controller!.text, isEmpty);

    api.fail = true;
    await paste(tester, 'DMS2|b');
    expect(find.text('تعذّر الاتصال بالخادم'), findsOneWidget);
  });

  testWidgets('📱 الهاتف: البطاقتان فوق بعضهما بلا فيض', (tester) async {
    await pump(tester, size: const Size(380, 800));
    expect(tester.takeException(), isNull);
    final cam = tester.getRect(find.byKey(const Key('verify-mode-camera')));
    final paste = tester.getRect(find.byKey(const Key('verify-mode-paste')));
    expect(paste.top, greaterThan(cam.bottom - 1), reason: 'عمودٌ لا صفّ على الشاشة الضيّقة');
  });

  test('رسائل الكاميرا عربيةٌ تقول ما العمل — والبديل يُعرض حيث يفيد', () {
    for (final k in QrScanFailure.values) {
      final e = QrScanError(k);
      expect(e.message, matches(RegExp(r'\p{Script=Arabic}', unicode: true)));
    }
    expect(const QrScanError(QrScanFailure.insecure).message, contains('https'));
    expect(const QrScanError(QrScanFailure.denied).photoHelps, isTrue);
    expect(const QrScanError(QrScanFailure.library).photoHelps, isFalse);
  });
}

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);
  VerifyResult? next;
  String? sent;
  bool fail = false;

  @override
  Future<VerifyResult> verifyQr(String input) async {
    sent = input;
    if (fail) throw ApiException(null, 'تعذّر الاتصال بالخادم', isNetworkError: true);
    return next!;
  }
}
