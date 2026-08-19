import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/employee_detail_screen.dart';
import 'package:dms_app/screens/employee_list_screen.dart';

/// حرّاس الدفعة **ج** من ملاحظات المالك (2026-08-20): صور الموظفين وتكبيرها.
///
/// 🔴 **العيب الذي تحرسه:** `_Avatar` في قائمة الموظفين كان **يستقبل `employeeId`
/// و`hasPhoto` ويتجاهلهما** ويعرض الحرف الأول دائماً — ميزةٌ نصف مُنفَّذة: المعلومة
/// تصل من الخادم ولا تُستعمل. والحرف يُخفي أن للموظف صورةً أصلاً.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// PNG صالح 1×1 — يكفي لإثبات أن البايتات تصل وتُرسم.
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
    0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  Future<void> pump(WidgetTester tester, ApiClient api, Widget child) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionProvider.overrideWith(() => _FixedSession(_session())),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('🖼️ صورة الموظف تُعرض ولا تُختزل في حرف', () {
    testWidgets('🔴 مَن له صورة: تُرسم صورته لا حرفه', (tester) async {
      final api = _PhotoApi(png: png, hasPhoto: true);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
      expect(avatar.backgroundImage, isNotNull, reason: 'لم تُرسم الصورة');
      // والحرف يغيب — وإلا ظهرا معاً.
      expect(avatar.child, isNull);
    });

    testWidgets('🔤 ومَن لا صورةَ له: الحرف الأول', (tester) async {
      final api = _PhotoApi(png: png, hasPhoto: false);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
      expect(avatar.backgroundImage, isNull);
      expect(avatar.child, isNotNull, reason: 'لا صورةَ ولا حرف — بطاقةٌ فارغة');
    });

    testWidgets('🔴 ولا يُطلب من الخادم صورةٌ نعلم أنها غير موجودة', (tester) async {
      // `hasPhoto` تصل مع البطاقة في الطلب نفسه — فطلبُها يُنتج 404 بلا فائدة،
      // وفي القائمة يتكرّر ذلك **لكل صفٍّ بلا صورة**.
      final api = _PhotoApi(png: png, hasPhoto: false);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));
      expect(api.photoCalls, 0, reason: 'طُلبت صورةٌ لمن لا صورةَ له');
    });

    testWidgets('وتُطلب مرّةً واحدة لمن له صورة', (tester) async {
      final api = _PhotoApi(png: png, hasPhoto: true);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));
      expect(api.photoCalls, 1);
    });
  });

  // ══════════════════ القائمة — موضع البلاغ ══════════════════

  group('📋 قائمة الموظفين — الصور لا الحروف', () {
    testWidgets('🔴 صفُّ مَن له صورة يعرضها، وصفُّ مَن لا صورةَ له يعرض حرفه',
        (tester) async {
      final api = _ListApi(png: png);
      await pump(tester, api, const EmployeeListScreen());
      await tester.pumpAndSettle();

      // ⚠️ **المطابقة بالبنية لا بالنصّ**: العربية تُشوَّه في بعض البيئات،
      //    والمقصود هنا **ماذا رُسم** لا ماذا كُتب.
      final avatars = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .where((a) => a.radius == 19)
          .toList();
      expect(avatars.length, 2, reason: 'عدد صفوف القائمة تغيّر — راجع العيّنة');

      final withPhoto = avatars.where((a) => a.backgroundImage != null).length;
      final withLetter = avatars.where((a) => a.child != null).length;
      expect(withPhoto, 1, reason: '🔴 لم تُعرض صورة صاحبها — وهو بلاغ المالك بعينه');
      expect(withLetter, 1, reason: 'مَن لا صورةَ له فقد حرفه أيضاً');
    });

    testWidgets('🔴 ولا يُطلب من الخادم إلا صورةُ مَن له صورة', (tester) async {
      // بلا هذا الشرط تصير قائمةٌ من عشرين موظفاً **عشرين طلباً**، أكثرها 404.
      final api = _ListApi(png: png);
      await pump(tester, api, const EmployeeListScreen());
      await tester.pumpAndSettle();
      expect(api.photoCalls, 1);
      expect(api.requestedIds, [7]);
    });
  });

  group('🔍 الضغط على الصورة يكبّرها', () {
    testWidgets('🔴 صورةٌ موجودة ⇒ مضغوطةٌ وتفتح العارض', (tester) async {
      final api = _PhotoApi(png: png, hasPhoto: true);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));

      final zoom = find.byTooltip('عرض الصورة بحجمٍ أكبر');
      expect(zoom, findsOneWidget, reason: 'لا مدخلَ للتكبير');

      await tester.tap(zoom);
      await tester.pumpAndSettle();

      // العارض المشترك نفسه الذي يعرض المرفقات — فيرث التكبير بالسحب.
      expect(find.byType(Dialog), findsOneWidget, reason: 'لم يُفتح العارض');
      expect(find.byType(InteractiveViewer), findsWidgets,
          reason: 'العارض بلا تكبير — فالضغط أظهر صورةً ثابتة لا أكبر');
    });

    testWidgets('⚠️ وبلا صورةٍ لا مؤشّرَ ولا وعدٌ بالضغط', (tester) async {
      // مؤشّرُ يدٍ على صورةٍ غير موجودة يَعِد بما لا يقع.
      final api = _PhotoApi(png: png, hasPhoto: false);
      await pump(tester, api, const EmployeeDetailScreen(employeeId: 1));
      expect(find.byTooltip('عرض الصورة بحجمٍ أكبر'), findsNothing);
    });
  });
}

