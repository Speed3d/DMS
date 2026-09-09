import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/company_providers.dart';
import 'package:dms_app/core/notification_providers.dart';
import 'package:dms_app/core/incoming_providers.dart';
import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/core/profile_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/backup_alert.dart';
import 'package:dms_app/widgets/sidebar.dart';
import 'package:dms_app/widgets/topbar.dart';

/// حرّاس **تنبيه تأخّر النسخة الاحتياطية** (طلب المالك 2026-09-09).
///
/// 🔴 **لماذا؟** النسخة الكاملة **يدوية بقرار المالك**، والمجدولة لا تحمي المرفقات —
/// فلو نُسيت شهرين ثم تعطّل القرص ضاعت مرفقات شهرين، **بينما النسخ اليومية تعمل بانتظام
/// فتُعطي شعوراً زائفاً بالأمان**. وكان التذكير محبوساً في شاشة النسخ وحدها —
/// **والتذكير الذي لا يُرى ليس تذكيراً**.
void main() {
  SessionState session({required String role}) => SessionState(
        loaded: true,
        activeCompanyId: 1,
        auth: AuthResult(
          accessToken: 't',
          accessExpires: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'r',
          userId: 1,
          fullName: 'مستخدم اختبار',
          username: 'tester',
          role: role,
          companyIds: const [1],
          mustChangePassword: false,
          companies: [CompanyAccess(companyId: 1, modules: const ['Backup'])],
        ),
      );

  BackupCoverage coverage(String urgency, {int? days}) => BackupCoverage(
        urgency: urgency,
        message: 'مضى $days يوماً على آخر نسخة كاملة.',
        maxAgeDays: 30,
        daysSince: days,
      );

  // ⚠️ **لا يُتجاوز `backupCoverageProvider` نفسه**: تجاوزُه يقفز فوق حارس الدور الذي
  //    نريد اختباره. يُتجاوز **العميل** ويُترك المزوّد يعمل — فيُثبَت الحجب **وعدم الطلب**.
  Future<_CountingApi> pumpTopbar(
    WidgetTester tester, {
    required String role,
    required BackupCoverage cov,
  }) async {
    final api = _CountingApi(cov);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FixedSession(session(role: role))),
        apiClientProvider.overrideWithValue(api),
        // ⚠️ **يُعزَل الجرس والصورة**: الجرس يستقصي الخادم كل ٦٠ ثانية، والصورة تُجلب —
        //    وبلا عزلهما يبقى مؤقّتُ الشبكة معلّقاً فيفشل الاختبار **بلا عيبٍ في الشاشة**
        //    (درسٌ مسجَّل من الدفعة ٥).
        unreadNotificationsProvider.overrideWith((ref) => Stream.value(0)),
        myPhotoProvider.overrideWith((ref) async => null),
        pendingDraftsProvider.overrideWith((ref) async => <OutgoingListItem>[]),
        pendingIncomingProvider.overrideWith((ref) async => <IncomingListItem>[]),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 1400,
              child: Topbar(
                title: 'الرئيسية',
                subtitle: 'وصف',
                onMenuTap: () {},
                onProfileTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return api;
  }

  Future<void> pumpSidebar(
    WidgetTester tester, {
    required String role,
    required BackupCoverage cov,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FixedSession(session(role: role))),
        apiClientProvider.overrideWithValue(_CountingApi(cov)),
        // ⚠️ صدرُ القائمة صار يقرأ الشركة الفعّالة — ويُعزَل هنا لأن موضوع الاختبار
        //    الشارةُ لا الصدر، وبلا عزلٍ يبقى طلبُ الشركات معلّقاً («Pending timers»).
        activeCompanyProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              height: 900,
              child: Sidebar(
                selectedIndex: 0,
                onSelected: (_) {},
                canManageUsers: true,
                isSuperAdmin: role == 'SuperAdmin',
                modules: const ['Backup'],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  group('🗄️ أيقونة الشريط العلوي', () {
    testWidgets('🔴 تظهر عند التأخّر وتحمل عدد الأيام', (tester) async {
      await pumpTopbar(tester, role: 'SuperAdmin', cov: coverage('Overdue', days: 42));

      expect(find.byType(BackupAlertIcon), findsOneWidget);
      // «مضى 42 يوماً» يُقرأ فوراً — و«تحذير» وحده يحتاج ضغطةً ليُعرف مداه.
      expect(find.text('42 يوم'), findsOneWidget);
    });

    testWidgets('🔴 وتغيب تماماً حين لا تأخّر — لا أيقونةَ دائمة', (tester) async {
      // أيقونةٌ دائمة تصير جزءاً من الأثاث فلا تُرى حين تلزم.
      await pumpTopbar(tester, role: 'SuperAdmin', cov: coverage('Ok', days: 3));

      expect(find.byType(BackupAlertIcon), findsOneWidget); // الغلاف موجود…
      expect(find.textContaining('يوم'), findsNothing); // …ولا يرسم شيئاً
    });

    testWidgets('🔐 وغيرُ السوبر أدمن: لا أيقونة **ولا طلبَ أصلاً**', (tester) async {
      final api = await pumpTopbar(
          tester, role: 'Manager', cov: coverage('Overdue', days: 42));

      expect(find.textContaining('يوم'), findsNothing);
      expect(api.calls, 0,
          reason: 'النقطة مقصورةٌ على السوبر أدمن — وطلبٌ نعلم أنه سيُردّ 403 ضجيجٌ وخطأ');
    });

    testWidgets('🎨 واللون يتصاعد: «قريباً» ليس كـ«متأخّرة»', (tester) async {
      // تنبيهٌ بلونٍ واحد لا يفرّق بين «اقترب الموعد» و«مضى شهران».
      expect(backupUrgencyColor('Soon'), isNot(backupUrgencyColor('Overdue')));
      expect(backupUrgencyColor('Urgent'), isNot(backupUrgencyColor('Overdue')));
      expect(backupUrgencyIcon('Soon'), isNot(backupUrgencyIcon('Overdue')));
    });
  });

  group('🗄️ شارة القائمة الجانبية', () {
    testWidgets('🔴 تحمل عدد الأيام على بند النسخ الاحتياطي', (tester) async {
      await pumpSidebar(tester, role: 'SuperAdmin', cov: coverage('Overdue', days: 42));

      expect(find.text('النسخ الاحتياطي'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('🔴 ولا شارة حين التغطية سليمة', (tester) async {
      await pumpSidebar(tester, role: 'SuperAdmin', cov: coverage('Ok', days: 3));

      expect(find.text('النسخ الاحتياطي'), findsOneWidget);
      expect(find.text('3'), findsNothing,
          reason: 'شارةٌ دائمة تُعمي عن الرقم حين يأتي');
    });

    testWidgets('🔐 وغيرُ السوبر أدمن: لا بندَ أصلاً فلا شارة', (tester) async {
      await pumpSidebar(tester, role: 'Manager', cov: coverage('Overdue', days: 42));

      expect(find.text('النسخ الاحتياطي'), findsNothing);
      expect(find.text('42'), findsNothing);
    });
  });
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

/// عميلٌ يعدّ نداءات التغطية — **العدّ هو الحارس**: الحجب بلا طلبٍ لا يكفي إثباتُه بالغياب
/// وحده، فقد يكون الطلب وقع وأُخفي ردُّه.
class _CountingApi extends ApiClient {
  _CountingApi(this._coverage)
      : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  final BackupCoverage _coverage;
  int calls = 0;

  @override
  Future<BackupCoverage> backupCoverage() async {
    calls++;
    return _coverage;
  }
}
