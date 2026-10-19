import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/task_detail_screen.dart';
import 'package:dms_app/widgets/task_badges.dart';

/// حرّاس واجهة المهام (ADR-037).
///
/// 🔴 **حرّاسُ رسمٍ حقيقي لا عقدٍ فقط**: العطلان اللذان وصلا المالك في وحدة الرواتب
/// (فيض 94 بكسل · `ListTile` داخل `CustomCard`) **لم تلتقطهما** اختبارات العقد ولا الوحدة
/// لأنها **لا ترسم**. وهذه تبني شجرةً وتقيس.
void main() {
  Widget wrap(Widget child, {double width = 1200, double height = 800}) => MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, height: height, child: child),
            ),
          ),
        ),
      );

  group('🏷️ شارات المهام', () {
    testWidgets('لكل حالةٍ لونٌ متمايز — و«أُعيد فتحها» ليست «جديدة»', (tester) async {
      // 🔴 سببُ وجود شارةٍ خاصّة بدل [StatusPill]: تلك تطابق بـ`contains` على حالات
      //    الصادر والوارد، فتعطي «Reopened» لونَ «جديد» فيضيع الفرق الذي بُنيت لإظهاره.
      final colors = {
        for (final s in kTaskStatusLabels.keys) s: TaskStatusPill.colorFor(s, false),
      };

      expect(colors['New'], isNot(colors['Reopened']));
      expect(colors['InProgress'], isNot(colors['Completed']));
      expect(colors['Cancelled'], isNot(colors['Completed']));
    });

    testWidgets('والتسمية من الخادم تسبق المحلّية عند التعارض', (tester) async {
      await tester.pumpWidget(wrap(
        const TaskStatusPill(status: 'InProgress', label: 'تسمية الخادم'),
      ));
      expect(find.text('تسمية الخادم'), findsOneWidget);
      expect(find.text('قيد التنفيذ'), findsNothing);
    });

    testWidgets('وتسقط على المحلّية إن غابت تسمية الخادم', (tester) async {
      await tester.pumpWidget(wrap(const TaskStatusPill(status: 'OnHold')));
      expect(find.text('معلّقة'), findsOneWidget);
    });

    testWidgets('🔴 «متأخرة» تُقرأ من الخادم ولا تُحسب بساعة الجهاز', (tester) async {
      // القاعدة «الموعد يومٌ لا لحظة» تعيش في `TaskWorkflow.IsOverdue` بتوقيت بغداد.
      // حسابُها هنا يجعل مهمةً حمراء عند مستخدمٍ وخضراء عند زميله في اللحظة نفسها.
      await tester.pumpWidget(wrap(
        const TaskDueLabel(isOverdue: true, daysOverdue: 3, daysRemaining: -3),
      ));
      expect(find.text('متأخرة 3 أيام'), findsOneWidget);
    });

    testWidgets('وموعدُ اليوم ليس متأخراً — «تستحق اليوم»', (tester) async {
      await tester.pumpWidget(wrap(
        const TaskDueLabel(isOverdue: false, daysOverdue: 0, daysRemaining: 0),
      ));
      expect(find.text('تستحق اليوم'), findsOneWidget);
      expect(find.textContaining('متأخرة'), findsNothing);
    });

    testWidgets('ويومٌ واحدٌ يُقال «متأخرة يوماً» لا «متأخرة 1 أيام»', (tester) async {
      await tester.pumpWidget(wrap(
        const TaskDueLabel(isOverdue: true, daysOverdue: 1, daysRemaining: -1),
      ));
      expect(find.text('متأخرة يوماً'), findsOneWidget);
    });
  });

  group('📐 حرّاس الرسم — الشارات لا تفيض عند العروض الضيّقة', () {
    // 🔴 **العروض مقيسة لا مخمَّنة** (درس الدفعة ٢ من وحدة الرواتب: خُمّنت العتبة 880
    //    فوجدها الحارس تفيض عند 880 بالضبط، والصحيح 920).
    for (final width in [320.0, 380.0, 420.0, 500.0, 700.0, 920.0, 1200.0, 1600.0]) {
      testWidgets('صفٌّ من الشارات الثلاث عند $width بكسل', (tester) async {
        await tester.pumpWidget(wrap(
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: const [
              TaskStatusPill(status: 'InProgress', label: 'قيد التنفيذ'),
              TaskPriorityBadge(priority: 'Urgent', label: 'عاجلة'),
              TaskDueLabel(isOverdue: true, daysOverdue: 12, daysRemaining: -12),
            ],
          ),
          width: width,
          height: 300,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('🗓️ التواريخ التقويمية لا تُمسّ', () {
    test('🔴 يومٌ يُقرأ كما هو — لا تحويلَ بالمنطقة الزمنية', () {
      // تحويلُ **يومٍ** بالمنطقة الزمنية يُنقصه يوماً عند إزاحةٍ سالبة — وهو العطل
      // المعكوس المسجَّل في ADR-032 وG18، وقد وقع نظيرُه في الخادم وعولج في الدفعة ٣.
      final d = parseCalendarDate('2026-09-13T00:00:00');
      expect(d.year, 2026);
      expect(d.month, 9);
      expect(d.day, 13);
    });

    test('وحتى لو وصل بلاحقة Z فاليوم لا يتزحزح', () {
      final d = parseCalendarDate('2026-09-13T00:00:00Z');
      expect(d.day, 13, reason: 'اليوم يُقرأ كما وصل لا يُحوَّل');
    });

    test('والفارغ يعطي null لا تاريخاً مخترعاً', () {
      expect(parseCalendarDateOrNull(null), isNull);
      expect(parseCalendarDateOrNull(''), isNull);
    });
  });

  group('🔗 عقد النماذج — كل حقلٍ محسوبٍ يعبر', () {
    // 🔴 درس `PaidAt` (ADR-026): حقلٌ تحسبه الخدمة ولا يقرؤه النموذج يبقى فارغاً **دائماً**
    //    بلا خطأٍ يكشفه — واكتُشف هناك بقراءة الملف صدفةً لا ببلاغٍ ولا باختبار.
    final sample = {
      'taskId': 7,
      'taskNumber': 'TSA-TSK-2026-00007',
      'title': 'مهمة اختبار',
      'taskType': 'Department',
      'taskTypeLabel': 'قسم',
      'priority': 'High',
      'priorityLabel': 'عالية',
      'status': 'InProgress',
      'statusLabel': 'قيد التنفيذ',
      'progressPercent': 40,
      'dueDate': '2026-09-20T00:00:00',
      'startDate': '2026-09-06T00:00:00',
      'isOverdue': false,
      'daysOverdue': 0,
      'daysRemaining': 7,
      'departmentId': 3,
      'departmentName': 'القسم القانوني',
      'assignedToUserId': 5,
      'assignedToUserName': 'سنان',
      'createdByUserId': 1,
      'createdByUserName': 'المدير',
      'isRecurring': false,
      'createdAt': '2026-09-06T10:00:00',
      'rowVersion': 'AAAAAAAApBE=',
      'nextStatuses': ['OnHold', 'Completed', 'Cancelled'],
      'canEdit': true,
    };

    test('النموذج يقرأ الحقول المحسوبة كلها', () {
      final t = TaskModel.fromJson(Map<String, dynamic>.from(sample));

      expect(t.statusLabel, 'قيد التنفيذ');
      expect(t.priorityLabel, 'عالية');
      expect(t.taskTypeLabel, 'قسم');
      expect(t.departmentName, 'القسم القانوني');
      expect(t.assignedToUserName, 'سنان');
      expect(t.createdByUserName, 'المدير');
      expect(t.daysRemaining, 7);
      expect(t.canEdit, isTrue);
      expect(t.nextStatuses, hasLength(3));
    });

    test('🔴 و`rowVersion` نصٌّ يُقرأ كما هو — لا مصفوفةَ أرقام', () {
      // `byte[]` في ASP.NET Core يُسلسَل base64، وقراءتُه `List<int>` أسقطت شاشة
      // كشف الرواتب كاملةً (بلاغ المالك 2026-08-04).
      final t = TaskModel.fromJson(Map<String, dynamic>.from(sample));
      expect(t.rowVersion, 'AAAAAAAApBE=');
    });

    test('و`isDepartmentTask` مشتقٌّ لا مكرَّر', () {
      final t = TaskModel.fromJson(Map<String, dynamic>.from(sample));
      expect(t.isDepartmentTask, isTrue);
      expect(t.isActive, isTrue);
      expect(t.isCompleted, isFalse);
    });

    test('واستجابةٌ ناقصةٌ لا تُسقط النموذج', () {
      // عقدٌ أقدم أو حقلٌ اختياريّ غائب يجب ألّا يرمي — فالسقوط يمنع الشاشة كلَّها.
      final t = TaskModel.fromJson({'taskId': 1, 'dueDate': '2026-09-20T00:00:00'});
      expect(t.title, '');
      expect(t.status, 'New');
      expect(t.nextStatuses, isEmpty);
      expect(t.canEdit, isFalse);
    });

    test('وصفحةٌ فارغة تُقرأ ولا ترمي', () {
      final p = TaskPage.fromJson({'items': [], 'total': 0, 'page': 1, 'pageSize': 25});
      expect(p.items, isEmpty);
      expect(p.total, 0);
    });
  });

  group('💬 التعليقات الفورية في شاشة المهمة', () {
    testWidgets('تظهر تعليقات المرسل والمستقبل فوراً دون الخروج من الشاشة أو إعادة التبويب',
        (tester) async {
      final api = _LiveCommentsFakeApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_TaskSessionNotifier.new),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: TaskDetailScreen(taskId: 7),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // الانتقال إلى تبويب «التعليقات»
      await tester.tap(find.text('التعليقات'));
      await tester.pumpAndSettle();
      expect(find.text('لا تعليقات بعد'), findsOneWidget);

      // المستخدم 1 يرسل تعليقاً — يظهر فوراً مع بقاء تبويب التعليقات مفتوحاً
      await tester.enterText(find.byType(TextField), 'مرحبا، هل اكتمل المرفق؟');
      await tester.tap(find.byTooltip('إرسال'));
      await tester.pumpAndSettle();

      expect(find.text('مرحبا، هل اكتمل المرفق؟'), findsOneWidget);
      expect(find.byTooltip('إرسال'), findsOneWidget);

      // المستخدم 2 يرسل ردّاً من جهازه — يظهر تلقائياً عبر الاستقصاء الدوري دون مغادرة الشاشة
      api.simulateIncomingReplyFromOtherUser('نعم، تم رفعه الآن.');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('نعم، تم رفعه الآن.'), findsOneWidget);
      expect(find.text('مرحبا، هل اكتمل المرفق؟'), findsOneWidget);
    });

    testWidgets('تظهر شارة التعليقات غير المقروءة على كارت المهمة وتُوسم كمقروءة عند فتحها',
        (tester) async {
      final api = _LiveCommentsFakeApi()
        ..simulateIncomingReplyFromOtherUser('رسالة غير مقروءة ١')
        ..simulateIncomingReplyFromOtherUser('رسالة غير مقروءة ٢');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_TaskSessionNotifier.new),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: TaskUnreadCommentsBadge(count: 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('تعليقات جديدة (2)'), findsOneWidget);

      // عند فتح شاشة تفاصيل المهمة مع initialTab: 1 يفتح مباشرةً على المحادثة ويسم الإشعارات كمقروءة
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_TaskSessionNotifier.new),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: TaskDetailScreen(taskId: 7, initialTab: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('رسالة غير مقروءة ١'), findsOneWidget);
      expect(find.text('رسالة غير مقروءة ٢'), findsOneWidget);
      expect(api.unreadCountForTask(7), 0);
    });
  });
}

class _TaskSessionNotifier extends SessionNotifier {
  @override
  SessionState build() => SessionState(
        loaded: true,
        activeCompanyId: 1,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'أحمد',
          username: 'ahmed',
          role: 'Employee',
          companyIds: const [1],
          mustChangePassword: false,
          companies: [
            CompanyAccess(companyId: 1, modules: const ['Tasks']),
          ],
        ),
      );
}

