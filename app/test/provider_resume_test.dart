import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/backup_providers.dart';
import 'package:dms_app/core/hr_providers.dart';
import 'package:dms_app/core/incoming_providers.dart';
import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/core/task_providers.dart';
import 'package:dms_app/core/company_providers.dart';
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

  // ⚠️ **`TickerMode` هو نفسُه ما يفعله المسار**: إيقافٌ ثم استئنافٌ داخل طور البناء.
  //    ولا يكفي إعادةُ ضخّ الشجرة نفسها — **الاشتراك يجب أن يُوقَف ثم يُستأنَف فعلاً**،
  //    وأن **يتغيّر مصدرُه وهو موقوف** (درس الدفعة ٥).
  Future<void> pumpAndToggle(WidgetTester tester, ProviderContainer container,
      void Function(WidgetRef ref) watch,
      {SessionState Function()? session, int companyId = 2}) async {
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
          .bump(session != null ? session() : loggedIn(companyId: companyId));
      container.invalidate(myProfileProvider);
      await tester.pump();

      // ③ يُستأنَف **أثناء البناء** — وهنا كانت تُرمى الاستثناء.
      setOuter(() => enabled = true);
      await tester.pump();
      await tester.pumpAndSettle();
  }

  group('🔴 استئنافُ اشتراكٍ موقوف أثناء البناء لا يُسقط الرسم', () {
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


  group('🔴 والمزوّدات المُضافة حديثاً — تنبيه النسخ وصدر القائمة', () {
    // 🔴 **بلاغ المالك 2026-09-09 (الثاني)**: عاد الاستثناء نفسه بعد إضافة تنبيه النسخ
    //    وصدر القائمة. والدرس المسجَّل («غير المتزامن لا يراقب غير المتزامن») **كان
    //    تشخيصاً ناقصاً**: العلّة أوسع — **أيُّ سلسلةِ `watch` بين مزوّدين** تُفلَش أثناء
    //    استئناف اشتراكٍ في طور البناء تُبطل التابع فتُرمى الاستثناء، ولو كان التابع
    //    **متزامناً**. ولهذا يُقاس كلُّ مزوّدٍ جديد بهذا الحارس لا بالنمط وحده.
    SessionState superAdmin() => SessionState(
          loaded: true,
          activeCompanyId: 1,
          auth: AuthResult(
            accessToken: 't',
            accessExpires: DateTime.now().add(const Duration(hours: 1)),
            refreshToken: 'r',
            userId: 1,
            fullName: 'مدير النظام',
            username: 'admin',
            role: 'SuperAdmin',
            companyIds: const [1, 2],
            mustChangePassword: false,
            companies: [
              CompanyAccess(companyId: 1, modules: const ['Backup']),
              CompanyAccess(companyId: 2, modules: const ['Backup']),
            ],
          ),
        );

    for (final entry in <({String name, void Function(WidgetRef) watch})>[
      (name: 'تغطية النسخ', watch: (ref) => ref.watch(backupCoverageProvider)),
      // ⚠️ **الدالّة النقيّة تحلّ محلّ المزوّد المشتقّ** — والحارس يقرؤها كما يقرؤها
      //    القارئان الحقيقيّان: مصدرٌ واحد يُراقَب، والحساب بعده.
      (name: 'تنبيه النسخ (دالّةٌ لا سلسلة)',
          watch: (ref) => backupAlertOf(ref.watch(backupCoverageProvider))),
      (name: 'الشركة الفعّالة', watch: (ref) => ref.watch(activeCompanyProvider)),
      // 🔴 **وبقيّة العائلة**: أربعةُ مشتقّاتٍ بالشكل نفسه تقرؤها شارات القائمة الجانبية —
      //    **حين يُكتشف عيبٌ من عائلة، تُفتَّش بقيّة أفرادها فوراً** (قاعدة مسجَّلة).
      (name: 'شارة الصادر',
          watch: (ref) => outgoingCountOf(ref.watch(pendingDraftsProvider))),
      (name: 'شارة الوارد',
          watch: (ref) => incomingCountOf(ref.watch(pendingIncomingProvider))),
      (name: 'شارة الأشهر غير المسدَّدة',
          watch: (ref) => unpaidMonthsOf(ref.watch(hrSummaryProvider))),
      (name: 'شارة المهام المتأخرة',
          watch: (ref) => overdueTasksCountOf(ref.watch(taskSummaryProvider))),
    ]) {
      testWidgets('${entry.name}: بلا استثناء', (tester) async {
        final container = ProviderContainer(overrides: [
          sessionProvider.overrideWith(() => _MutableSession(superAdmin())),
          apiClientProvider.overrideWithValue(_ShellApi()),
        ]);
        addTearDown(container.dispose);

        await pumpAndToggle(tester, container, entry.watch,
            session: () => superAdmin(), companyId: 2);

        expect(tester.takeException(), isNull,
            reason: 'استئنافُ الاشتراك أثناء البناء أسقط الرسم');
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

  group('🔒 وحارسُ العائلة الثاني — لا مزوّدَ مشتقٌّ يراقب مزوّداً', () {
    // 🔴 **الدرس المسجَّل كان ناقصاً**: كُتب أن العلّة «`await ref.watch(x.future)`»، فبقيت
    //    **خمسةُ مزوّدات مشتقّة** (`Provider` يراقب `FutureProvider`) تُسقط الرسم بالطريقة
    //    نفسها — أربعُ شارات في القائمة الجانبية وتنبيهُ النسخ. **وأُثبت ذلك بالقياس**:
    //    أُعيد أحدها مؤقّتاً فأخفق الحارس، ثم أُزيل فمرّ.
    //
    // ✅ **والقاعدة الصحيحة: لا سلسلةَ `watch` بين مزوّدين** — يقرأ القارئُ المصدرَ
    //    مباشرةً ويحسب بدالّةٍ نقيّة (`outgoingCountOf` · `backupAlertOf` …).
    test('لا `Provider(... ref.watch(...))` في ملفّات المزوّدات', () {
      final offenders = <String>[];
      for (final f in Directory('lib/core').listSync().whereType<File>()) {
        if (!f.path.endsWith('_providers.dart')) continue;
        final lines = f.readAsStringSync().split(String.fromCharCode(10));
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          // مزوّدٌ **متزامن**: `= Provider<` أو `= Provider.autoDispose<` — ولا يُحسب
          // `FutureProvider`/`StreamProvider`/`NotifierProvider` فهي مصادر لا مشتقّات.
          final isSync = (l.contains('= Provider<') || l.contains('= Provider.autoDispose<')) &&
              !l.contains('FutureProvider') &&
              !l.contains('StreamProvider') &&
              !l.contains('NotifierProvider');
          if (!isSync) continue;
          // جسمُه: حتى أوّل سطرٍ ينتهي بـ`});` أو `);`
          final to = i + 12 > lines.length ? lines.length : i + 12;
          final body = lines.sublist(i, to).join(String.fromCharCode(10));
          final upToEnd = body.contains(');') ? body.substring(0, body.indexOf(');')) : body;
          if (upToEnd.contains('ref.watch(')) offenders.add('${f.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'مزوّدٌ مشتقٌّ يراقب مزوّداً يُبطل نفسه أثناء استئناف اشتراكٍ في طور '
              'البناء — استعمل دالّةً نقيّة يناديها القارئ');
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

/// عميلٌ يخدم مزوّدات القشرة — تغطيةَ النسخ وقائمةَ الشركات.
class _ShellApi extends ApiClient {
  _ShellApi()
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<BackupCoverage> backupCoverage() async => BackupCoverage(
        urgency: 'Overdue',
        message: 'مضى 42 يوماً على آخر نسخة كاملة.',
        maxAgeDays: 30,
        daysSince: 42,
      );

  @override
  Future<List<Company>> companies() async => [];

  // ⚠️ **الأربعةُ الباقية إلزامية**: أوّلَ مرّةٍ نقصت، فذهب الطلب إلى شبكةٍ حقيقية وأخفق —
  //    **فبدت الشارات الأربعُ معطوبةً وهي سليمة**. خامسُ تكرارٍ لدرس «قبل تصديق فشلٍ،
  //    تحقّق من الأداة»، وهذه المرّة كاد يدفعني إلى «إصلاح» ما ليس معطوباً.
  @override
  Future<List<OutgoingListItem>> outgoingList({String? status, String? search}) async => const [];

  @override
  Future<List<IncomingListItem>> incomingList({
    String? search, String? status, int? entityId,
    DateTime? from, DateTime? to, int? documentTypeId,
    int? departmentId, int? receiveMethod,
  }) async => const [];

  @override
  Future<HrSummary> hrSummary() async => HrSummary(7, 5000000, 60000000, 2, 3);

  @override
  Future<TaskSummaryModel> taskSummary() async => TaskSummaryModel.zero;
}