import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/profile_screen.dart';

/// حرّاس البروفايل الشخصي (ADR-033).
///
/// 🔴 **ما تحرسه هذه الاختبارات ليس «هل تُبنى الشاشة» بل ثلاث قواعد يكلّف خرقُها مالاً:**
/// 1. **من لا بطاقةَ له لا يرى تبويبَي الإجازات والرواتب** — ولا يُترك بلا تفسير.
/// 2. **نموذج الطلب لا يعرض «تحتاج موافقة» ولا «تُحسم من الراتب»** — عرضُهما يوهم الموظف
///    أنه يملك ما لا يملك، وإرسالُهما يمنحه إجازةً مقبولةً بلا حسم.
/// 3. **الشهر الذي صرفته شركةٌ أخرى لا زرَّ إيصالٍ له** — الإيصال إقرارُ استلامٍ من هذه
///    الشركة، وطبعُه يشهد بما لم يقع هنا (ADR-028).
void main() {
  // ══════════════════ قراءة النماذج ══════════════════

  group('نماذج البروفايل — العقد كما يرسله الخادم', () {
    test('MyProfile: مربوطٌ ببطاقة ⇒ التبويبتان تظهران', () {
      final p = MyProfile.fromJson(const {
        'userId': 7,
        'fullName': 'سنان أياد',
        'username': 'sinan',
        'role': 'Employee',
        'companyName': 'أرض العرين',
        'departmentName': 'المالية',
        'employeeId': 12,
        'employeeFullName': 'سنان أياد محمد',
        'position': 'محاسب',
        'hireDate': '2024-03-01',
        'hasPhoto': true,
      });
      expect(p.isLinkedToEmployee, isTrue);
      expect(p.position, 'محاسب');
      // ⚠️ `hireDate` **تاريخٌ تقويميّ**: يبقى اليوم الأول من آذار ولا يُزحزحه تحويلُ منطقة.
      expect(p.hireDate!.year, 2024);
      expect(p.hireDate!.month, 3);
      expect(p.hireDate!.day, 1);
    });

    test('🔴 MyProfile: بلا بطاقة ⇒ التبويبتان تُخفيان', () {
      final p = MyProfile.fromJson(const {
        'userId': 1,
        'fullName': 'مدير النظام',
        'username': 'admin',
        'role': 'SuperAdmin',
      });
      expect(p.isLinkedToEmployee, isFalse);
      expect(p.employeeId, isNull);
    });

    /// 🔴 **عائلة عطل الوقت (ADR-032) — وقد تبيّن أنها أوسع مما عولج.**
    ///
    /// `models_hr.dart` لم يُمسّ في تلك الدفعة أصلاً، فبقيت حقولُه اللحظيّة تُقرأ محليّاً
    /// وتُعرض متأخّرةً ثلاث ساعات. الخادم يرسل بلا `Z` والقيمة UTC.
    test('🔴 MyPayslip: `paidAt` لحظةٌ تُقرأ UTC ولو وصلت بلا `Z`', () {
      final withoutZ = MyPayslip.fromJson(const {
        'periodId': 3,
        'year': 2026,
        'month': 7,
        'monthLabel': 'تموز',
        'netSalaryIqd': 1250000,
        'paymentStatus': 'PaidByThisCompany',
        'paymentStatusLabel': 'مصروف',
        'paidAt': '2026-08-11T21:31:00.846',
      });
      final withZ = MyPayslip.fromJson(const {
        'periodId': 3,
        'year': 2026,
        'month': 7,
        'monthLabel': 'تموز',
        'netSalaryIqd': 1250000,
        'paymentStatus': 'PaidByThisCompany',
        'paymentStatusLabel': 'مصروف',
        'paidAt': '2026-08-11T21:31:00.846Z',
      });
      expect(withoutZ.paidAt!.toUtc(), withZ.paidAt!.toUtc(),
          reason: 'النصّ بلا منطقةٍ من خادمنا **UTC** — وقراءتُه محليّاً تُقدّم الساعة ثلاثاً');
      expect(withoutZ.paidAt!.isUtc, isTrue);
    });

    test('MyPayslip: `paidAt` غائبة ⇒ null لا الآن', () {
      final s = MyPayslip.fromJson(const {
        'periodId': 1, 'year': 2026, 'month': 1, 'monthLabel': 'كانون الثاني',
        'paymentStatus': 'Unpaid', 'paymentStatusLabel': 'غير مصروف',
      });
      expect(s.paidAt, isNull);
    });

    test('🔴 MyPayslip: «صُرف من شركة أخرى» يُعرَف — فلا إيصال له من هنا', () {
      final other = MyPayslip.fromJson(const {
        'periodId': 4, 'year': 2026, 'month': 6, 'monthLabel': 'حزيران',
        'paymentStatus': 'PaidByOtherCompany', 'paymentStatusLabel': 'مصروف من شركة أخرى',
      });
      final here = MyPayslip.fromJson(const {
        'periodId': 5, 'year': 2026, 'month': 5, 'monthLabel': 'أيار',
        'paymentStatus': 'PaidByThisCompany', 'paymentStatusLabel': 'مصروف',
      });
      expect(other.paidByOtherCompany, isTrue);
      expect(here.paidByOtherCompany, isFalse);
    });

    test('LeaveModel: `isSelfRequested` يصل — والقديم بلا الحقل يبقى `false`', () {
      final self = LeaveModel.fromJson(const {
        'leaveId': 1, 'leaveType': 'Annual', 'leaveTypeLabel': 'اعتيادية',
        'fromDate': '2026-08-01', 'toDate': '2026-08-05', 'durationDays': 5,
        'requiresApproval': true, 'status': 'Pending', 'deductFromSalary': false,
        'createdAt': '2026-08-01T09:00:00', 'isSelfRequested': true,
      });
      final byHr = LeaveModel.fromJson(const {
        'leaveId': 2, 'leaveType': 'Sick', 'leaveTypeLabel': 'مرضية',
        'fromDate': '2026-08-10', 'toDate': '2026-08-11', 'durationDays': 2,
        'requiresApproval': false, 'status': 'Approved', 'deductFromSalary': true,
        'createdAt': '2026-08-10T09:00:00',
      });
      expect(self.isSelfRequested, isTrue);
      expect(byHr.isSelfRequested, isFalse);
    });

    test('EmployeeDetail: الحساب المربوط يصل — والبطاقة تعرف أنها مربوطة', () {
      final linked = EmployeeDetail.fromJson(const {
        'employeeId': 12, 'fullName': 'سنان', 'receiptLanguage': 'Arabic',
        'hasPhoto': false, 'companies': [], 'userId': 7, 'username': 'sinan',
      });
      final free = EmployeeDetail.fromJson(const {
        'employeeId': 13, 'fullName': 'علي', 'receiptLanguage': 'Arabic',
        'hasPhoto': false, 'companies': [],
      });
      expect(linked.isLinkedToUser, isTrue);
      expect(linked.username, 'sinan');
      expect(free.isLinkedToUser, isFalse);
    });
  });

  // ══════════════════ الشاشة بالرسم ══════════════════

  group('الشاشة تُبنى وتتبع حقيقة الربط — بالرسم لا بالحساب', () {
    // 🔴 اختبار الخاصيّة وحدها لا يُثبت أن الشاشة تستعملها (درس «نيّة التنقّل»:
    //    خمسة اختبارات خضراء على منطقٍ سليم، والعطل في **استدعائه**).
    Future<void> pumpProfile(WidgetTester tester, ApiClient api,
        {double width = 1200}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FixedSession(_session())),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(width: width, height: 800, child: const ProfileScreen()),
            ),
          ),
        ),
      ));
      await tester.pump();   // build
      await tester.pump();   // بعد وصول البيانات
    }

    testWidgets('المربوط: التبويبات الثلاثة تظهر', (tester) async {
      await pumpProfile(tester, _LinkedApi());
      expect(tester.takeException(), isNull);
      expect(find.text('هويّتي'), findsOneWidget);
      expect(find.text('إجازاتي'), findsOneWidget);
      expect(find.text('رواتبي'), findsOneWidget);
    });

    testWidgets('🔴 غير المربوط: تبويبٌ واحد **وتفسيرٌ للسبب**', (tester) async {
      await pumpProfile(tester, _UnlinkedApi());
      expect(tester.takeException(), isNull);
      expect(find.text('هويّتي'), findsOneWidget);
      expect(find.text('إجازاتي'), findsNothing);
      expect(find.text('رواتبي'), findsNothing);
      // تبويبتان مفقودتان بلا تفسيرٍ تبدوان عطلاً لا حجباً.
      expect(find.textContaining('غير مرتبط ببطاقة موظف'), findsOneWidget);
    });

    testWidgets('هويّتي: تعرض البيانات ولا تعرض حقل تحريرٍ للاسم', (tester) async {
      await pumpProfile(tester, _LinkedApi());
      expect(find.text('sinan'), findsOneWidget);
      expect(find.text('محاسب'), findsWidgets);
      // 🔴 **عرضٌ لا تحرير** (قرار المالك): لا حقل إدخالٍ واحد في تبويب الهويّة.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
    });

    // ── الصورة يغيّرها صاحبها (ADR-035) ──
    //
    // 🔴 **الحارس هنا حارسُ مدخلٍ لا حارسُ دالّة**: نمطُ «ميزة بلا مدخل» تكرّر في هذا
    //    المستودع خمس مرّات (G7 · G8 · G10 · مستمسكات الموظف · إسناد موظفٍ قائم)،
    //    فنقطةُ رفعٍ في الخادم بلا زرٍّ في الشاشة ميزةٌ ميتة.
    testWidgets('🔴 المربوط: شارةُ الكاميرا على الأفاتار موجودة **وداخل الشاشة**',
        (tester) async {
      await pumpProfile(tester, _LinkedApi());
      final badge = find.byTooltip('تغيير صورتي');
      expect(badge, findsOneWidget);

      // ⚠️ **الوجود في الشجرة ليس ظهوراً على الشاشة.** الشارة موضوعةٌ بإزاحةٍ سالبة
      //    داخل `Stack`، فلو قصّها سلفٌ أو خرجت عن الحدود لبقي `find` ناجحاً
      //    **والمستخدم لا يراها** — وهو بيت بلاغ المالك (2026-08-19).
      final r = tester.getRect(badge);
      final screen = tester.getRect(find.byType(Scaffold));
      expect(r.width > 0 && r.height > 0, isTrue, reason: 'مساحةٌ صفرية = غير مرئية');
      expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight), isTrue,
          reason: 'الشارة خارج حدود الشاشة: $r مقابل $screen');
    });

    // 🔴 **بلاغ المالك (2026-08-19): «لا أرى أي مكان أغيّر منه الصورة».**
    //    الشارة الصغيرة في زاوية الأفاتار لا تكفي مدخلاً — **الميزة التي لا يجدها
    //    صاحبها ميزةٌ غير موجودة**، وهو نمطٌ تكرّر في هذا المستودع (G7 · G8 · G10 ·
    //    المستمسكات · إسناد موظفٍ قائم). فالمدخل زرٌّ **مُسمّى** بجانب «تغيير كلمة المرور».
    testWidgets('🔴 وزرٌّ **مُسمّى** في تبويب الهويّة — لا شارةً وحدها', (tester) async {
      await pumpProfile(tester, _LinkedApi());
      final btn = find.widgetWithText(OutlinedButton, 'تغيير الصورة الشخصية');
      expect(btn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull,
          reason: 'زرٌّ معطَّل مدخلٌ غير موجود');
      final r = tester.getRect(btn);
      expect(r.width > 0 && r.height > 0, isTrue);
    });

    // ⚠️ **بلا بطاقةٍ لا موضعَ للصورة**: الصورة تُكتب على البطاقة، فزرٌّ يردّ 404
    //    أسوأ من زرٍّ غائب — يوهم صاحبَه أن الميزة معطوبة لا محجوبة.
    testWidgets('🔴 غير المربوط: لا شارةَ ولا زرّ — لا موضعَ لصورته', (tester) async {
      await pumpProfile(tester, _UnlinkedApi());
      expect(find.byIcon(Icons.photo_camera_rounded), findsNothing);
      expect(find.byTooltip('تغيير صورتي'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'تغيير الصورة الشخصية'), findsNothing);
      // وكلمةُ المرور تبقى متاحةً له — الحجب للصورة وحدها.
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
    });
  });

  // ══════════════════ حرّاس الرسم ══════════════════

  group('حرّاس رسمٍ ضدّ فيض التخطيط', () {
    // ⚠️ الفيض تحت العرض الضيّق عطبٌ متكرّر في هذا المستودع (G12 · جدول الرواتب ·
    //    شريط الأدوات) — و«رقمٌ يجب أن يسع محتوًى **يُقاس بالرسم لا يُخمَّن**».
    for (final width in [380.0, 420.0, 700.0, 900.0, 1280.0, 1600.0]) {
      testWidgets('ترويسة البروفايل لا تفيض عند $width', (tester) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() => _FixedSession(_session())),
            apiClientProvider.overrideWithValue(_LinkedApi()),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(width: width, height: 800, child: const ProfileScreen()),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('🔴 ترويسةُ غير المربوط لا تفيض عند $width', (tester) async {
        // بطاقة التنبيه تُضاف إلى الصفّ — وهي أطولُ عنصرٍ فيه، فالفيض يبدأ منها.
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() => _FixedSession(_session())),
            apiClientProvider.overrideWithValue(_UnlinkedApi()),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(width: width, height: 800, child: const ProfileScreen()),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

// ═══════════════════════ مساعدات ═══════════════════════

SessionState _session() => SessionState(
      loaded: true,
      activeCompanyId: 1,
      auth: AuthResult(
        accessToken: 't',
        accessExpires: DateTime.now().add(const Duration(hours: 1)),
        refreshToken: 'r',
        userId: 7,
        fullName: 'سنان أياد',
        username: 'sinan',
        role: 'Employee',
        companyIds: const [1],
        mustChangePassword: false,
        companies: [CompanyAccess(companyId: 1, modules: const [])],
      ),
    );

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

/// عميلُ API صامت — بلا شبكة ولا مؤقّتات معلّقة تُفشل الاختبار بلا عيبٍ في المنتج.
class _SilentApi extends ApiClient {
  _SilentApi() : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));

  @override
  Future<List<LeaveModel>> myLeaves() async => const [];

  @override
  Future<List<MyPayslip>> myPayslips({int? year}) async => const [];

  @override
  Future<Uint8List> myPhoto() async => Uint8List(0);
}

/// مستخدمٌ **مربوطٌ ببطاقة** — التبويبات الثلاثة تظهر له.
class _LinkedApi extends _SilentApi {
  @override
  Future<MyProfile> myProfile() async => MyProfile.fromJson(const {
        'userId': 7,
        'fullName': 'سنان أياد',
        'username': 'sinan',
        'role': 'Employee',
        'companyName': 'أرض العرين للتجارة والمقاولات',
        'departmentName': 'المالية',
        'employeeId': 12,
        'employeeFullName': 'سنان أياد محمد حسن',
        'position': 'محاسب',
        'hireDate': '2024-03-01',
        'nationalId': '19900101234',
        'phone': '07700000000',
        'hasPhoto': false,
      });
}

/// مستخدمٌ **بلا بطاقة** (سوبر أدمن مثلاً) — تبويبٌ واحد وتفسيرٌ للسبب.
class _UnlinkedApi extends _SilentApi {
  @override
  Future<MyProfile> myProfile() async => MyProfile.fromJson(const {
        'userId': 1,
        'fullName': 'مدير النظام',
        'username': 'admin',
        'role': 'SuperAdmin',
        'companyName': 'أرض العرين للتجارة والمقاولات',
      });
}