class _LiveCommentsFakeApi extends ApiClient {
  _LiveCommentsFakeApi()
      : super(baseUrl: 'http://localhost:0', token: () => 't', companyId: () => 1);

  int _nextUpdateId = 2;
  int _nextNotificationId = 100;
  final List<NotificationModel> _notifications = [];
  final List<TaskUpdateModel> _updates = [
    TaskUpdateModel(
      updateId: 1,
      updateType: 'Created',
      description: 'أُنشئت المهمة',
      updatedByUserId: 1,
      updatedByUserName: 'أحمد',
      updatedAt: DateTime(2026, 9, 6, 10, 0),
    ),
  ];

  @override
  Future<TaskModel> task(int id) async => TaskModel.fromJson({
        'taskId': id,
        'taskNumber': 'TSA-TSK-2026-00007',
        'title': 'مهمة اختبار المحادثة',
        'taskType': 'Individual',
        'taskTypeLabel': 'فردية',
        'priority': 'Normal',
        'priorityLabel': 'عادية',
        'status': 'InProgress',
        'statusLabel': 'قيد التنفيذ',
        'progressPercent': 50,
        'dueDate': '2026-09-20T00:00:00',
        'isOverdue': false,
        'daysOverdue': 0,
        'daysRemaining': 7,
        'assignedToUserId': 1,
        'assignedToUserName': 'أحمد',
        'createdByUserId': 2,
        'createdByUserName': 'المدير',
        'isRecurring': false,
        'createdAt': '2026-09-06T10:00:00',
        'rowVersion': 'AAAAAAAApBE=',
        'nextStatuses': ['Completed'],
        'canEdit': false,
      });

