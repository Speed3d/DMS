import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/job_watcher.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/backup_screen.dart';
import 'package:dms_app/widgets/job_progress_card.dart';

/// حرّاس **متابعة العمليات الطويلة** — النسخ والاستعادة والمرآة وحذف الشركة صارت تجري في
/// الخلفية لأن Cloudflare يقطع كلَّ طلبٍ لا يردّ خلال ~100 ثانية.
///
/// 🔴 **أهمّ حارسٍ هنا**: أثناء الاستعادة (503) **لا يُرسَل طلبٌ يحتاج الرمز** — تُسأل نقطة
/// الحالة العامّة وحدها. لو سُئلت نقطة العملية وانتهت صلاحية الرمز لحاول العميل التجديد،
/// والتجديد مرفوضٌ في الصيانة، **فيُخرَج المالك من النظام في منتصف الاستعادة**.
void main() {
  JobInfo job(String state, {int? percent, String? message, String stage = 'مرحلة'}) => JobInfo(
      id: 'j1', kind: 'backup', title: 'نسخة احتياطية كاملة', state: state,
      stage: stage, percent: percent, message: message);

  group('watchJob', () {
    test('يتابع حتى النجاح ويُبلّغ كلّ تحديث', () async {
      final api = _ScriptedApi([job('Running', percent: 40), job('Succeeded', message: 'تمت')]);
      final seen = <JobInfo>[];
      final end = await watchJob(api, job('Running'), onUpdate: seen.add, interval: Duration.zero);
      expect(end.succeeded, isTrue);
      expect(end.message, 'تمت');
      expect(seen.map((j) => j.percent), [40, null]);
    });

    test('الفشل يُعاد حالةً برسالته — لا استثناءً يضيّعها', () async {
      final api = _ScriptedApi([job('Failed', message: 'القرص ممتلئ')]);
      final end = await watchJob(api, job('Running'), interval: Duration.zero);
      expect(end.succeeded, isFalse);
      expect(end.message, 'القرص ممتلئ');
    });

    test('🔴 أثناء الصيانة لا يُسأل إلا /system/status — ثم تُستأنف المتابعة', () async {
      final api = _ScriptedApi(
        [job('Running'), ApiException(503, 'صيانة'), job('Succeeded', message: 'تمت الاستعادة')],
        maintenance: [true, true, false],
      );
      final end = await watchJob(api, job('Running'), interval: Duration.zero);
      expect(end.succeeded, isTrue);
      expect(api.maintenanceChecks, 3);
      expect(api.jobCallsDuringMaintenance, 0,
          reason: 'طلبٌ بالرمز أثناء الصيانة قد يُطلق تجديداً مرفوضاً فيُخرج المستخدم');
    });

    test('عمليةٌ ضاعت (404 — أُعيد تشغيل الخادم) تُقال صراحةً لا تُعلَّق', () async {
      final api = _ScriptedApi([ApiException(404, 'غير معروفة')]);
      await expectLater(
        watchJob(api, job('Running'), interval: Duration.zero),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('انقطعت'))),
      );
    });

    test('انقطاعٌ عابر في الشبكة لا يُعلن الفشل — العملية تجري في الخادم', () async {
      final net = ApiException(null, 'لا اتصال', isNetworkError: true);
      final api = _ScriptedApi([net, net, job('Succeeded', message: 'تمت')]);
      final end = await watchJob(api, job('Running'), interval: Duration.zero);
      expect(end.succeeded, isTrue);
    });

    test('وانقطاعٌ دائم يُعلَن بعد حدّه — لا انتظارٌ بلا نهاية', () async {
      final net = ApiException(null, 'لا اتصال', isNetworkError: true);
      final api = _ScriptedApi(List.filled(10, net));
      await expectLater(
        watchJob(api, job('Running'), interval: Duration.zero, maxNetworkErrors: 3),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('JobInfo.fromJson — النسبة الغائبة تبقى null (شريطٌ غير محدَّد لا صفرٌ كاذب)', () {
    final j = JobInfo.fromJson({
      'id': 'a', 'kind': 'restore', 'title': 'استعادة', 'state': 'Running', 'stage': 'استعادة القاعدة',
      'percent': null, 'message': null, 'result': null,
    });
    expect(j.isRunning, isTrue);
    expect(j.percent, isNull);
  });

  testWidgets('حوار المتابعة (حذف الشركة) يظهر · لا يُغلق باللمس · ويُغلق وحده عند الانتهاء', (tester) async {
    final api = _ScriptedApi([
      job('Running', stage: 'نسخة احتياطية قبل الحذف'),
      job('Succeeded', message: 'حُذفت الشركة'),
    ]);
    JobInfo? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () async {
            final start = job('Running', stage: 'في الانتظار');
            result = await showJobProgressDialog(
                ctx, (onUpdate) => watchJob(api, start, onUpdate: onUpdate, interval: const Duration(seconds: 1)), start);
          },
          child: const Text('احذف'),
        )),
      )),
    ));

    await tester.tap(find.text('احذف'));
    await tester.pump();
    await tester.pump();
    expect(find.text('نسخة احتياطية قبل الحذف'), findsOneWidget);

    // اللمس خارج الحوار لا يُغلقه — العملية لم تنتهِ.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('نسخة احتياطية قبل الحذف'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('جارية'), findsNothing, reason: 'الحوار أُغلق وحده');
    expect(result?.succeeded, isTrue);
    expect(result?.message, 'حُذفت الشركة');
  });

  group('شاشة النسخ', () {
    Future<_BackupApi> pump(WidgetTester tester, _BackupApi api) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FixedSession()),
          apiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen())),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return api;
    }

    testWidgets('«نسخة احتياطية الآن» تبدأ ثم تُتابَع حتى رسالة النجاح', (tester) async {
      final api = await pump(tester, _BackupApi(polls: [
        job('Running', percent: 50, stage: 'ضغط الملفات (5 من 10)'),
        job('Succeeded', message: 'تمت النسخة الاحتياطية (1.0 MB).'),
      ]));

      await tester.tap(find.text('نسخة احتياطية الآن'));
      await tester.pump();
      expect(api.runCalls, 1);
      // البطاقة تظهر والمرحلة معها
      await tester.pump();
      expect(find.textContaining('جارية'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('تمت النسخة الاحتياطية (1.0 MB).'), findsOneWidget);
      expect(find.textContaining('جارية'), findsNothing);
    });

    testWidgets('الرفض الفوريّ (عمليةٌ أخرى جارية) يُعرض كما هو ولا تظهر بطاقة', (tester) async {
      final api = _BackupApi(polls: const [], startError: ApiException(409, '«استعادة نسخة احتياطية» جاريةٌ الآن'));
      await pump(tester, api);
      await tester.tap(find.text('نسخة احتياطية الآن'));
      await tester.pumpAndSettle();
      expect(find.textContaining('جاريةٌ الآن'), findsOneWidget);
      expect(find.textContaining('— جارية'), findsNothing);
    });

    testWidgets('عمليةٌ جارية من قبل تُستأنف متابعتها عند فتح الشاشة', (tester) async {
      final api = _BackupApi(
        running: job('Running', percent: 10, stage: 'نسخ الملفات (1 من 10)'),
        // ⚠️ السؤال الأوّل **فوريّ** (لا ينتظر المهلة) — فالحالة الأولى «جارية» كما في الواقع.
        polls: [job('Running', percent: 20, stage: 'نسخ الملفات (2 من 10)'), job('Succeeded', message: 'المرآة اكتملت')],
      );
      await pump(tester, api);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('جارية'), findsOneWidget);
      expect(find.text('نسخ الملفات (2 من 10)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('المرآة اكتملت'), findsOneWidget);
    });
  });
}

