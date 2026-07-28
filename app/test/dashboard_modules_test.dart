import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/archive_providers.dart';
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
          archiveListProvider.overrideWith((ref) async => <ArchiveListItem>[]),
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
    expect(find.text('وارد مؤرشف'), findsOneWidget);

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
