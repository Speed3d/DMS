import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/employee_detail_screen.dart';
import 'package:dms_app/screens/employee_form_screen.dart';
import 'package:dms_app/screens/employee_link_dialog.dart';

// اختبار **نقرٍ حقيقي** لمسار «إضافة موظف قائم» (ADR-027): شجرةٌ تُبنى وتُرسم، وأزرارٌ
// تُضغط، وشاشةٌ يُقرأ نصُّها المرسوم.
//
// 🔴 **سبب وجوده — درسٌ دفع المشروع ثمنه ثلاث مرّات:**
// عيّنةٌ كتبتُها بيدي صادقت ظنّي (`rowVersion`)، ونسخةٌ مقلَّدة قاست اختراعي (حارس الفيض)،
// و**اختبارٌ جرّب المنطق خارج بيئته** فمرّ أخضرَ بينما `initState` ينهار عند المالك
// (نيّة التنقّل، 2026-08-06). المشترك أن أياً منها **لم يبنِ الشجرة ويضغط الزرّ**.
// وبيئة التطوير هنا لا تعرض واجهة Flutter (رسمٌ على canvas بلا شجرةٍ دلالية تُقرأ)، فالنقر
// الآليّ في اختبارٍ كهذا هو **البديل الوحيد** عن نقر المالك — أو عن بلاغٍ منه.

/// عميلٌ بديل يردّ **أجسام الخادم الحقيقية حرفياً** ثم يمرّرها على `fromJson` نفسها.
///
/// ⚠️ **لماذا بديلٌ لا خادمُ HTTP حقيقي كما في `api_client_empty_body_test`؟** لأن
/// `testWidgets` يُركّب `HttpOverrides` وهميّاً يقطع كل اتصال — ورفعُه داخل بيئة الاختبار
/// يصطدم بمناطق التنفيذ (zones). والمقصود هنا **التوصيل بالنقر** لا سلوكُ Dio: سلوكُه
/// أمام 204 محروسٌ في ذلك الملف على خادمٍ حقيقي.
/// 🔴 **والأجسام أدناه من خادمٍ حيّ لا من فهمي للعقد** (نظير `test/fixtures/lookup.json`)،
/// وتمرّ على `ExistingEmployeeHint.fromJson` عينها التي يستعملها التطبيق.
class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);

  static const foundElsewhere =
      '{"employeeId":7,"fullName":"سنان الجبوري","alreadyInThisCompany":false}';
  static const foundHere =
      '{"employeeId":7,"fullName":"سنان الجبوري","alreadyInThisCompany":true}';

  @override
  Future<ExistingEmployeeHint?> lookupEmployee(String nationalId) async {
    // هوية غير موجودة ⇒ الخادم يردّ **204 بجسم فارغ**، والعميل يترجمها `null`.
    if (nationalId == '000') return null;
    return ExistingEmployeeHint.fromJson(
        jsonDecode(nationalId == '111' ? foundHere : foundElsewhere));
  }

  // ── ما تحتاجه بطاقة الموظف: العيّنات **مُلتقَطة من الخادم** لا مصنوعة ──
  static dynamic _fixture(String name) =>
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

  /// أيّ عيّنةٍ يقرأ: `employee_detail` (يعمل في شركتين) أو `employee_detail_single`.
  String detailFixture = 'employee_detail';

  @override
  Future<EmployeeDetail> employee(int id) async =>
      EmployeeDetail.fromJson(_fixture(detailFixture));

  @override
  Future<List<SalaryHistoryItem>> salaryHistory(int id, {int take = 12}) async =>
      (_fixture('salary_history') as List).map((e) => SalaryHistoryItem.fromJson(e)).toList();

  @override
  Future<List<LeaveModel>> leaves(int employeeId) async =>
      (_fixture('leaves') as List).map((e) => LeaveModel.fromJson(e)).toList();

  @override
  Future<List<EmployeeLogItem>> employeeLog(int employeeId) async =>
      (_fixture('employee_log') as List).map((e) => EmployeeLogItem.fromJson(e)).toList();

  @override
  Future<List<AttachmentModel>> employeeAttachments(int id) async => const [];
}

