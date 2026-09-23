import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/company_select_screen.dart';

/// حرّاس **شاشة اختيار الشركة** بعد إعادة تصميمها كروتاً مربّعة (طلب المالك 2026-09-23).
///
/// ⚠️ **العدد والمقاس يُقاسان لا يُفترضان**: الكرت مربّعٌ فعلاً (العرض = الارتفاع) · ولا فيض
/// عند أربعة عروض وفي الوضع الليلي · وكرتان متجاوران في الهاتف · والنقر يختار الشركة.
void main() {
  final companies = [
    const Company(companyId: 1, name: 'أرض العرين للتجارة والمقاولات العامة المحدودة', prefix: 'DEN', isActive: true),
    const Company(companyId: 2, name: 'شركة ثانية', prefix: 'TSA', isActive: true),
    const Company(companyId: 3, name: 'ثالثة', prefix: 'TES', isActive: true),
  ];

  SessionState session() => SessionState(
        loaded: true,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مدير النظام',
          username: 'admin',
          role: 'SuperAdmin',
          companyIds: const [],
          mustChangePassword: false,
          companies: const [],
        ),
      );

  late _RecordingSession sess;

  Future<void> pump(WidgetTester tester, _Api api,
      {double width = 1280, double height = 900, ThemeData? theme}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sess = _RecordingSession(session());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => sess),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: theme ?? ThemeData.light(),
        home: const Directionality(textDirection: TextDirection.rtl, child: CompanySelectScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Finder card(String name) => find.byKey(
      ValueKey('company-card-${companies.firstWhere((c) => c.name == name).companyId}'));

  for (final w in [360.0, 414.0, 800.0, 1280.0]) {
    testWidgets('بلا فيض والكروت مربّعة عند عرض ${w.toInt()}', (tester) async {
      await pump(tester, _Api(companies), width: w);
      expect(tester.takeException(), isNull);
      for (final c in companies) {
        final size = tester.getSize(card(c.name));
        expect(size.width, closeTo(size.height, 0.5), reason: '${c.name}: $size');
      }
    });
  }

  testWidgets('وفي الوضع الليلي بلا فيض', (tester) async {
    await pump(tester, _Api(companies), width: 360, theme: ThemeData.dark());
    expect(tester.takeException(), isNull);
    expect(card(companies.first.name), findsOneWidget);
  });

  testWidgets('كرتان متجاوران في الهاتف — لا عمودٌ من مربّعاتٍ ضخمة', (tester) async {
    await pump(tester, _Api(companies), width: 360);
    final a = tester.getTopLeft(card(companies[0].name));
    final b = tester.getTopLeft(card(companies[1].name));
    expect(a.dy, b.dy, reason: 'الكرتان الأوّلان في صفٍّ واحد');
  });

  testWidgets('الاسم والرمز والتحيّة ظاهرة', (tester) async {
    await pump(tester, _Api(companies));
    expect(find.text('شركة ثانية'), findsOneWidget);
    expect(find.text('TSA'), findsOneWidget);
    expect(find.text('مرحباً، مدير النظام'), findsOneWidget);
  });

  testWidgets('النقر على الكرت يختار الشركة', (tester) async {
    await pump(tester, _Api(companies));
    await tester.tap(card('شركة ثانية'));
    await tester.pump();
    expect(sess.selected, 2);
  });

  testWidgets('الخطأ يعرض «إعادة المحاولة» — والإعادة تجلب ثانيةً', (tester) async {
    final api = _Api(companies, failFirst: true);
    await pump(tester, api);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(card('شركة ثانية'), findsOneWidget);
  });

  testWidgets('نظامٌ بلا شركات يدخل بلا شركة (السلوك القائم لم يتغيّر)', (tester) async {
    await pump(tester, _Api(const []));
    await tester.pump();
    expect(sess.enteredWithout, isTrue);
  });
}

class _Api extends ApiClient {
  _Api(this._companies, {this.failFirst = false})
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final List<Company> _companies;
  final bool failFirst;
  int calls = 0;

  @override
  Future<List<Company>> companies({bool includeInactive = false}) async {
    calls++;
    if (failFirst && calls == 1) throw ApiException(0, 'تعذّر الاتصال بالخادم.', isNetworkError: true);
    return _companies;
  }
}

/// جلسةٌ تسجّل الاختيار بدل الكتابة إلى التخزين الآمن (لا قناة منصّة في الاختبار).
class _RecordingSession extends SessionNotifier {
  _RecordingSession(this._state);
  final SessionState _state;
  int? selected;
  bool enteredWithout = false;

  @override
  SessionState build() => _state;

  @override
  Future<void> setActiveCompany(int companyId) async => selected = companyId;

  @override
  void enterWithoutCompany() => enteredWithout = true;
}