/// عميل API للاختبار — **يعدّ طلبات الصور** ليُثبَت أنها لا تُطلب بلا داعٍ.
class _PhotoApi extends ApiClient {
  _PhotoApi({required this.png, required this.hasPhoto})
      : super(baseUrl: 'http://test/api', token: (() => 't'), companyId: (() => 1));

  final Uint8List png;
  final bool hasPhoto;
  int photoCalls = 0;

  static dynamic _fixture(String name) =>
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

  @override
  Future<EmployeeDetail> employee(int id) async {
    final j = _fixture('employee_detail') as Map<String, dynamic>;
    return EmployeeDetail.fromJson({...j, 'hasPhoto': hasPhoto});
  }

  @override
  Future<Uint8List> employeePhoto(int id) async {
    photoCalls++;
    return png;
  }

  @override
  Future<List<SalaryHistoryItem>> salaryHistory(int id, {int take = 12}) async =>
      (_fixture('salary_history') as List)
          .map((e) => SalaryHistoryItem.fromJson(e))
          .toList();

  @override
  Future<List<LeaveModel>> leaves(int employeeId) async =>
      (_fixture('leaves') as List).map((e) => LeaveModel.fromJson(e)).toList();

  @override
  Future<List<EmployeeLogItem>> employeeLog(int employeeId) async =>
      (_fixture('employee_log') as List)
          .map((e) => EmployeeLogItem.fromJson(e))
          .toList();

  @override
  Future<List<AttachmentModel>> employeeAttachments(int id) async => const [];
}

/// عميلٌ لقائمةٍ من موظفَين: أحدهما بصورة والآخر بلا.
class _ListApi extends ApiClient {
  _ListApi({required this.png})
      : super(baseUrl: 'http://test/api', token: (() => 't'), companyId: (() => 1));

  final Uint8List png;
  int photoCalls = 0;
  final List<int> requestedIds = [];

  @override
  Future<List<EmployeeListItem>> employees({bool? activeOnly, String? search}) async => [
        EmployeeListItem(
          employeeId: 7, employeeCompanyId: 1, fullName: 'سنان الجبوري',
          hasPhoto: true, position: 'مهندس', hireDate: DateTime(2020, 1, 1),
          salaryCurrency: 'IQD', baseSalary: 1200000, displayOrder: 1, isActive: true,
        ),
        EmployeeListItem(
          employeeId: 8, employeeCompanyId: 2, fullName: 'هدير صفاء',
          hasPhoto: false, position: 'إدارية', hireDate: DateTime(2021, 5, 1),
          salaryCurrency: 'IQD', baseSalary: 900000, displayOrder: 2, isActive: true,
        ),
      ];

  @override
  Future<Uint8List> employeePhoto(int id) async {
    photoCalls++;
    requestedIds.add(id);
    return png;
  }

  @override
  Future<HrSummary> hrSummary() async => HrSummary.fromJson(const {
        'activeEmployees': 2, 'pendingLeaves': 0,
        'thisMonthTotalIqd': null, 'unpaidMonths': null,
      });
}

SessionState _session() => SessionState(
      loaded: true,
      activeCompanyId: 1,
      auth: AuthResult(
        accessToken: 't',
        accessExpires: DateTime.now().add(const Duration(hours: 1)),
        refreshToken: 'r',
        userId: 1,
        fullName: 'مدير',
        username: 'admin',
        role: 'SuperAdmin',
        companyIds: const [1],
        mustChangePassword: false,
        companies: [CompanyAccess(companyId: 1, modules: const [])],
      ),
    );

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}