void main() {
  late ApiClient api;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    api = _FakeApi();
  });

  SessionState session({bool canManage = true}) => SessionState(
        loaded: true,
        activeCompanyId: 1,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مستخدم اختبار',
          username: 'tester',
          role: 'Manager',
          companyIds: const [1],
          mustChangePassword: false,
          companies: [
            CompanyAccess(
              companyId: 1,
              modules: const ['Employees'],
              canManageEmployees: canManage,
            ),
          ],
        ),
      );

  /// يبني الشجرة فعلاً مع مزوّدٍ حقيقي — لا `ProviderContainer` بلا ودجات.
  ///
  /// وسطحٌ طويل عمداً: النموذج داخل `ListView` يبني المرئيَّ وحده، فزرُّ الحفظ أسفلَه
  /// **غير موجودٍ في الشجرة** على سطحٍ قصير — فيبدو الاختبار وكأنه كشف نقصاً وهو لم يكشف شيئاً.
  Future<void> pump(WidgetTester tester, Widget child, {bool canManage = true}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionProvider.overrideWith(() => _FixedSession(session(canManage: canManage))),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('نافذة البحث بالهوية', () {
    testWidgets('موظفٌ في شركة أخرى: يظهر اسمه وزرّ الإسناد، ويُعاد بالنتيجة', (tester) async {
      EmployeeLinkResult? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<EmployeeLinkResult>(
                context: context,
                builder: (_) => const EmployeeLinkDialog(),
              );
            },
            child: const Text('افتح'),
          ),
        ),
      );

      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة موظف قائم'), findsOneWidget);

      // قبل البحث: لا زرّ إسناد — فلا يُسنَد أحدٌ بلا نتيجة.
      expect(find.text('إسناده إلى هذه الشركة'), findsNothing);

      await tester.enterText(find.byType(TextField), '19900101');
      await tester.tap(find.widgetWithText(ElevatedButton, 'بحث'));
      await tester.pumpAndSettle();

      expect(find.textContaining('سنان الجبوري'), findsOneWidget);
      expect(find.textContaining('يعمل في شركة أخرى'), findsOneWidget);

      await tester.tap(find.text('إسناده إلى هذه الشركة'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.employeeId, 7);
      expect(result!.alreadyHere, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('🔐 مُسنَدٌ هنا أصلاً: الفعل «فتح بطاقته» لا الإسناد', (tester) async {
      EmployeeLinkResult? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<EmployeeLinkResult>(
                context: context,
                builder: (_) => const EmployeeLinkDialog(),
              );
            },
            child: const Text('افتح'),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '111');
      await tester.tap(find.widgetWithText(ElevatedButton, 'بحث'));
      await tester.pumpAndSettle();

      expect(find.textContaining('مُسنَدٌ إلى هذه الشركة بالفعل'), findsOneWidget);
      expect(find.text('إسناده إلى هذه الشركة'), findsNothing);

      await tester.tap(find.text('فتح بطاقته'));
      await tester.pumpAndSettle();
      expect(result!.alreadyHere, isTrue);
    });

    testWidgets('هويةٌ غير موجودة (204): رسالةٌ مرشدة بلا انهيار ولا زرّ إسناد',
        (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
                context: context, builder: (_) => const EmployeeLinkDialog()),
            child: const Text('افتح'),
          ),
        ),
      );
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000');
      await tester.tap(find.widgetWithText(ElevatedButton, 'بحث'));
      await tester.pumpAndSettle();

      // ⚠️ 204 يصل من Dio نصّاً فارغاً لا `null` — وهو العطب الذي أسقط شاشة الكشف عند
      //    المالك (2026-08-04). هنا يجب أن يُقرأ «لم يُوجد» لا أن ينهار.
      expect(find.textContaining('لا يوجد موظف بهذا الرقم'), findsOneWidget);
      expect(find.text('إسناده إلى هذه الشركة'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('نموذج الإسناد', () {
    testWidgets('يعرض الاسم ويُخفي البيانات الشخصية ويطلب شروط العمل وحدها', (tester) async {
      await pump(
        tester,
        const EmployeeFormScreen(
          link: LinkExistingEmployee(employeeId: 7, fullName: 'سنان الجبوري'),
        ),
      );

      expect(find.text('إسناد موظف قائم'), findsOneWidget);
      expect(find.text('سنان الجبوري'), findsOneWidget);

      // 🔐 البيانات الشخصية مخفيّة: ملفُّ الشخص واحدٌ لكل الشركات، وتحريرُه من هنا كان
      //    يعدّله على الشركة الأخرى معه.
      expect(find.text('البيانات الشخصية'), findsNothing);
      expect(find.text('الاسم الكامل بالعربية *'), findsNothing);

      expect(find.text('بيانات الوظيفة في هذه الشركة'), findsOneWidget);
      expect(find.text('الصفة بالعربية *'), findsOneWidget);
      expect(find.text('إسناده إلى هذه الشركة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ووضع «موظف جديد» يبقى كما كان — البيانات الشخصية ظاهرة', (tester) async {
      await pump(tester, const EmployeeFormScreen());

      expect(find.text('موظف جديد'), findsOneWidget);
      expect(find.text('البيانات الشخصية'), findsOneWidget);
      expect(find.text('الاسم الكامل بالعربية *'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('«يعمل أيضاً في» في بطاقة الموظف', () {
    // 🔴 **هذا هو التحقّق الذي كان ينقص المالك**: أن أثر الإسناد **يُرى**. وبدونه يقع
    //    الربط صامتاً فلا يُصدَّق أنه وقع — وهو نصف البلاغ الأصلي.
    testWidgets('موظفٌ في شركتين: يظهر اسم الشركة الأخرى', (tester) async {
      await pump(tester, const EmployeeDetailScreen(employeeId: 1));

      expect(find.text('يعمل أيضاً في:'), findsOneWidget);
      expect(find.text('شركة بوغوصيان للتجارة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('وموظفٌ في شركة واحدة: لا يظهر السطر أصلاً', (tester) async {
      (api as _FakeApi).detailFixture = 'employee_detail_single';
      await pump(tester, const EmployeeDetailScreen(employeeId: 2));

      expect(find.text('يعمل أيضاً في:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// جلسةٌ ثابتة — تتجاوز القراءة من التخزين الآمن غير المتاح في بيئة الاختبار.
class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;

  @override
  SessionState build() => _state;
}
