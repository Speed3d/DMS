import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/screens/reports_activity_tab.dart';
import 'package:dms_app/screens/reports_detail_tabs.dart';
import 'package:dms_app/screens/reports_screen.dart';

/// حرّاس تبويبات التقارير (ADR-031).
///
/// ⚠️ **سبب وجودها هو سببُ حرّاس الموظفين نفسه**: كل تبويب هنا له نظيرٌ في الخادم يردّ 403
/// لمن نقصه شرط. تبويبٌ يظهر ثم يردّ 403 **أسوأ من غيابه** — يظنّ المستخدم النظام معطوباً
/// لا أنه غير مخوَّل.
///
/// 🔐 **والحدّان مختلفان بين التبويبات عمداً:**
/// · النشاط ⟵ قسم التقارير **مع دورٍ** (رئيس فأعلى)، لأنه يقرأ سجلّ التدقيق.
/// · التفصيليان ⟵ قسم التقارير **مع قسم الوحدة**، لأنهما يقرآن بيانات وحدتهما.
void main() {
  SessionState sessionWith({required List<String> modules, required String role}) => SessionState(
        loaded: true,
        activeCompanyId: 1,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مستخدم اختبار',
          username: 'tester',
          role: role,
          companyIds: const [1],
          mustChangePassword: false,
          companies: [CompanyAccess(companyId: 1, modules: modules)],
        ),
      );

  group('🔐 تقرير النشاط — القسم لا يكفي', () {
    test('رئيس الشركة بقسم التقارير: يراه', () {
      expect(sessionWith(modules: ['Reports'], role: 'President').canSeeActivityReport, isTrue);
    });

    test('سوبر أدمن بقسم التقارير: يراه', () {
      expect(sessionWith(modules: ['Reports'], role: 'SuperAdmin').canSeeActivityReport, isTrue);
    });

    // 🔴 **الحارس الجوهري**: هذا بالضبط ما يمنع أن يصير التقرير باباً خلفياً لسجلّ التدقيق.
    //    مديرٌ يملك التقارير — وهي تُمنح لمحاسبين ليقرأوا المالي — لا يقرأ بها نشاط الجميع.
    test('🔐 مدير بقسم التقارير: **محجوب** — سجلّ التدقيق يكشف كل الأقسام', () {
      expect(sessionWith(modules: ['Reports'], role: 'Manager').canSeeActivityReport, isFalse);
    });

    test('🔐 موظف وقارئ بقسم التقارير: محجوبان', () {
      expect(sessionWith(modules: ['Reports'], role: 'Employee').canSeeActivityReport, isFalse);
      expect(sessionWith(modules: ['Reports'], role: 'Reader').canSeeActivityReport, isFalse);
    });

    // ⚠️ **ولا حارسَ «رئيسٌ بلا قسم التقارير»**: رئيس الشركة والسوبر أدمن **معفيان من قيد
    //    الأقسام أصلاً** (`AllowedModules = All` في الخادم و`hasModule` في العميل)، فقائمة
    //    أقسامهما لا تعني شيئاً. كتبتُ الحارس أولاً يتوقّع الحجب **ففشل — والمنتج سليم**،
    //    وهذا ما يُثبته الاختبار أدناه صراحةً بدل أن يُترك فراغاً يُعاد اكتشافه.
    test('الرئيس معفى من قيد الأقسام — فقائمةٌ بلا «التقارير» لا تحجبه', () {
      expect(sessionWith(modules: ['Outgoing'], role: 'President').canSeeActivityReport, isTrue);
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canSeeActivityReport, isTrue);
      // وغيرُ المعفى يُحجب بالقائمة فعلاً — وإلا لم يكن للقيد معنى.
      expect(sessionWith(modules: ['Outgoing'], role: 'Manager').canSeeActivityReport, isFalse);
    });
  });

  group('🔐 التقارير التفصيلية — حدٌّ مزدوج بالقسم', () {
    test('قسم التقارير + الصادر ⇒ الصادر التفصيلي', () {
      final s = sessionWith(modules: ['Reports', 'Outgoing'], role: 'Employee');
      expect(s.canSeeOutgoingDetailReport, isTrue);
      expect(s.canSeeArchiveDetailReport, isFalse, reason: 'بلا قسم الأرشيف');
    });

    test('قسم التقارير + الأرشيف ⇒ الأرشيف التفصيلي', () {
      final s = sessionWith(modules: ['Reports', 'Archive'], role: 'Employee');
      expect(s.canSeeArchiveDetailReport, isTrue);
      expect(s.canSeeOutgoingDetailReport, isFalse, reason: 'بلا قسم الصادر');
    });

    test('🔐 قسم التقارير وحده: لا تفصيليَّ إطلاقاً — وهذا هو الباب الخلفي المُغلق', () {
      final s = sessionWith(modules: ['Reports'], role: 'Manager');
      expect(s.canSeeOutgoingDetailReport, isFalse);
      expect(s.canSeeArchiveDetailReport, isFalse);
    });

    test('🔐 قسم الصادر أو الأرشيف بلا التقارير: محجوب — الحدّ مزدوج في الاتجاهين', () {
      expect(sessionWith(modules: ['Outgoing', 'Archive'], role: 'Manager').canSeeOutgoingDetailReport, isFalse);
      expect(sessionWith(modules: ['Outgoing', 'Archive'], role: 'Manager').canSeeArchiveDetailReport, isFalse);
    });
  });

  group('الشاشة تبني ما تسمح به الصلاحيات — بالرسم لا بالحساب', () {
    // 🔴 اختبار الخاصيّة وحدها لا يُثبت أن الشاشة تستعملها (درس «نيّة التنقّل» 2026-08-06:
    //    خمسة اختبارات خضراء على منطقٍ سليم، والعطل في **استدعائه**). فهذه تبني شجرةً فعلاً.
    Future<void> pumpReports(WidgetTester tester, SessionState session) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FixedSession(session)),
          // 🔴 **عميلٌ مزيّف إلزاميّ هنا**: التبويبات تنادي الـAPI في `initState`، فبعميلٍ
          //    حقيقي يبقى مؤقّتُ الشبكة معلّقاً بعد التخلّص من الشجرة ويفشل الاختبار
          //    بـ«A Timer is still pending» — لا لعيبٍ في الشاشة بل لأن الاختبار وصلها بشبكة.
          apiClientProvider.overrideWithValue(_SilentApi()),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SizedBox(width: 1200, height: 800, child: const ReportsScreen())),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('رئيس بكل الأقسام: أربعة تبويبات', (tester) async {
      await pumpReports(tester, sessionWith(modules: ['Reports', 'Outgoing', 'Archive'], role: 'President'));
      expect(find.text('المالي'), findsOneWidget);
      expect(find.text('الصادر التفصيلي'), findsOneWidget);
      expect(find.text('الأرشيف التفصيلي'), findsOneWidget);
      expect(find.text('النشاط'), findsOneWidget);
    });

    testWidgets('🔐 مدير بكل الأقسام: **لا تبويب نشاط**', (tester) async {
      await pumpReports(tester, sessionWith(modules: ['Reports', 'Outgoing', 'Archive'], role: 'Manager'));
      expect(find.text('الصادر التفصيلي'), findsOneWidget);
      expect(find.text('النشاط'), findsNothing);
    });

    testWidgets('موظف بالتقارير وحدها: المالي بلا تبويبات إطلاقاً', (tester) async {
      // تبويبٌ واحد لا يستحقّ شريط تبويبات — الشاشة تعود إلى شكلها الأصلي.
      await pumpReports(tester, sessionWith(modules: ['Reports'], role: 'Employee'));
      expect(find.text('الصادر التفصيلي'), findsNothing);
      expect(find.text('الأرشيف التفصيلي'), findsNothing);
      expect(find.text('النشاط'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('التبويبات تُبنى ببياناتٍ حقيقية وتعرضها', () {
    // 🔴 **أقربُ ما يمكن إلى النقر**: التبويب الفارغ يُثبت أنه يُبنى، ولا يُثبت أنه **يعرض**.
    //    والدرس المسجَّل من وحدة الرواتب: «ما يُتحقَّق منه بالنقر بقي على المالك، ولهذا وصلت
    //    أربعة بلاغات». هذه تبني الشجرة ببياناتٍ ثم تقرأ ما رُسم فعلاً.
    Future<void> pumpTab(WidgetTester tester, Widget tab, ApiClient api) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SizedBox(width: 1280, height: 800, child: tab)),
          ),
        ),
      ));
      await tester.pump();      // initState
      await tester.pump();      // بعد وصول البيانات
      expect(tester.takeException(), isNull);
    }

    testWidgets('النشاط: يعرض العربية والمعروضَ من الإجمالي', (tester) async {
      await pumpTab(tester, const ActivityReportTab(), _DataApi());
      // العربية هي ما يُعرض، لا المفتاح الخام.
      expect(find.text('اعتماد'), findsWidgets);
      expect(find.text('كتاب صادر'), findsWidgets);
      expect(find.text('Approve'), findsNothing, reason: 'المفتاح الخام للفلترة لا للعرض');
      // 🔴 «المعروض من الإجمالي» حين يُقصّ — قارئٌ يظنّ أنه رأى الكل يبني على نقصٍ لا يعلمه.
      expect(find.textContaining('المعروض: 2 من 784'), findsOneWidget);
      expect(find.textContaining('الأنشط'), findsOneWidget);
    });

    testWidgets('🔴 الصادر التفصيلي: المسودّة تُعدّ ولا تُجمع (ADR-029)', (tester) async {
      await pumpTab(tester, const OutgoingDetailTab(), _DataApi());
      expect(find.text('مسودّة'), findsWidgets);
      expect(find.text('معتمد'), findsWidgets);
      // المسودّة بمبلغ 900,000 موجودة في الجدول، والإجمالي 700,000 (المعتمد وحده).
      expect(find.textContaining('معتمدة: 1 · مسودّات: 1'), findsOneWidget);
      expect(find.textContaining('إجمالي المعتمد: 700,000'), findsOneWidget);
      expect(find.textContaining('إجمالي المعتمد: 1,600,000'), findsNothing,
          reason: 'جمعُ المسودّة مع المعتمد هو عطل ADR-029 بعينه');
    });

    testWidgets('الأرشيف التفصيلي: المصدران مميّزان والوارد بلا مبلغ', (tester) async {
      await pumpTab(tester, const ArchiveDetailTab(), _DataApi());
      expect(find.text('وارد مؤرشف'), findsWidgets);
      expect(find.text('أضبارة ورقية'), findsWidgets);
      expect(find.textContaining('وارد مؤرشف: 1 · أضابير: 1'), findsOneWidget);
      expect(find.textContaining('إجمالي الأضابير: 2,620,000'), findsOneWidget);
    });
  });

  group('حرّاس رسمٍ ضدّ فيض التخطيط', () {
    // ⚠️ الفيض تحت العرض الضيّق عطبٌ متكرّر في هذا المستودع (G12 · جدول الرواتب · شريط
    //    الأدوات) — و«رقمٌ يجب أن يسع محتوًى **يُقاس بالرسم لا يُخمَّن**».
    for (final width in [380.0, 420.0, 700.0, 900.0, 1280.0, 1600.0]) {
      testWidgets('شريط الملخّص لا يفيض عند $width', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: const SummaryBar(items: [
                  'عدد السجلات: 1250',
                  'وارد مؤرشف: 830 · أضابير: 420',
                  'إجمالي الأضابير: 128,450,000 د.ع',
                ]),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('جدول التقرير يمرّر أفقياً ولا يفيض عند $width', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: width,
                height: 600,
                child: const ReportTable(
                  minWidth: 1100,
                  columns: ['الرقم', 'التاريخ', 'الموضوع', 'الجهة', 'الحالة', 'أنشأه', 'اعتمده', 'بالدينار'],
                  rows: [
                    ['DEN-2026-00005', '2026-08-01', 'كتابٌ بموضوعٍ طويل نسبياً ليُختبر الفيض', 'وزارة الإعمار والإسكان', 'معتمد', 'مدير النظام', 'مدير النظام', '720,000'],
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('🔴 وصفٌّ أقصر من أعمدته يُملأ فراغاً ولا يكسر المحاذاة', (tester) async {
      // خليّةٌ ناقصة في `DataTable` تُزحزح ما بعدها فتنكسر المحاذاة **صامتةً** — لا استثناء
      // ولا خطأ، جدولٌ خاطئ فحسب. الحارس يُثبت أن النقص يُملأ لا يُسقِط.
      await tester.pumpWidget(const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 400,
              child: ReportTable(
                columns: ['أ', 'ب', 'ج'],
                rows: [
                  ['1'],
                  ['1', '2', '3'],
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(DataCell), findsNothing, reason: 'DataCell ليس Widget — نتحقّق من الرسم لا من النوع');
      expect(find.text('1'), findsNWidgets(2));
    });
  });
}

/// جلسةٌ ثابتة للاختبار — نظير ما تستعمله حرّاس لوحة التحكم.
class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

/// عميلُ API صامت — يردّ فوراً بنتائج فارغة بلا شبكة ولا مؤقّتات.
///
/// ⚠️ **ما نختبره هنا هو التبويبات لا البيانات**: أيُّ تبويبٍ يُبنى ولمن. وربطُ الاختبار
/// بشبكةٍ حقيقية يُدخل مؤقّتات معلّقة تُفشله **بلا عيبٍ في المنتج** — وهو صنفُ «الأداة تكذب»
/// المسجَّل في هذا المستودع مراراً.
class _SilentApi extends ApiClient {
  _SilentApi() : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<List<EntityModel>> entities() async => const [];

  @override
  Future<List<UserModel>> users() async => const [];

  @override
  Future<FinancialReport> financialReport(
          {DateTime? from, DateTime? to, int? entityId, String source = 'All'}) async =>
      FinancialReport(const [], 0, 0);

  @override
  Future<ActivityReport> activityReport(
          {DateTime? from, DateTime? to, int? userId, String? action, String? entityType, int take = 500}) async =>
      ActivityReport(const [], 0, const [], const []);

  @override
  Future<AuditVocabulary> auditVocabulary() async => AuditVocabulary(const [], const []);

  @override
  Future<OutgoingDetailReport> outgoingDetailReport(
          {DateTime? from, DateTime? to, int? entityId, String? status}) async =>
      OutgoingDetailReport(const [], 0, 0, 0, 0);

  @override
  Future<ArchiveDetailReport> archiveDetailReport(
          {String? search, int? year, int? month, int? departmentId, String? source}) async =>
      ArchiveDetailReport(const [], 0, 0, 0, 0);
}

/// عميلٌ يردّ **بيانات تشبه الحقيقية** — لاختبار ما يُعرض لا ما يُبنى فحسب.
///
/// ⚠️ العيّنات هنا **مبنيّة على عقد الخادم المُثبَت حيّاً** في `reports-e2e.ps1` (الحالة نصٌّ
/// `"Final"` لا رقم · الوقت UTC · العربية في `actionLabel`) — لا على ظنّي. والدرس المسجَّل:
/// «عيّنةٌ بخطّ يدي تُصادق ظنّي لا النظام».
class _DataApi extends _SilentApi {
  @override
  Future<ActivityReport> activityReport(
          {DateTime? from, DateTime? to, int? userId, String? action, String? entityType, int take = 500}) async =>
      ActivityReport(
        [
          ActivityRow(DateTime.utc(2026, 8, 11, 9, 30), 1, 'مدير النظام', 'Approve', 'اعتماد',
              'OutgoingBook', 'كتاب صادر', '12', 'اعتماد الكتاب'),
          ActivityRow(DateTime.utc(2026, 8, 11, 8, 15), 5, 'موظف الشؤون', 'Login', 'تسجيل دخول',
              'User', 'مستخدم', '5', null),
        ],
        784,
        [CountRow('تسجيل دخول', 188), CountRow('اعتماد', 42)],
        [CountRow('مدير النظام', 500), CountRow('موظف الشؤون', 120)],
      );

  @override
  Future<OutgoingDetailReport> outgoingDetailReport(
          {DateTime? from, DateTime? to, int? entityId, String? status}) async =>
      OutgoingDetailReport(
        [
          OutgoingDetailRow(1, 'DEN-2026-00005', DateTime(2026, 8, 1), 'كتاب معتمد', 'وزارة الإعمار',
              'Final', 'معتمد', 'مدير النظام', 'مدير النظام', 700, 'IQD', 700000),
          // مسودّةٌ **بمبلغ** — الحالة التي يكشفها العطل: موجودة في الجدول وخارج المجموع.
          OutgoingDetailRow(2, '— مسودّة —', DateTime(2026, 8, 3), 'كتاب مسودّة', 'وزارة المالية',
              'Draft', 'مسودّة', 'مدير النظام', null, 900, 'IQD', 900000),
        ],
        2, 1, 1, 700000,
      );

  @override
  Future<ArchiveDetailReport> archiveDetailReport(
          {String? search, int? year, int? month, int? departmentId, String? source}) async =>
      ArchiveDetailReport(
        [
          ArchiveDetailRow(true, 'وارد مؤرشف', 'DEN-IN-2026-00031', DateTime(2026, 7, 20),
              'كتاب وارد مؤرشف', 'وزارة التخطيط', 'كتاب رسمي', 'المالية', null),
          ArchiveDetailRow(false, 'أضبارة ورقية', 'DEN-AR-2026-00007', DateTime(2026, 6, 10),
              'أضبارة ورقية قديمة', null, 'عقد', '—', 2620000),
        ],
        2, 1, 1, 2620000,
      );
}
