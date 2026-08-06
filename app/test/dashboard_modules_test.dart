import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/archive_providers.dart';
import 'package:dms_app/core/hr_providers.dart';
import 'package:dms_app/core/incoming_providers.dart';
import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/dashboard_screen.dart';

/// لوحة التحكم يجب أن تعرض **بطاقات الأقسام التي يملكها المستخدم في الشركة الفعّالة فقط**
/// (ADR-017).
///
/// ⚠️ سبب وجود هذا الاختبار: كانت اللوحة بلا أي فحص صلاحيات، والمزوّدات تُرجع قائمة فارغة
/// لمن لا يملك القسم ⇒ فتظهر بطاقاته بقيمة **صفر** بدل أن تُخفى. وهذا **أسوأ من الإخفاء**:
/// يقرأ الموظفُ «إجمالي الصادر: 0» فيفهم أن الشركة بلا صادر، والحقيقة أنه لا يراه.
/// حارسٌ آليّ خيرٌ من فحص بصري لا يُعاد.
void main() {
  /// جلسة بمستخدم له [modules] في الشركة 1، وهي شركته الفعّالة.
  SessionState sessionWith(List<String> modules, {String role = 'Employee'}) => SessionState(
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

  Future<void> pumpDashboard(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FakeSession(session)),
          // بيانات ثابتة: الاختبار يخصّ **الحجب** لا الأرقام، ولا يلمس الشبكة.
          outgoingListProvider.overrideWith((ref) async => <OutgoingListItem>[]),
          incomingListProvider.overrideWith((ref) async => <IncomingListItem>[]),
          archiveLensProvider.overrideWith((ref) async => <ArchiveLensItem>[]),
          // بلا هذا التجاوز يحاول المزوّد بلوغ الشبكة في الاختبار (لا خادم) —
          // فيُخفق صامتاً ويُظهر «…» بدل الأرقام، وهو ما يُخفي عطباً حقيقياً لو وقع.
          hrSummaryProvider.overrideWith((ref) async => HrSummary(7, 5000000, 60000000, 2, 3)),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('موظف بصلاحية الوارد وحده: بطاقات الوارد فقط', (tester) async {
    await pumpDashboard(tester, sessionWith(['Incoming']));

    expect(find.text('إجمالي الوارد'), findsOneWidget);
    expect(find.text('وارد جديد'), findsOneWidget);

    // ⚠️ «وارد مؤرشف» **يتطلّب قسم الأرشيف أيضاً** منذ إعادة تصميم الأرشيف
    // (2026-07-28): المؤرشف صار يُعرض في قسم الأرشيف، ومصدر عدّه عدسته — ومن لا يملك
    // القسم لا يستطيع فتحه أصلاً، فعرض رقم لا يقدر على التحقق منه هو نفس عيب
    // «المعلومة الكاذبة» الذي وُجد هذا الاختبار لمنعه.
    expect(find.text('وارد مؤرشف'), findsNothing);

    expect(find.text('إجمالي الصادر'), findsNothing);
    expect(find.text('بانتظار الاعتماد'), findsNothing);
    expect(find.text('صادر معتمد'), findsNothing);
    expect(find.text('إجمالي مبالغ الصادر'), findsNothing);
    expect(find.text('أضابير الأرشيف'), findsNothing);
    // الرسم البياني وقائمة «أحدث الكتب» يخصّان الصادر ⇒ يُخفيان معه.
    expect(find.text('نشاط الصادر (الأسبوع الحالي)'), findsNothing);
    expect(find.text('أحدث الكتب'), findsNothing);
  });

  testWidgets('موظفة بصلاحية الصادر وحده: بطاقات الصادر والرسم البياني فقط', (tester) async {
    await pumpDashboard(tester, sessionWith(['Outgoing']));

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('بانتظار الاعتماد'), findsOneWidget);
    expect(find.text('صادر معتمد'), findsOneWidget);
    expect(find.text('نشاط الصادر (الأسبوع الحالي)'), findsOneWidget);

    expect(find.text('إجمالي الوارد'), findsNothing);
    expect(find.text('وارد جديد'), findsNothing);
    expect(find.text('أضابير الأرشيف'), findsNothing);
  });

  testWidgets('موظف بصلاحية الصادر والوارد والأرشيف: كل البطاقات', (tester) async {
    await pumpDashboard(tester, sessionWith(['Outgoing', 'Incoming', 'Archive']));

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('إجمالي الوارد'), findsOneWidget);
    expect(find.text('أضابير الأرشيف'), findsOneWidget);
    // بامتلاك الوارد **والأرشيف** معاً تظهر بطاقة المؤرشف — بخلاف الوارد وحده.
    expect(find.text('وارد مؤرشف'), findsOneWidget);
    expect(find.text('نشاط الصادر (الأسبوع الحالي)'), findsOneWidget);
  });

  testWidgets('السوبر أدمن معفى: يرى كل شيء ولو كانت قائمة أقسامه فارغة', (tester) async {
    await pumpDashboard(tester, sessionWith(const [], role: 'SuperAdmin'));

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('إجمالي الوارد'), findsOneWidget);
    expect(find.text('أضابير الأرشيف'), findsOneWidget);
  });

  testWidgets('رئيس الشركة معفى كذلك', (tester) async {
    await pumpDashboard(tester, sessionWith(const [], role: 'President'));

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('إجمالي الوارد'), findsOneWidget);
  });

  testWidgets('موظف بلا أي قسم تشغيلي: رسالة تشرح السبب لا شاشة فارغة', (tester) async {
    await pumpDashboard(tester, sessionWith(const ['Reports']));

    expect(find.text('لا توجد أقسام متاحة لك في هذه الشركة'), findsOneWidget);
    expect(find.text('إجمالي الصادر'), findsNothing);
    expect(find.text('إجمالي الوارد'), findsNothing);
  });

  testWidgets('الصلاحيات تتبع الشركة الفعّالة: نفس المستخدم يرى الوارد في شركة والصادر في أخرى',
      (tester) async {
    final auth = AuthResult(
      accessToken: 't',
      accessExpires: DateTime.now().add(const Duration(hours: 1)),
      refreshToken: 'r',
      userId: 1,
      fullName: 'موظف شركتين',
      username: 'emp_multi',
      role: 'Employee',
      companyIds: const [1, 2],
      mustChangePassword: false,
      companies: const [
        CompanyAccess(companyId: 1, modules: ['Incoming']),
        CompanyAccess(companyId: 2, modules: ['Outgoing']),
      ],
    );

    await pumpDashboard(tester, SessionState(loaded: true, activeCompanyId: 1, auth: auth));
    expect(find.text('إجمالي الوارد'), findsOneWidget);
    expect(find.text('إجمالي الصادر'), findsNothing);

    // التبديل إلى الشركة 2 **عبر الجلسة نفسها** — لا بإعادة بناء الشجرة — ليختبر ما
    // يحدث فعلاً حين يبدّل المستخدم شركته من الشريط العلوي. وهذا جوهر ADR-017.
    final container = ProviderScope.containerOf(tester.element(find.byType(DashboardScreen)));
    (container.read(sessionProvider.notifier) as _FakeSession).switchCompany(2);
    await tester.pumpAndSettle();

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('إجمالي الوارد'), findsNothing);
  });

  // ─────────────── بطاقات الموظفين والرواتب (ADR-023 ← **ADR-025**) ───────────────

  testWidgets('صاحب القسمين: تظهر بطاقاتهما كلها', (tester) async {
    await pumpDashboard(
        tester, sessionWith(['Outgoing', 'Employees', 'Payroll'], role: 'Manager'));

    expect(find.text('الموظفون الفعّالون'), findsOneWidget);
    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsOneWidget);
    // التنبيهان يظهران لأن الملخّص المُجاوَز فيه شهران غير مُسدَّدين وثلاث إجازات معلّقة.
    expect(find.text('أشهر غير مُسدَّدة'), findsOneWidget);
    expect(find.text('إجازات بانتظار الموافقة'), findsOneWidget);
  });

  testWidgets('🔐 صاحب «الموظفين» وحدهم: لا بطاقات رواتب', (tester) async {
    // جوهر ADR-025 في اللوحة: فتحُ قسمٍ لا يكشف أرقام الآخر.
    await pumpDashboard(tester, sessionWith(['Outgoing', 'Employees'], role: 'Manager'));

    expect(find.text('الموظفون الفعّالون'), findsOneWidget);
    expect(find.text('إجازات بانتظار الموافقة'), findsOneWidget);
    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsNothing);
    expect(find.text('أشهر غير مُسدَّدة'), findsNothing);
  });

  testWidgets('🔐 صاحب «الرواتب» وحدها: لا بطاقات موظفين', (tester) async {
    await pumpDashboard(tester, sessionWith(['Outgoing', 'Payroll'], role: 'Manager'));

    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsOneWidget);
    expect(find.text('الموظفون الفعّالون'), findsNothing);
    expect(find.text('إجازات بانتظار الموافقة'), findsNothing);
  });

  testWidgets('🔄 موظف بالقسمين: **يراهما الآن** — كان محجوباً قبل ADR-025', (tester) async {
    // قرار المالك 2026-08-05: الوحدة فُتحت لدور «موظف»، والحارس الباقي هو أن القسم
    // لا يُمنح تلقائياً (`AppModule.All` تستثنيهما).
    await pumpDashboard(
        tester, sessionWith(['Outgoing', 'Employees', 'Payroll'], role: 'Employee'));

    expect(find.text('الموظفون الفعّالون'), findsOneWidget);
    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsOneWidget);
  });

  testWidgets('🔐 قارئ بالقسمين: لا بطاقات إطلاقاً — الدور يحجبه', (tester) async {
    // الحارس الأهمّ الباقي بعد فتح الوحدة: بطاقةٌ تقود إلى 403 أسوأ من بطاقة غائبة.
    await pumpDashboard(
        tester, sessionWith(['Outgoing', 'Employees', 'Payroll'], role: 'Reader'));

    expect(find.text('إجمالي الصادر'), findsOneWidget);
    expect(find.text('الموظفون الفعّالون'), findsNothing);
    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsNothing);
  });

  testWidgets('مدير بلا القسمين: لا بطاقات', (tester) async {
    await pumpDashboard(tester, sessionWith(['Outgoing'], role: 'Manager'));
    expect(find.text('الموظفون الفعّالون'), findsNothing);
    expect(find.text('رواتب مُسدَّدة هذا الشهر'), findsNothing);
  });
}

/// جلسة ثابتة للاختبار — تحلّ محلّ `SessionNotifier` الذي يقرأ التخزين المحلي.
class _FakeSession extends SessionNotifier {
  _FakeSession(this._initial);
  final SessionState _initial;

  @override
  SessionState build() => _initial;

  /// تبديل الشركة الفعّالة بلا لمس التخزين الآمن (لا قناة منصّة في الاختبارات).
  void switchCompany(int companyId) => state = state.copyWith(activeCompanyId: companyId);
}
