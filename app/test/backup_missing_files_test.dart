import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/backup_providers.dart';
import 'package:dms_app/core/job_watcher.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/backup_screen.dart';

/// سجلّاتٌ ملفّها مفقود وتنبيه صحّة النسخ (ADR-062) — على جهاز التطوير وُجد سجلّان بلا ملفّ يظهران بعلامة نجاحٍ
/// خضراء، والتنبيه صامتٌ والجدولة متوقّفة وعشرة أيامٍ بلا نسخة.
void main() {
  late _Api api;

  final healthy = BackupRecordModel(7, DateTime(2026, 10, 5), 'backup-20261005-153145.zip', 352321536, 'Manual', 'Full', 'Manual', 'Success', null);
  final missing = BackupRecordModel(5, DateTime(2026, 9, 25), 'backup-20260925-101010.zip', 1048576, 'Manual', 'Full', 'Manual', 'Success', null,
      fileExists: false);

  BackupCoverage coverage({List<String> warnings = const []}) => BackupCoverage(
      urgency: warnings.isEmpty ? 'Ok' : 'Urgent', message: warnings.isEmpty ? 'محميّة' : warnings.first, maxAgeDays: 30,
      daysSince: 9, fullUrgency: 'Ok', warnings: warnings);

  Future<void> pump(WidgetTester tester, {BackupCoverage? cov, double width = 1300}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = _Api([healthy, missing]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        backupCoverageProvider.overrideWith((ref) async => cov ?? coverage()),
      ],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: BackupScreen())),
      ),
    ));
    await tester.pumpAndSettle();
  }

  IconButton button(WidgetTester tester, String tooltip, int index) =>
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).at(index));

  testWidgets('المفقود ملفّه ⟵ «الملف مفقود» · لا تنزيل ولا استعادة · والحذف متاح — والسليم كما هو', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('missing-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('missing-7')), findsNothing);

    expect(button(tester, 'تنزيل', 0).onPressed, isNotNull, reason: 'السليم يُنزَّل');
    expect(button(tester, 'استعادة هذه النسخة', 0).onPressed, isNotNull);
    expect(button(tester, 'الملف مفقود — لا يُنزَّل', 0).onPressed, isNull);
    expect(button(tester, 'الملف مفقود — لا تُستعاد', 0).onPressed, isNull);
    expect(button(tester, 'حذف النسخة', 1).onPressed, isNotNull, reason: 'سجلٌّ بلا ملفٍّ يُحذف');
  });

  testWidgets('حذف المفقود ⟵ التأكيد يقول «السجلّ وحده» · ثم يُحذف', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('حذف النسخة').at(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('سيُحذف سجلّها من القائمة فقط'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(api.deleted, [5]);
    expect(find.byKey(const ValueKey('missing-5')), findsNothing);
  });

  testWidgets('بطاقة التنبيه تعرض كل التنبيهات لا أوّلها', (tester) async {
    await pump(tester, cov: coverage(warnings: [
      '⚠️ لم تُؤخذ أيّ نسخة احتياطية منذ 9 يوماً.',
      'النسخ التلقائي متوقّف — فعّل الجدولة (يومي) من «الجدولة التلقائية» أدناه.',
      '1 من النسخ في القائمة ملفّها مفقودٌ من القرص — لا تُستعاد، واحذف سجلّها.',
    ]));
    expect(find.text('تنبيه النسخ الاحتياطي'), findsOneWidget);
    expect(find.textContaining('منذ 9 يوماً'), findsOneWidget);
    expect(find.textContaining('النسخ التلقائي متوقّف'), findsOneWidget);
    expect(find.textContaining('ملفّها مفقودٌ من القرص'), findsOneWidget);
  });

  testWidgets('لا تفيض على هاتف', (tester) async {
    await pump(tester, width: 380, cov: coverage(warnings: ['النسخ التلقائي متوقّف', 'ملفٌّ مفقود']));
    expect(tester.takeException(), isNull);
  });

  group('النموذج', () {
    test('شارة القائمة: عدد أيام الكاملة حين تكون هي السبب — وإلا «!»', () {
      expect(coverage(warnings: ['متوقّف']).badge, '!', reason: 'الكاملة سليمة والسبب الجدولة');
      final full = BackupCoverage(urgency: 'Overdue', message: 'm', maxAgeDays: 30, daysSince: 42, fullUrgency: 'Overdue');
      expect(full.badge, '42');
      expect(BackupCoverage(urgency: 'Overdue', message: 'm', maxAgeDays: 30).badge, '!', reason: 'لا نسخة قطّ — لا رقم يُختلق');
    });

    test('خادمٌ أقدم بلا الحقول الجديدة ⟵ يبقى صادقاً', () {
      final c = BackupCoverage.fromJson({'urgency': 'Urgent', 'message': 'مضى 28 يوماً', 'maxAgeDays': 30, 'daysSinceFullBackup': 28});
      expect(c.fullUrgency, 'Urgent');
      expect(c.details, 'مضى 28 يوماً');
      expect(c.badge, '28');
      final r = BackupRecordModel.fromJson({'backupRecordId': 1, 'createdAt': '2026-10-05T12:00:00Z', 'status': 'Success'});
      expect(r.fileExists, isTrue, reason: 'لا نُعلن فقداً لم يُقَس');
      expect(r.isUsable, isTrue);
    });

    test('الخادم الجديد ⟵ الحقول تُقرأ', () {
      final c = BackupCoverage.fromJson({
        'urgency': 'Urgent', 'message': 'a', 'maxAgeDays': 30, 'daysSinceFullBackup': 9,
        'fullUrgency': 'Ok', 'scheduleEnabled': false, 'missingFiles': 2, 'warnings': ['a', 'b'],
      });
      expect(c.scheduleEnabled, isFalse);
      expect(c.missingFiles, 2);
      expect(c.details, 'a\nb');
      expect(c.badge, '!');
      final r = BackupRecordModel.fromJson({'backupRecordId': 1, 'createdAt': '2026-10-05T12:00:00Z', 'status': 'Success', 'fileExists': false});
      expect(r.isUsable, isFalse);
    });
  });
}

class _Api extends ApiClient {
  _Api(this.list) : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));
  List<BackupRecordModel> list;
  final deleted = <int>[];

  @override
  Future<BackupScheduleModel> backupSchedule() async => BackupScheduleModel('Off', false, 2, null, null);

  @override
  Future<List<BackupRecordModel>> backupList() async => list;

  @override
  Future<JobInfo?> currentJob() async => null;

  @override
  Future<List<UnrecordedBackupModel>> backupUnrecorded() async => [];

  @override
  Future<void> backupDelete(int id) async {
    deleted.add(id);
    list = list.where((r) => r.id != id).toList();
  }
}
