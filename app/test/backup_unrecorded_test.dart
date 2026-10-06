import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/backup_providers.dart';
import 'package:dms_app/core/job_watcher.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/backup_screen.dart';

/// ملفات نسخٍ على القرص لا يعرفها النظام (ADR-059): تُعرض ولا تُحذف تلقائياً — إعادةٌ إلى القائمة أو حذفٌ بتأكيد.
void main() {
  late _Api api;

  Future<void> pump(WidgetTester tester, {List<UnrecordedBackupModel>? files, double width = 1300}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = _Api(files ?? []);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        backupCoverageProvider.overrideWith((ref) async => BackupCoverage(urgency: 'Ok', message: 'محميّة', maxAgeDays: 30)),
      ],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen())),
      ),
    ));
    await tester.pumpAndSettle();
  }

  UnrecordedBackupModel file(String name, {String? problem, int mb = 340}) =>
      UnrecordedBackupModel(name, mb * 1048576, DateTime.utc(2026, 9, 23, 8), DateTime.utc(2026, 9, 23, 8), true, '0.10.0', problem);

  testWidgets('لا ملفات بلا سجلّ ⟵ لا بطاقة (الشاشة كما كانت)', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('unrecorded-card')), findsNothing);
  });

  testWidgets('ملفاتٌ بلا سجلّ ⟵ بطاقةٌ بالعدد والحجم الكليّ · والتالف لا يُعاد', (tester) async {
    await pump(tester, files: [file('backup-20260923-114718.zip'), file('backup-20260924-172426.zip', problem: 'أرشيفٌ تالف لا يُقرأ — لا يُستعاد.', mb: 1)]);
    expect(find.byKey(const Key('unrecorded-card')), findsOneWidget);
    expect(find.textContaining('لا يعرفها النظام — 2 (341.0 MB)'), findsOneWidget);
    expect(find.text('أرشيفٌ تالف لا يُقرأ — لا يُستعاد.'), findsOneWidget);
    final adoptBroken = tester.widget<TextButton>(find.byKey(const ValueKey('unrecorded-adopt-backup-20260924-172426.zip')));
    expect(adoptBroken.onPressed, isNull, reason: 'أرشيفٌ لا يُستعاد لا يُعاد إلى القائمة');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«إعادة إلى القائمة» تنادي الخادم ثم تعيد القراءة — فتختفي البطاقة', (tester) async {
    await pump(tester, files: [file('backup-20260923-114718.zip')]);
    await tester.tap(find.byKey(const ValueKey('unrecorded-adopt-backup-20260923-114718.zip')));
    await tester.pumpAndSettle();
    expect(api.adopted, ['backup-20260923-114718.zip']);
    expect(find.byKey(const Key('unrecorded-card')), findsNothing);
    expect(find.textContaining('أُعيدت «backup-20260923-114718.zip» إلى القائمة'), findsOneWidget);
  });

  testWidgets('«حذف» يسأل أوّلاً — والإلغاء لا يحذف شيئاً · والتأكيد يحذف', (tester) async {
    await pump(tester, files: [file('backup-20260923-114718.zip')]);
    await tester.tap(find.byKey(const ValueKey('unrecorded-delete-backup-20260923-114718.zip')));
    await tester.pumpAndSettle();
    expect(find.textContaining('أعِده إلى القائمة بدل حذفه'), findsOneWidget, reason: 'التنبيه أنها قد تكون نسخةً حقيقية');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);

    await tester.tap(find.byKey(const ValueKey('unrecorded-delete-backup-20260923-114718.zip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unrecorded-delete-ok')));
    await tester.pumpAndSettle();
    expect(api.deleted, ['backup-20260923-114718.zip']);
    expect(find.byKey(const Key('unrecorded-card')), findsNothing);
  });

  testWidgets('خادمٌ أقدم بلا النقطة ⟵ الشاشة تعمل والبطاقة غائبة', (tester) async {
    tester.view.physicalSize = const Size(1300, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api([], failList: true)),
        backupCoverageProvider.overrideWith((ref) async => BackupCoverage(urgency: 'Ok', message: 'محميّة', maxAgeDays: 30)),
      ],
      child: const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen()))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unrecorded-card')), findsNothing);
    expect(find.byKey(const Key('backup-run-now')), findsOneWidget);
    expect(find.textContaining('404'), findsNothing, reason: 'خطؤها لا يُعرض رسالةً');
  });

  testWidgets('لا تفيض على هاتف', (tester) async {
    await pump(tester, files: [file('backup-20260923-114718.zip'), file('uploaded-20260925-173946.zip')], width: 380);
    expect(tester.takeException(), isNull);
  });
}

class _Api extends ApiClient {
  _Api(this.files, {this.failList = false}) : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));
  List<UnrecordedBackupModel> files;
  final bool failList;
  final adopted = <String>[];
  final deleted = <String>[];

  @override
  Future<BackupScheduleModel> backupSchedule() async => BackupScheduleModel('Off', false, 2, null, null);

  @override
  Future<List<BackupRecordModel>> backupList() async =>
      [BackupRecordModel(1, DateTime(2026, 10, 5), 'backup-20261005-153145.zip', 1048576, 'Manual', 'Full', 'Manual', 'Success', null)];

  @override
  Future<JobInfo?> currentJob() async => null;

  @override
  Future<List<UnrecordedBackupModel>> backupUnrecorded() async {
    if (failList) throw ApiException(404, 'غير موجود');
    return files;
  }

  @override
  Future<void> backupAdoptUnrecorded(String fileName) async {
    adopted.add(fileName);
    files = files.where((f) => f.fileName != fileName).toList();
  }

  @override
  Future<void> backupDeleteUnrecorded(String fileName) async {
    deleted.add(fileName);
    files = files.where((f) => f.fileName != fileName).toList();
  }
}