  @override
  Future<List<TaskUpdateModel>> taskUpdates(int id) async =>
      List<TaskUpdateModel>.from(_updates);

  @override
  Future<List<TaskParticipant>> taskParticipants(int id) async => const [];

  @override
  Future<List<AttachmentModel>> taskAttachments(int id) async => const [];

  @override
  Future<NotificationPage> notifications(
          {int page = 1, int pageSize = 25, bool unreadOnly = false}) async =>
      NotificationPage(
        items: unreadOnly
            ? _notifications.where((n) => !n.isRead).toList()
            : List<NotificationModel>.from(_notifications),
        total: _notifications.length,
        page: 1,
        pageSize: pageSize,
      );

  @override
  Future<int> unreadNotificationCount() async =>
      _notifications.where((n) => !n.isRead).length;

  @override
  Future<void> markNotificationRead(int id) async {
    final idx = _notifications.indexWhere((n) => n.notificationId == id);
    if (idx != -1) {
      final old = _notifications[idx];
      _notifications[idx] = NotificationModel(
        notificationId: old.notificationId,
        title: old.title,
        body: old.body,
        category: old.category,
        entityType: old.entityType,
        entityId: old.entityId,
        priority: old.priority,
        isRead: true,
        readAt: DateTime.now(),
        createdAt: old.createdAt,
      );
    }
  }