/// عميلٌ يردّ على `job()` بتسلسلٍ مكتوب — حالاتٍ أو أخطاء.
class _ScriptedApi extends ApiClient {
  _ScriptedApi(this._script, {List<bool> maintenance = const []})
      : _maintenance = List.of(maintenance),
        super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final List<Object> _script;
  final List<bool> _maintenance;
  int _i = 0;
  bool _inMaintenance = false;
  int maintenanceChecks = 0;
  int jobCallsDuringMaintenance = 0;

  @override
  Future<JobInfo> job(String id) async {
    if (_inMaintenance) jobCallsDuringMaintenance++;
    final next = _script[_i < _script.length ? _i++ : _script.length - 1];
    if (next is ApiException) {
      if (next.status == 503) _inMaintenance = true;
      throw next;
    }
    return next as JobInfo;
  }

  @override
  Future<bool> isUnderMaintenance() async {
    maintenanceChecks++;
    final m = _maintenance.isEmpty ? false : _maintenance.removeAt(0);
    _inMaintenance = m;
    return m;
  }
}

class _BackupApi extends ApiClient {
  _BackupApi({required this.polls, this.running, this.startError})
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final List<JobInfo> polls;
  final JobInfo? running;
  final ApiException? startError;
  int runCalls = 0;
  int _p = 0;
  bool _resumed = false;

  @override
  Future<BackupScheduleModel> backupSchedule() async => BackupScheduleModel('Off', false, 2, null, null);
  @override
  Future<List<BackupRecordModel>> backupList() async => const [];
  @override
  Future<BackupCoverage> backupCoverage() async =>
      BackupCoverage(urgency: 'Ok', message: 'سليمة', maxAgeDays: 30);

  @override
  Future<JobInfo?> currentJob() async {
    if (_resumed) return null;
    _resumed = true;
    return running;
  }

  @override
  Future<JobInfo> backupRun() async {
    runCalls++;
    if (startError != null) throw startError!;
    return const JobInfo(id: 'j1', kind: 'backup', title: 'نسخة احتياطية كاملة', state: 'Running', stage: 'في الانتظار');
  }

  @override
  Future<JobInfo> job(String id) async => polls[_p < polls.length ? _p++ : polls.length - 1];
}

class _FixedSession extends SessionNotifier {
  @override
  SessionState build() => SessionState(
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
}
