import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/company_providers.dart';
import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/sidebar.dart';

/// حرّاس **صدر القائمة الجانبية** — اسم الشركة الفعّالة وشعارها (طلب المالك 2026-09-09).
///
/// 🔴 **لماذا؟** كان الصدر يعرض «DEN LAND» **نصّاً ثابتاً** وأيقونةً عامّة. والنظام
/// **متعدّد الشركات** (ADR-017) — فموظّف الشركة الثانية كان يرى اسم الأولى وشعارها فوق
/// بياناته، وهي **معلومةٌ كاذبة** لا نقصٌ تجميليّ.
void main() {
  SessionState session({int companyId = 1}) => SessionState(
        loaded: true,
        activeCompanyId: companyId,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مستخدم اختبار',
          username: 'tester',
          role: 'Employee',
          companyIds: const [1, 2],
          mustChangePassword: false,
          companies: [
            CompanyAccess(companyId: 1, modules: const ['Outgoing']),
            CompanyAccess(companyId: 2, modules: const ['Outgoing']),
          ],
        ),
      );

  Company company(int id, String name, {String? logoKey}) => Company(
        companyId: id,
        name: name,
        prefix: 'C$id',
        isActive: true,
        logoImageKey: logoKey,
      );

  Future<void> pumpSidebar(WidgetTester tester, Company? active) async {
    await tester.pumpWidget(ProviderScope(
      // ⚠️ **مفتاحٌ بمعرّف الشركة**: بدونه تُعيد `pumpWidget` استعمال الحاوية نفسها
      //    فلا يُقرأ التجاوز الجديد — **فيمرّ حارسُ التبديل وهو لا يقيس تبديلاً**.
      key: ValueKey(active?.companyId),
      overrides: [
        sessionProvider.overrideWith(() => _FixedSession(session())),
        activeCompanyProvider.overrideWith((ref) async => active),
        // ⚠️ **تُعزَل شارة الصادر**: مصدرُها يستقصي الخادم، وبلا عزلٍ يبقى مؤقّتُ الشبكة
        //    معلّقاً فيفشل الاختبار **بلا عيبٍ في المنتج** (درسٌ مسجَّل من الدفعة ٥).
        pendingDraftsProvider.overrideWith((ref) async => <OutgoingListItem>[]),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              height: 900,
              child: Sidebar(
                selectedIndex: 0,
                onSelected: (_) {},
                canManageUsers: false,
                isSuperAdmin: false,
                modules: const ['Outgoing'],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('🏢 يعرض اسم الشركة الفعّالة لا اسم النظام', (tester) async {
    await pumpSidebar(tester, company(1, 'أرض العرين للتجارة والمقاولات'));

    expect(find.text('أرض العرين للتجارة والمقاولات'), findsOneWidget);
    expect(find.text('DEN LAND'), findsNothing,
        reason: 'الاسم الثابت يجعل موظّف الشركة الثانية يرى اسم الأولى فوق بياناته');
  });

  testWidgets('🔄 وتبديلُ الشركة يبدّل الاسم', (tester) async {
    await pumpSidebar(tester, company(1, 'الشركة الأولى'));
    expect(find.text('الشركة الأولى'), findsOneWidget);

    await pumpSidebar(tester, company(2, 'الشركة الثانية'));
    expect(find.text('الشركة الثانية'), findsOneWidget);
    expect(find.text('الشركة الأولى'), findsNothing);
  });

  testWidgets('🖼️ أيقونةٌ عامّة لشركةٍ بلا شعار', (tester) async {
    await pumpSidebar(tester, company(1, 'شركة بلا شعار'));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.business), findsOneWidget);
  });

  testWidgets('🖼️ وصورةٌ لشركةٍ لها شعار', (tester) async {
    // ⚠️ **صورةُ الشبكة تُخدَم محلياً** — وإلا حاول الاختبار بلوغ الشبكة فعلّق مؤقّتاً.
    await HttpOverrides.runZoned(() async {
      await pumpSidebar(tester, company(1, 'شركة بشعار', logoKey: 'logo/1.png'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget,
          reason: 'الشعار يُطلب حين يكون للشركة مفتاحُ صورة');
      expect(find.byIcon(Icons.business), findsNothing);
    }, createHttpClient: (_) => _FakeHttpClient());
  });

  test('🔗 ورابط الشعار يُبنى من مفتاح الصورة لا من الاسم', () {
    expect(companyLogoUrl(company(1, 'بلا شعار')), isNull);
    expect(companyLogoUrl(null), isNull);
    expect(companyLogoUrl(company(7, 'بشعار', logoKey: 'k')), contains('/companies/7/logo'));
  });

  testWidgets('🔴 وقبل وصول الشركة: لا اسمَ مختلَق', (tester) async {
    // اسمُ شركةٍ يُعرض قبل معرفتها **كذبٌ لحظيّ** — والسابقة المتّبعة في الشريط العلوي
    // نصُّ «جاري التحميل...».
    await pumpSidebar(tester, null);

    expect(find.text('جاري التحميل...'), findsOneWidget);
    expect(find.byIcon(Icons.business), findsOneWidget);
  });

  testWidgets('📝 والسطر الثاني يصف النظام فيبقى ثابتاً', (tester) async {
    await pumpSidebar(tester, company(1, 'شركة ما'));
    expect(find.text('إدارة الوثائق'), findsOneWidget);
  });
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

/// عميل HTTP مزيّف يخدم صورةً شفافة 1×1 — **لئلّا يبلغ الاختبار الشبكة**.
class _FakeHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest();
}

class _FakeRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeResponse();
}

class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeResponse extends Fake implements HttpClientResponse {
  static final _png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}
