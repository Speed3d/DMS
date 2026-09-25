import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/backup_providers.dart';
import 'package:dms_app/core/backup_upload.dart';
import 'package:dms_app/core/job_watcher.dart';
import 'package:dms_app/core/remembered_user.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/backup_screen.dart';
import 'package:dms_app/screens/login_screen.dart';

import 'support/quiet_status.dart';

/// الدفعة ج (ADR-055): استعادة نسخةٍ من جهاز المستخدم · شريط الأزرار · الفلترة · «تذكّرني».
void main() {
  // ───────────────────── تقطيع التدفّق ─────────────────────
  group('rechunk', () {
    Future<List<int>> sizes(List<List<int>> parts, int size) async =>
        [await for (final c in rechunk(Stream.fromIterable(parts), size)) c.length];

    test('قطعٌ بالحجم نفسه والأخيرة أصغر — ولا يضيع بايت', () async {
      final data = List<int>.generate(10, (i) => i);
      expect(await sizes([data], 4), [4, 4, 2]);
      final joined = <int>[
        await for (final c in rechunk(Stream.fromIterable([data]), 4)) ...c,
      ];
      expect(joined, data, reason: 'الترتيب والمحتوى كما هما');
    });

    test('مدخلٌ غير منتظم (كما يعطيه المتصفّح) يُعاد تقطيعه بانتظام', () async {
      expect(await sizes([[1], [2, 3, 4, 5, 6], [7, 8], [9]], 3), [3, 3, 3]);
      expect(await sizes([[1, 2], [3]], 5), [3]);
      expect(await sizes([], 5), isEmpty);
    });
  });

  // ───────────────────── الرفع ─────────────────────
  group('uploadBackupFile', () {
    test('القطع بالترتيب ثم «اكتمل» — والنسبة تصل 100%', () async {
      final api = _UploadApi();
      final progress = <double>[];
      final job = await uploadBackupFile(api,
          fileName: 'b.zip', sizeBytes: 10,
          content: Stream.fromIterable([List<int>.filled(10, 7)]),
          onProgress: progress.add, retryDelay: Duration.zero);
      expect(api.chunks, [(0, 4), (1, 4), (2, 2)]);
      expect(api.completed, isTrue);
      expect(job.id, 'job-1');
      expect(progress.last, 1.0);
    });

    test('🔑 انقطاعٌ عابر يُعاد القطعة نفسها — لا يُلغى الرفع', () async {
      final api = _UploadApi(failNetworkOnce: 1);
      await uploadBackupFile(api,
          fileName: 'b.zip', sizeBytes: 10,
          content: Stream.fromIterable([List<int>.filled(10, 7)]), retryDelay: Duration.zero);
      expect(api.chunks.map((c) => c.$1), [0, 1, 1, 2], reason: 'القطعة 1 أُعيدت');
      expect(api.aborted, isFalse);
    });

    test('🔴 فشلٌ نهائيّ يُلغي الرفع — فلا يبقى نصفُ ملفٍّ على الخادم', () async {
      final api = _UploadApi(rejectAt: 1);
      await expectLater(
          uploadBackupFile(api,
              fileName: 'b.zip', sizeBytes: 10,
              content: Stream.fromIterable([List<int>.filled(10, 7)]), retryDelay: Duration.zero),
          throwsA(isA<ApiException>()));
      expect(api.aborted, isTrue);
      expect(api.completed, isFalse);
    });
  });

  // ───────────────────── الفلترة والوصف ─────────────────────
  group('filterBackups', () {
    final all = [
      _rec(1, type: 'Manual', category: 'Manual', scope: 'Full', note: 'قبل التحديث'),
      _rec(2, type: 'Scheduled', category: 'Daily', scope: 'DbOnly'),
      _rec(3, type: 'Uploaded', category: 'Manual', scope: 'Full', note: 'مرفوعة من جهاز: dev.zip'),
      _rec(4, type: 'Scheduled', category: 'Daily', scope: 'DbOnly', status: 'Failed'),
    ];
    List<int> ids(List<BackupRecordModel> l) => l.map((r) => r.id).toList();

    test('المرفوعة نوعٌ مستقلّ — ولا تظهر ضمن «يدوية»', () {
      expect(ids(filterBackups(all, kind: 'Uploaded')), [3]);
      expect(ids(filterBackups(all, kind: 'Manual')), [1]);
      expect(ids(filterBackups(all, kind: 'Daily')), [2, 4]);
    });

    test('النطاق والحالة والبحث في الاسم والملاحظة', () {
      expect(ids(filterBackups(all, scope: 'Full')), [1, 3]);
      expect(ids(filterBackups(all, succeeded: false)), [4]);
      expect(ids(filterBackups(all, query: 'DEV.ZIP')), [3], reason: 'البحث لا يفرّق بين الحروف');
      expect(ids(filterBackups(all, query: 'التحديث')), [1]);
      expect(ids(filterBackups(all)), [1, 2, 3, 4]);
    });

    test('وصف النوع يميّز المرفوعة', () {
      expect(backupKindLabel(all[2]), 'مرفوعة من جهاز');
      expect(backupKindLabel(all[1]), 'يومية');
    });
  });

  // ───────────────────── «تذكّرني» ─────────────────────
  group('RememberedUser', () {
    test('يحفظ الاسم وحده إن طُلب — ويمحوه إن لم يُطلب', () async {
      SharedPreferences.setMockInitialValues({});
      await RememberedUser.afterLogin('  sinan ', remember: true);
      expect(await RememberedUser.load(), 'sinan');
      await RememberedUser.afterLogin('sinan', remember: false);
      expect(await RememberedUser.load(), isNull, reason: 'جهازٌ عامّ لا يحتفظ باسم مَن لم يطلب');
    });

    testWidgets('شاشة الدخول تملأ الاسم المحفوظ وتؤشّر «تذكّرني»', (tester) async {
      SharedPreferences.setMockInitialValues({'dms_remembered_username': 'sinan'});
      await _pumpLogin(tester);
      expect(find.widgetWithText(TextField, 'sinan'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('وبلا اسمٍ محفوظ: الحقل فارغ والمربّع غير مؤشَّر', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpLogin(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });
  });

  // ───────────────────── شاشة النسخ ─────────────────────
  group('شاشة النسخ الاحتياطي', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1300, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_ScreenApi()),
          backupCoverageProvider.overrideWith((ref) async => BackupCoverage(urgency: 'Ok', message: 'محميّة', maxAgeDays: 30)),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('🧰 شريط الأزرار الأربعة في الأعلى — ومنها «استعادة نسخة من جهازي»', (tester) async {
      await pump(tester);
      for (final k in ['backup-run-now', 'backup-upload', 'backup-mirror-restore', 'backup-mirror-run']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('استعادة نسخة من جهازي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('🔎 البحث يُضيّق القائمة ويُعلن «المعروض من الكل»', (tester) async {
      await pump(tester);
      expect(find.text('النسخ السابقة (2)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('backup-search')), 'dev');
      await tester.pumpAndSettle();
      expect(find.text('النسخ السابقة — المعروض 1 من 2'), findsOneWidget);
      expect(find.textContaining('مرفوعة من جهاز •'), findsOneWidget);
    });

    testWidgets('لا تفيض على هاتف', (tester) async {
      tester.view.physicalSize = const Size(380, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_ScreenApi()),
          backupCoverageProvider.overrideWith((ref) async => BackupCoverage(urgency: 'Ok', message: 'محميّة', maxAgeDays: 30)),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen())),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpLogin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [quietSystemStatus],
    child: const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: LoginScreen())),
  ));
  await tester.pumpAndSettle();
}

BackupRecordModel _rec(int id,
        {required String type, required String category, required String scope, String status = 'Success', String? note}) =>
    BackupRecordModel(id, DateTime(2026, 9, id), 'backup-$id.zip', 1024 * 1024, type, scope, category, status, note);

class _UploadApi extends ApiClient {
  _UploadApi({this.failNetworkOnce, this.rejectAt})
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final int? failNetworkOnce;
  final int? rejectAt;
  bool _failed = false;
  final chunks = <(int, int)>[];
  bool completed = false, aborted = false;

  @override
  Future<BackupUploadSession> backupUploadStart(String fileName, int sizeBytes) async =>
      const BackupUploadSession('abc', 4, 0, 0);

  @override
  Future<BackupUploadSession> backupUploadChunk(String uploadId, int index, Uint8List bytes) async {
    chunks.add((index, bytes.length));
    if (index == failNetworkOnce && !_failed) {
      _failed = true;
      throw ApiException(null, 'انقطع', isNetworkError: true);
    }
    if (index == rejectAt) throw ApiException(409, 'وصلت القطعة قبل أختها');
    return BackupUploadSession(uploadId, 4, 0, index + 1);
  }

  @override
  Future<JobInfo> backupUploadComplete(String uploadId) async {
    completed = true;
    return JobInfo.fromJson({'id': 'job-1', 'kind': 'backup-upload', 'title': 'فحص', 'state': 'Running'});
  }

  @override
  Future<void> backupUploadAbort(String uploadId) async => aborted = true;
}

class _ScreenApi extends ApiClient {
  _ScreenApi() : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<BackupScheduleModel> backupSchedule() async => BackupScheduleModel('Off', false, 2, null, null);

  @override
  Future<List<BackupRecordModel>> backupList() async => [
        _rec(1, type: 'Manual', category: 'Manual', scope: 'Full'),
        _rec(2, type: 'Uploaded', category: 'Manual', scope: 'Full', note: 'مرفوعة من جهاز: dev.zip'),
      ];

  @override
  Future<JobInfo?> currentJob() async => null;
}
