import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';
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
}
