import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/app_version.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/core/system_status.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/version_tag.dart';

/// رقم إصدار البرنامج (ADR-054).
void main() {
  // ───────────────────── المصدر الواحد ─────────────────────
  test('🔴 pubspec.yaml يطابق ملف VERSION — رقمان لشيءٍ واحد يتباعدان', () {
    // `flutter test` يعمل من مجلد `app`، والملف في جذر المستودع.
    final file = File('../VERSION');
    expect(file.existsSync(), isTrue, reason: 'ملف VERSION غير موجود في جذر المستودع');
    final expected = file.readAsStringSync().trim();

    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final pub = line.substring('version:'.length).trim().split('+').first;
    expect(pub, expected, reason: 'ارفع version في pubspec.yaml إلى $expected');
  });

  // ───────────────────── الدوالّ النقيّة ─────────────────────
  test('نصُّ الإصدار — وفي التطوير «نسخة تطوير»', () {
    expect(appVersionLabel('0.9.0'), 'الإصدار 0.9.0');
    expect(appVersionLabel(''), 'نسخة تطوير');
  });

  test('اختلافُ الإصدارين يُحكم فيه بالطرفين وحدهما', () {
    expect(versionsDiffer('0.9.0', '0.9.1'), isTrue);
    expect(versionsDiffer('0.9.0', '0.9.0'), isFalse);
    expect(versionsDiffer('0.9.0', ' 0.9.0 '), isFalse);
    // ⚠️ **لا حكمَ بلا طرفين**: واجهةُ تطوير بلا رقم، أو خادمٌ لم يُسأل بعد (أو مجهولٌ لا يُكشف له).
    expect(versionsDiffer('', '0.9.0'), isFalse);
    expect(versionsDiffer('0.9.0', null), isFalse);
    expect(versionsDiffer('0.9.0', ''), isFalse);
  });

  test('حالة النظام تقرأ إصدار الخادم — وغيابُه null لا انهيار', () {
    expect(SystemStatusInfo.fromJson({'maintenance': false, 'version': '0.9.0'}).serverVersion, '0.9.0');
    expect(SystemStatusInfo.fromJson({'maintenance': false}).serverVersion, isNull);
  });

  test('«حول النظام»: المهاجرات متأخّرة حين يختلف آخرُ الكود عن آخر المطبَّق', () {
    final ok = SystemAboutInfo.fromJson({'version': '0.9.0', 'latestMigration': 'A', 'appliedMigration': 'A'});
    final behind = SystemAboutInfo.fromJson({'version': '0.9.0', 'latestMigration': 'B', 'appliedMigration': 'A'});
    expect(ok.migrationsUpToDate, isTrue);
    expect(behind.migrationsUpToDate, isFalse);
  });

  // ───────────────────── الودجات ─────────────────────
  group('سطر الإصدار والحوار', () {
    SessionState session(String role) => SessionState(
          loaded: true,
          auth: AuthResult(
            accessToken: 't',
            accessExpires: DateTime.now().add(const Duration(hours: 1)),
            refreshToken: 'r',
            userId: 1,
            fullName: 'مستخدم',
            username: 'u',
            role: role,
            companyIds: const [1],
            mustChangePassword: false,
            companies: [CompanyAccess(companyId: 1, modules: const ['Outgoing'])],
          ),
        );

    Future<void> pump(WidgetTester tester, {required String role, String? server, String ui = '0.9.0'}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FixedSession(session(role))),
          systemStatusProvider.overrideWith(() => _FixedStatus(SystemView(serverVersion: server))),
          apiClientProvider.overrideWithValue(_FakeApi()),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: SizedBox(width: 240, child: VersionTag(uiVersion: ui)))),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('يعرض الإصدار لكل مستخدم', (tester) async {
      await pump(tester, role: 'Employee', server: '0.9.0');
      expect(find.text('الإصدار 0.9.0'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('🔴 السوبر أدمن يُنبَّه إن اختلف الخادم عن الواجهة', (tester) async {
      await pump(tester, role: 'SuperAdmin', server: '0.9.1');
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('وغيرُه لا يُنبَّه — ليس بيده ما يفعله', (tester) async {
      await pump(tester, role: 'Employee', server: '0.9.1');
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('النقر يفتح «حول النظام» بإصدارَي الطرفين وآخر مهاجرة', (tester) async {
      await pump(tester, role: 'SuperAdmin', server: '0.9.0');
      await tester.tap(find.byKey(const Key('version-tag')));
      await tester.pumpAndSettle();
      expect(find.text('حول النظام'), findsWidgets);
      expect(find.textContaining('الإصدار 0.9.0 (abc1234)'), findsOneWidget);
      expect(find.textContaining('31 مهاجرة'), findsOneWidget);
    });
  });
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._s);
  final SessionState _s;
  @override
  SessionState build() => _s;
}

class _FixedStatus extends SystemStatusNotifier {
  _FixedStatus(this._v);
  final SystemView _v;
  @override
  SystemView build() => _v;
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<SystemAboutInfo> systemAbout() async => const SystemAboutInfo(
      version: '0.9.0', commit: 'abc1234', latestMigration: 'M31', appliedMigration: 'M31', migrationCount: 31);
}
