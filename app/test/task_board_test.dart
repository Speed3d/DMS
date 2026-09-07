import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/task_board_screen.dart';

/// حرّاس **لوحة الكانبان** (الدفعة ٧).
///
/// 🔴 **حرّاسُ رسمٍ لا عقد**: اللوحة كلُّها تخطيطٌ وسحبٌ وإفلات، ولا يُكتشف عطبُها إلا
/// بالبناء الفعلي — نفس درس `hr_render_test`.
void main() {
  SessionState sessionWith({
    List<String> modules = const ['Tasks'],
    String role = 'Employee',
  }) =>
      SessionState(
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

  TaskListItem task({
    required int id,
    required String title,
    required String status,
    List<String> next = const [],
    bool overdue = false,
    int daysOverdue = 0,
  }) =>
      TaskListItem(
        taskId: id,
        title: title,
        taskType: 'Individual',
        priority: 'Normal',
        priorityLabel: 'عادية',
        status: status,
        statusLabel: kTaskStatusLabels[status] ?? status,
        progressPercent: 0,
        dueDate: DateTime(2026, 9, 30),
        isOverdue: overdue,
        daysOverdue: daysOverdue,
        daysRemaining: 5,
        attachmentCount: 0,
        nextStatuses: next,
      );

  Future<void> pumpBoard(
    WidgetTester tester, {
    required List<TaskListItem> items,
    int? total,
    SessionState? session,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FixedSession(session ?? sessionWith())),
        apiClientProvider.overrideWithValue(
            _BoardApi(TaskPage(items: items, total: total ?? items.length, page: 1, pageSize: 200))),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(width: 1400, height: 900, child: const TaskBoardScreen()),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  group('🗂️ أعمدة اللوحة', () {
    testWidgets('خمسة أعمدة — و«ملغاة» ليست عموداً', (tester) async {
      // 🔴 الإلغاء **قرارٌ نهائي بلا رجعة** في `TaskWorkflow` — وسحبةُ إصبعٍ خاطئة لا يصحّ
      //    أن تُنهي مهمةً بلا سؤال، فيبقى من شاشة التفاصيل حيث يُقرأ ويُؤكَّد.
      await pumpBoard(tester, items: []);

      for (final label in ['جديدة', 'قيد التنفيذ', 'معلّقة', 'أُعيد فتحها', 'مكتملة']) {
        expect(find.text(label), findsOneWidget, reason: 'العمود «$label» مفقود');
      }
      expect(find.text('ملغاة'), findsNothing);
    });

    testWidgets('كل بطاقةٍ في عمود حالتها، والعدّاد يطابقها', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة جديدة', status: 'New', next: ['InProgress', 'Cancelled']),
        task(id: 2, title: 'مهمة جارية', status: 'InProgress', next: ['OnHold', 'Completed']),
        task(id: 3, title: 'مهمة ثانية جارية', status: 'InProgress', next: ['Completed']),
      ]);

      expect(find.text('مهمة جديدة'), findsOneWidget);
      expect(find.text('مهمة جارية'), findsOneWidget);
      expect(find.text('مهمة ثانية جارية'), findsOneWidget);

      // عدّادان: «1» لعمود الجديدة و«2» لقيد التنفيذ — والباقي أصفار.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
    });
  });

  group('🔴 الملغاة تُعدّ ولا تُخفى صامتةً', () {
    testWidgets('عددُها يُعلَن مع موضع قراءتها', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة ملغاة', status: 'Cancelled'),
        task(id: 2, title: 'مهمة أخرى ملغاة', status: 'Cancelled'),
        task(id: 3, title: 'مهمة جديدة', status: 'New', next: ['InProgress']),
      ]);

      // الرسالة تقول العدد **وأين تُقرأ** — إخفاءٌ بلا إعلانٍ يجعل اللوحة تكذب في عددها.
      expect(find.textContaining('2 مهمة ملغاة'), findsOneWidget);
      expect(find.textContaining('قائمة المهام'), findsOneWidget);
    });

    testWidgets('ولا رسالة حين لا ملغاة', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة جديدة', status: 'New', next: ['InProgress']),
      ]);
      expect(find.textContaining('ملغاة'), findsNothing);
    });
  });

  group('🔴 القصّ يُعلَن — واللوحة لا تعرض نصف الصورة صامتةً', () {
    testWidgets('حين يتجاوز العدد ما حُمِّل، تُقال النسبة صراحةً', (tester) async {
      await pumpBoard(
        tester,
        items: [task(id: 1, title: 'مهمة', status: 'New', next: ['InProgress'])],
        total: 340,
      );
      expect(find.textContaining('1 من 340'), findsOneWidget);
    });

    testWidgets('ولا تحذير حين يكتمل العدد', (tester) async {
      await pumpBoard(
        tester,
        items: [task(id: 1, title: 'مهمة', status: 'New', next: ['InProgress'])],
      );
      expect(find.textContaining('من '), findsNothing);
    });
  });

  group('🔴 الحالة النهائية لا تُسحَب', () {
    testWidgets('بطاقةٌ بلا `nextStatuses` ليست قابلةً للسحب', (tester) async {
      // قائمةٌ فارغة تعني **حالةً نهائية** في `TaskWorkflow` — وسحبٌ لا يقود إلى شيء يُربك.
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة مكتملة نهائية', status: 'Completed'),
      ]);
      expect(find.byType(LongPressDraggable<TaskListItem>), findsNothing);
    });

    testWidgets('وبطاقةٌ لها انتقالٌ واحد تُسحَب', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة مكتملة', status: 'Completed', next: ['Reopened']),
      ]);
      expect(find.byType(LongPressDraggable<TaskListItem>), findsOneWidget);
    });
  });

  group('📐 حرّاس فيض التخطيط — لا رقمَ ارتفاعٍ مكتوبٍ بيد', () {
    // 🔴 **ارتفاعٌ مكتوب (`maxHeight: 560`) فاض 28 بكسلاً فعلاً** في أول تشغيل، لأنه يساوي
    //    «المتاح ناقص الترويسة» — **ورقمٌ يساوي مجموع أرقامٍ أخرى يُحسب لا يُكتب**
    //    (درسُ فيض 94 بكسل في وحدة الرواتب). والعلاج `stretch` + `Expanded`.
    for (final size in [
      (w: 1400.0, h: 900.0),
      (w: 900.0, h: 600.0),
      (w: 500.0, h: 400.0),
      (w: 420.0, h: 320.0),
    ]) {
      testWidgets('لا فيض عند ${size.w}×${size.h}', (tester) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() => _FixedSession(sessionWith())),
            apiClientProvider.overrideWithValue(_BoardApi(TaskPage(
              items: [
                task(id: 1, title: 'مهمة طويلة العنوان جداً لاختبار الالتفاف والقصّ معاً',
                    status: 'New', next: ['InProgress'], overdue: true, daysOverdue: 12),
                task(id: 2, title: 'مهمة ثانية', status: 'InProgress', next: ['Completed']),
              ],
              total: 2, page: 1, pageSize: 200,
            ))),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                    width: size.w, height: size.h, child: const TaskBoardScreen()),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('🔐 حارس اللوحة هو حارس المهام نفسه', () {
    testWidgets('القارئ محجوبٌ ولو مُنح القسم', (tester) async {
      await pumpBoard(tester,
          items: [task(id: 1, title: 'مهمة', status: 'New', next: ['InProgress'])],
          session: sessionWith(modules: ['Tasks'], role: 'Reader'));

      expect(find.textContaining('غير متاح'), findsOneWidget);
      expect(find.text('جديدة'), findsNothing);
    });

    testWidgets('ومَن لا يملك القسم محجوب', (tester) async {
      await pumpBoard(tester,
          items: [task(id: 1, title: 'مهمة', status: 'New', next: ['InProgress'])],
          session: sessionWith(modules: ['Outgoing'], role: 'Manager'));

      expect(find.textContaining('غير متاح'), findsOneWidget);
    });
  });

  group('🔴 المهمة المتأخّرة تُميَّز — والصفر ليس تأخّراً', () {
    testWidgets('المتأخّرة تحمل عدد أيامها', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة متأخرة', status: 'New',
            next: ['InProgress'], overdue: true, daysOverdue: 4),
      ]);
      expect(find.text('متأخرة 4 يوم'), findsOneWidget);
    });

    testWidgets('وغير المتأخّرة بلا وسمٍ إطلاقاً', (tester) async {
      await pumpBoard(tester, items: [
        task(id: 1, title: 'مهمة في موعدها', status: 'New', next: ['InProgress']),
      ]);
      expect(find.textContaining('متأخرة'), findsNothing);
    });
  });
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

/// عميلٌ يردّ بصفحةٍ ثابتة — بلا شبكة ولا مؤقّتات (درس «الجرس يستطلع في اختبارٍ بلا خادم»).
class _BoardApi extends ApiClient {
  _BoardApi(this.page)
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final TaskPage page;

  @override
  Future<TaskPage> tasks({
    String? status, String? priority, int? departmentId, int? assignedTo, int? createdBy,
    DateTime? dueFrom, DateTime? dueTo, bool? isOverdue, bool mineOnly = false,
    String? search, int page = 1, int pageSize = 25,
  }) async =>
      this.page;

  @override
  Future<TaskSummaryModel> taskSummary() async =>
      TaskSummaryModel(total: 0, active: 0, overdue: 0, dueToday: 0,
          completedThisMonth: 0, mineActive: 0);
}