  int unreadCountForTask(int taskId) =>
      _notifications.where((n) => !n.isRead && n.entityId == taskId).length;

  @override
  Future<TaskUpdateModel> addTaskComment(int id, String text) async {
    final added = TaskUpdateModel(
      updateId: _nextUpdateId++,
      updateType: 'Comment',
      description: 'علّق: $text',
      comment: text,
      updatedByUserId: 1,
      updatedByUserName: 'أحمد',
      updatedAt: DateTime.now(),
    );
    _updates.insert(0, added);
    return added;
  }

  void simulateIncomingReplyFromOtherUser(String text) {
    final reply = TaskUpdateModel(
      updateId: _nextUpdateId++,
      updateType: 'Comment',
      description: 'علّق: $text',
      comment: text,
      updatedByUserId: 2,
      updatedByUserName: 'المدير',
      updatedAt: DateTime.now(),
    );
    _updates.insert(0, reply);
    _notifications.insert(
      0,
      NotificationModel(
        notificationId: _nextNotificationId++,
        title: 'تعليقٌ جديد على مهمة',
        body: text,
        category: 'Task',
        entityType: 'DmsTask',
        entityId: 7,
        priority: 'Normal',
        isRead: false,
        createdAt: DateTime.now(),
      ),
    );
  }
}


