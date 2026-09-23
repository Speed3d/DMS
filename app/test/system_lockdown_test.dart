import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/core/system_status.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/system_shell.dart';

/// حرّاس إيقاف النظام وشريط الإعلان (ADR-050).
///
/// 🔴 **أهمُّها أن فشل التجديد لأن الخادم غائب لا يُخرج المستخدم** — كان كلُّ فشلٍ في
/// التجديد يعني «الجلسة انتهت»، فإعادةُ تشغيل السيرفر لحظةَ انتهاء الرمز كانت تُغلق كلَّ
/// ما على الشاشة. هذا ما رآه المالك في التطوير ووصفه «البرنامج يتوقّف ولا يحفظ شيئاً».
void main() {
  // ───────────────────────── القرارات النقيّة ─────────────────────────
  group('قرار فشل التجديد', () {
    test('غيابُ الردّ و5xx عابرةٌ — لا خروج', () {
      for (final s in [null, 500, 502, 503, 524, 530]) {
        expect(ApiClient.refreshFailureIsTransient(s), isTrue, reason: '$s');
      }
    });
    test('4xx رفضٌ صريح — الجلسة انتهت', () {
      for (final s in [400, 401, 403, 404]) {
        expect(ApiClient.refreshFailureIsTransient(s), isFalse, reason: '$s');
      }
    });
  });

  group('ردٌّ من الوسيط لا من خادمنا', () {
    test('502/504 ورموز Cloudflare انقطاع', () {
      for (final s in [502, 504, 520, 522, 524, 530]) {
        expect(ApiClient.isGatewayUnreachable(s, '<html>'), isTrue, reason: '$s');
      }
    });
    test('5xx بجسمٍ منّا ليس انقطاعاً', () {
      expect(ApiClient.isGatewayUnreachable(503, {'error': 'صيانة', 'maintenance': true}), isFalse);
      expect(ApiClient.isGatewayUnreachable(500, {'error': 'خطأ'}), isFalse);
      expect(ApiClient.isGatewayUnreachable(500, '<html>'), isTrue);
    });
    test('نجاحٌ أو 4xx ليس انقطاعاً', () {
      for (final s in [null, 200, 400, 404]) {
        expect(ApiClient.isGatewayUnreachable(s, null), isFalse, reason: '$s');
      }
    });
  });

  group('الطور ومَن يُحجب', () {
    SystemStatusInfo st({bool m = false, bool l = false}) =>
        SystemStatusInfo(maintenance: m, lockdown: LockdownInfo(active: l));

    test('الطور من ردّ الخادم', () {
      expect(phaseOf(st()), SystemPhase.ok);
      expect(phaseOf(st(l: true)), SystemPhase.lockdown);
      expect(phaseOf(st(m: true, l: true)), SystemPhase.restoring, reason: 'الاستعادة تغلب');
    });

    test('الإيقاف يحجب المستخدم المسجَّل عدا السوبر أدمن', () {
      const v = SystemView(phase: SystemPhase.lockdown);
      expect(blocksUser(v, loggedIn: true, isSuperAdmin: false), isTrue);
      expect(blocksUser(v, loggedIn: true, isSuperAdmin: true), isFalse);
      // شاشة الدخول تعرض الرسالة بنفسها ورابط «دخول المسؤول» — فلا تُغطّى.
      expect(blocksUser(v, loggedIn: false, isSuperAdmin: false), isFalse);
    });

    test('الاستعادة والانقطاع يحجبان الجميع — والسوبر أدمن معهم', () {
      for (final p in [SystemPhase.restoring, SystemPhase.unreachable]) {
        final v = SystemView(phase: p);
        expect(blocksUser(v, loggedIn: true, isSuperAdmin: true), isTrue, reason: '$p');
        expect(blocksUser(v, loggedIn: false, isSuperAdmin: false), isTrue, reason: '$p');
      }
    });
  });

  group('إعادة تحميل الصفحة بعد تحديث الواجهة', () {
    test('تُعاد فقط حين يختلف الرقم المنشور', () {
      expect(shouldReload('202609231800', '202609241200'), isTrue);
      expect(shouldReload('202609231800', '202609231800'), isFalse);
    });
    test('لا شيء بلا رقم بناء (التطوير) أو بلا version.json', () {
      expect(shouldReload('', '202609241200'), isFalse);
      expect(shouldReload('202609231800', null), isFalse);
      expect(shouldReload('202609231800', ''), isFalse);
    });
    test('reloadIfNewBuild تنادي reload مرّةً عند الاختلاف وحده', () async {
      var reloads = 0;
      await reloadIfNewBuild(current: 'a', fetch: () async => 'b', reload: () => reloads++);
      await reloadIfNewBuild(current: 'a', fetch: () async => 'a', reload: () => reloads++);
      await reloadIfNewBuild(current: '', fetch: () async => 'b', reload: () => reloads++);
      expect(reloads, 1);
    });
  });

  test('المدّة بالعربية', () {
    expect(arabicDuration(const Duration(seconds: 30)), 'أقل من دقيقة');
    expect(arabicDuration(const Duration(minutes: 1)), 'دقيقة');
    expect(arabicDuration(const Duration(minutes: 2)), 'دقيقتين');
    expect(arabicDuration(const Duration(minutes: 5)), '5 دقائق');
    expect(arabicDuration(const Duration(minutes: 45)), '45 دقيقة');
    expect(arabicDuration(const Duration(hours: 1, minutes: 20)), 'ساعة و20 دقيقة');
    expect(arabicDuration(const Duration(hours: 3)), '3 ساعات');
    expect(arabicDuration(const Duration(days: 2, hours: 2, minutes: 9)), 'يومين وساعتين');
  });

  test('نماذج الحالة تُقرأ من ردّ الخادم الحقيقي', () {
    // ⚠️ ردٌّ مُلتقَطٌ من الخادم حرفياً (2026-09-23) — لا نصٌّ من فهمي للعقد.
    const raw = '{"maintenance":false,"reason":null,"since":null,'
        '"lockdown":{"active":true,"message":"اختبار إعادة التشغيل","since":"2026-09-23T14:33:38.6334909Z","byName":null},'
        '"announcement":{"visible":true,"text":"سيُحدَّث النظام","kind":"Warning","updatedAt":"2026-09-23T14:30:00"}}';
    final s = SystemStatusInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(s.lockdown.active, isTrue);
    expect(s.lockdown.message, 'اختبار إعادة التشغيل');
    expect(s.lockdown.since!.isUtc, isTrue);
    expect(s.announcement.kind, AnnouncementKind.warning);
    expect(s.announcement.shows, isTrue);
    expect(s.announcement.updatedAt!.hour, 14, reason: 'بلا Z = UTC (parseInstant)');
  });

  // ───────────────────────── الطبقة والشريطان ─────────────────────────
  group('SystemShell', () {
    SessionState session(String role) => SessionState(
          loaded: true,
          activeCompanyId: 1,
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

    Future<void> pump(WidgetTester tester, {required SystemView view, SessionState? s, Widget? child}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          systemStatusProvider.overrideWith(() => _FixedStatus(view)),
          sessionProvider.overrideWith(() => _FixedSession(s ?? const SessionState(loaded: true))),
        ],
        child: MaterialApp(
          home: const Scaffold(body: SizedBox()),
          builder: (c, ch) => Directionality(
              textDirection: TextDirection.rtl,
              child: SystemShell(child: child ?? ch!)),
        ),
      ));
      await tester.pump();
    }

    const locked = SystemView(
      phase: SystemPhase.lockdown,
      lockdown: LockdownInfo(active: true, message: 'نعود خلال نصف ساعة'),
    );

    testWidgets('الموظف: الطبقة برسالة المالك — والنموذج تحتها يحتفظ بما كُتب', (tester) async {
      final ctrl = TextEditingController(text: 'كتابٌ لم يُحفظ بعد');
      await pump(tester,
          view: locked,
          s: session('Employee'),
          child: Scaffold(body: TextField(controller: ctrl)));

      expect(find.byType(MaintenanceOverlay), findsOneWidget);
      expect(find.text('نعود خلال نصف ساعة'), findsOneWidget);
      // 🔴 الشاشة تحت الطبقة لم تُهدم — النصّ في مكانه.
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
      expect(ctrl.text, 'كتابٌ لم يُحفظ بعد');
      expect(find.byType(LockdownReminderBar), findsNothing, reason: 'التذكير للسوبر أدمن وحده');
    });

    testWidgets('السوبر أدمن: بلا طبقة — وتذكيرٌ أحمر بزرّ التشغيل', (tester) async {
      await pump(tester,
          view: SystemView(
            phase: SystemPhase.lockdown,
            lockdown: LockdownInfo(
                active: true, message: 'x', since: DateTime.now().toUtc().subtract(const Duration(hours: 1, minutes: 20))),
          ),
          s: session('SuperAdmin'));
      expect(find.byType(MaintenanceOverlay), findsNothing);
      expect(find.byType(LockdownReminderBar), findsOneWidget);
      expect(find.textContaining('منذ ساعة و20 دقيقة'), findsOneWidget);
      expect(find.text('تشغيل الآن'), findsOneWidget);
    });

    testWidgets('غير المسجَّل أثناء الإيقاف: لا طبقة (شاشة الدخول تتولّى)', (tester) async {
      await pump(tester, view: locked);
      expect(find.byType(MaintenanceOverlay), findsNothing);
    });

    testWidgets('الانقطاع: طبقةٌ بزرّ إعادة المحاولة — حتى للسوبر أدمن', (tester) async {
      await pump(tester, view: const SystemView(phase: SystemPhase.unreachable), s: session('SuperAdmin'));
      expect(find.text('تعذّر الوصول إلى الخادم'), findsOneWidget);
      expect(find.text('إعادة المحاولة الآن'), findsOneWidget);
    });

    testWidgets('الشريط: يظهر للمسجَّل بنصّه — بلا زرّ إغلاق', (tester) async {
      await pump(tester,
          view: const SystemView(
              announcement: AnnouncementInfo(visible: true, text: 'اجتماعٌ الساعة 10', kind: AnnouncementKind.warning)),
          s: session('Employee'));
      expect(find.byType(AnnouncementBar), findsOneWidget);
      expect(find.text('اجتماعٌ الساعة 10'), findsOneWidget);
      expect(find.descendant(of: find.byType(AnnouncementBar), matching: find.byIcon(Icons.close)), findsNothing);
    });

    testWidgets('الشريط: لا يظهر مخفيّاً ولا لغير المسجَّل', (tester) async {
      await pump(tester,
          view: const SystemView(announcement: AnnouncementInfo(visible: false, text: 'قديم')),
          s: session('Employee'));
      expect(find.byType(AnnouncementBar), findsNothing);

      await pump(tester, view: const SystemView(announcement: AnnouncementInfo(visible: true, text: 'نص')));
      expect(find.byType(AnnouncementBar), findsNothing);
    });

    testWidgets('لونا الشريط مقروءان نهاراً وليلاً', (tester) async {
      for (final brightness in Brightness.values) {
        for (final kind in AnnouncementKind.values) {
          late ({Color bg, Color fg, IconData icon}) s;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Builder(builder: (c) {
              s = announcementStyle(c, kind);
              return const SizedBox();
            }),
          ));
          final ratio = _contrast(s.bg, s.fg);
          expect(ratio, greaterThanOrEqualTo(3.0), reason: '$brightness · $kind = ${ratio.toStringAsFixed(2)}');
        }
      }
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

class _FixedStatus extends SystemStatusNotifier {
  _FixedStatus(this._v);
  final SystemView _v;
  @override
  SystemView build() => _v;
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}
