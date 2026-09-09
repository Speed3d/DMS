import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/profile_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';

/// حرّاس **استئناف الاشتراكات الموقوفة** — علّةٌ ظهرت أربع مرّات.
///
/// 🔴 **العلّة:** `await ref.watch(x.future)` يُنشئ `ProxyProviderListenable`. وحين يُستأنَف
/// اشتراكٌ موقوف **أثناء طور البناء** — ويقع ذلك مع كل تبدّل `TickerMode` لعنصر Overlay:
/// انتقالُ مسار، فتحُ حوار، إقلاعُ التطبيق — **يُبطل المزوّد نفسه** فتُرمى
/// «setState() or markNeedsBuild() called during build» **ويتوقّف الرسم**.
///
/// ظهرت في: شارتَي الشريط الجانبي (الصادر والوارد) · ملخّص الرواتب · **ومزوّدات البروفايل**
/// (بلاغ المالك 2026-09-09 — الشريط العلوي يقرأ الصورة في كل شاشة، فسقط عند فتح المسارات).
void main() {
  SessionState loggedIn({int companyId = 1}) => SessionState(
        loaded: true,
        activeCompanyId: companyId,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مستخدم اختبار',
          username: 'tester',
          role: 'Employee',
          companyIds: const [1, 2],
          mustChangePassword: false,
          companies: [
            CompanyAccess(companyId: 1, modules: const ['Tasks']),
            CompanyAccess(companyId: 2, modules: const ['Tasks']),
          ],
        ),
      );

  group('🔴 استئنافُ اشتراكٍ موقوف أثناء البناء لا يُسقط الرسم', () {
    // ⚠️ **`TickerMode` هو نفسُه ما يفعله المسار**: إيقافٌ ثم استئنافٌ داخل طور البناء.
    //    ولا يكفي إعادةُ ضخّ الشجرة نفسها — **الاشتراك يجب أن يُوقَف ثم يُستأنَف فعلاً**،
    //    وأن **يتغيّر مصدرُه وهو موقوف** (درس الدفعة ٥).
    Future<void> pumpAndToggle(WidgetTester tester, ProviderContainer container,
        void Function(WidgetRef ref) watch) async {
      var enabled = true;
      late StateSetter setOuter;

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return TickerMode(
              enabled: enabled,
              child: Consumer(builder: (context, ref, _) {
                watch(ref);
                return const SizedBox.shrink();
              }),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();

      // ① يُوقَف الاشتراك.
      setOuter(() => enabled = false);
      await tester.pump();

      // ② يتغيّر المصدر **وهو موقوف** — الجلسةُ (تبديلُ شركة) والبروفايلُ معاً، فأيُّهما
      //    كان مصدرَ المزوّد يتّسخ الآن.
      (container.read(sessionProvider.notifier) as _MutableSession)
          .bump(loggedIn(companyId: 2));
      container.invalidate(myProfileProvider);
      await tester.pump();

      // ③ يُستأنَف **أثناء البناء** — وهنا كانت تُرمى الاستثناء.
      setOuter(() => enabled = true);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    for (final entry in <({String name, void Function(WidgetRef) watch})>[
      (name: 'صورتي (الشريط العلوي)', watch: (ref) => ref.watch(myPhotoProvider)),
      (name: 'إجازاتي', watch: (ref) => ref.watch(myLeavesProvider)),
      (name: 'رواتبي', watch: (ref) => ref.watch(myPayslipsProvider)),
    ]) {
      testWidgets('${entry.name}: بلا استثناء', (tester) async {
        final container = ProviderContainer(overrides: [
          sessionProvider.overrideWith(() => _MutableSession(loggedIn())),
          apiClientProvider.overrideWithValue(_ProfileApi()),
        ]);
        addTearDown(container.dispose);

        await pumpAndToggle(tester, container, entry.watch);

        expect(tester.takeException(), isNull,
            reason: 'استئنافُ الاشتراك أثناء البناء أسقط الرسم — عادت علّة `.future`');
      });
    }
  });

  group('🔒 حارس العائلة — النمط لا يعود من بابٍ آخر', () {
    // 🔴 **حين يُكتشف عيبٌ من عائلة، تُفتَّش بقيّة أفرادها فوراً** (قاعدة مسجَّلة).
    //    وهذا الحارس يمنع **الظهور الخامس**: لا يمرّ `await ref.watch(x.future)` في المزوّدات.
    test('لا `await ref.watch(...future)` في أيّ ملفّ مزوّدات', () {
      final offenders = <String>[];
      final dir = Directory('lib');

      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        // يُتجاهل ذكرُ النمط داخل التعليقات التحذيرية نفسها.
        for (final line in src.split('\n')) {
          final code = line.trimLeft();
          if (code.startsWith('//') || code.startsWith('///')) continue;
          if (RegExp(r'ref\.watch\([^)]*\.future\)').hasMatch(code)) {
            offenders.add('${f.path}: ${code.trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'انتظارُ `.future` يُبطل المزوّد أثناء البناء — اشتقّ من `AsyncValue` '
              'أو انتظِر بـ`Completer` كما في `profile_providers._profileOrWait`');
    });
  });
}

/// جلسةٌ **قابلة للتغيير** — لأن الحارس يحتاج أن يتغيّر المصدر فعلاً وهو موقوف،
/// وجلسةٌ ثابتة تجعل الحارس يمرّ بلا أن يقيس شيئاً.
class _MutableSession extends SessionNotifier {
  _MutableSession(this._initial);
  final SessionState _initial;
  @override
  SessionState build() => _initial;
  void bump(SessionState next) => state = next;
}

/// عميلٌ يردّ ببروفايلٍ مربوطٍ بصورة — بلا شبكة ولا مؤقّتات.
class _ProfileApi extends ApiClient {
  _ProfileApi()
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<MyProfile> myProfile() async => MyProfile(
        userId: 1,
        fullName: 'مستخدم اختبار',
        username: 'tester',
        role: 'Employee',
        employeeId: 7,
        hasPhoto: true,
      );

  @override
  Future<Uint8List> myPhoto() async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<List<LeaveModel>> myLeaves() async => const [];

  @override
  Future<List<MyPayslip>> myPayslips({int? year}) async => const [];
}
