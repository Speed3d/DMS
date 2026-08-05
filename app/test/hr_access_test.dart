import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';

/// حرّاس صلاحيات قسمَي الموظفين والرواتب (ADR-023 ← **ADR-025**).
///
/// ⚠️ سبب وجودها: القسمان محكومان بـ**حدَّين معاً** — القسم **ودورٌ فوق القارئ** — والباك-إند
/// يردّ 403 على من نقصه أحدهما. لو اكتفت الواجهة بفحص القسم لظهر بندٌ في الشريط الجانبي
/// يقود إلى شاشة تردّ 403، وهو **أسوأ من إخفائه**: يظنّ المستخدم أن النظام معطوب لا أنه
/// غير مخوَّل. وحارسٌ آليّ خيرٌ من فحص بصري لا يُعاد.
///
/// 🔄 **وما تغيّر في ADR-025:** الحدّ نزل من «المدير فأعلى» إلى «فوق القارئ»، و**القسم
/// الواحد صار قسمين لا يستلزم أحدهما الآخر** — وهذا ما تحرسه أكثر الاختبارات أدناه.
void main() {
  SessionState sessionWith({
    required List<String> modules,
    required String role,
    bool canManageEmployees = false,
    bool canManagePayroll = false,
  }) =>
      SessionState(
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
          companies: [
            CompanyAccess(
              companyId: 1,
              modules: modules,
              canManageEmployees: canManageEmployees,
              canManagePayroll: canManagePayroll,
            ),
          ],
        ),
      );

  group('الرؤية تتطلّب القسم والدور معاً', () {
    test('مدير بقسم الموظفين: يراه', () {
      expect(sessionWith(modules: ['Employees'], role: 'Manager').canSeeEmployees, isTrue);
    });

    test('🔄 **موظف بقسم الموظفين: يراه الآن** — كان محجوباً قبل ADR-025', () {
      // قرار المالك 2026-08-05: محاسبٌ أو كاتب شؤون موظفين بدور «موظف» يحتاجه يومياً،
      // وحصرُه في المدير كان يدفع إلى منح الدور الأعلى للالتفاف — وهو أوسع أثراً.
      expect(sessionWith(modules: ['Employees'], role: 'Employee').canSeeEmployees, isTrue);
      expect(sessionWith(modules: ['Payroll'], role: 'Employee').canSeePayroll, isTrue);
    });

    test('🔐 قارئ بالقسمين: لا يرى شيئاً — الدور يحجبه', () {
      final s = sessionWith(modules: ['Employees', 'Payroll'], role: 'Reader');
      expect(s.canSeeEmployees, isFalse);
      expect(s.canSeePayroll, isFalse);
      expect(s.canSeeAnyHr, isFalse);
    });

    test('مدير بلا القسمين: لا يراهما — القسم يحجبهما', () {
      final s = sessionWith(modules: ['Outgoing', 'Incoming'], role: 'Manager');
      expect(s.canSeeEmployees, isFalse);
      expect(s.canSeePayroll, isFalse);
    });

    test('سوبر أدمن ورئيس الشركة: يريانهما بحكم الإعفاء ولو بقائمة أقسام فارغة', () {
      // المعفَون يعودون بكل الأقسام من `modulesIn` — كما يفعل الباك-إند تماماً.
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canSeeEmployees, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canSeePayroll, isTrue);
    });
  });

  group('🔐 جوهر ADR-025: قسمٌ لا يفتح الآخر', () {
    test('مَن يملك الموظفين وحدهم لا يرى الرواتب', () {
      final s = sessionWith(modules: ['Employees'], role: 'Manager');
      expect(s.canSeeEmployees, isTrue);
      expect(s.canSeePayroll, isFalse);
      expect(s.canSeeAnyHr, isTrue);
    });

    test('ومَن يملك الرواتب وحدها لا يرى الموظفين', () {
      final s = sessionWith(modules: ['Payroll'], role: 'Employee');
      expect(s.canSeePayroll, isTrue);
      expect(s.canSeeEmployees, isFalse);
    });

    test('وعلَما الكتابة مستقلّان كذلك', () {
      final s = sessionWith(
        modules: ['Employees', 'Payroll'],
        role: 'Manager',
        canManageEmployees: true,
      );
      expect(s.canManageEmployees, isTrue);
      expect(s.canManagePayroll, isFalse,
          reason: 'مَن يُدخل بيانات الموظفين ليس بالضرورة مَن يصرف رواتبهم');
    });
  });

  group('الكتابة تنفصل عن الرؤية', () {
    test('قسمٌ بلا علَم: يرى ولا يحرّر', () {
      final s = sessionWith(modules: ['Payroll'], role: 'Manager');
      expect(s.canSeePayroll, isTrue);
      expect(s.canManagePayroll, isFalse);
    });

    test('قسمٌ مع علَم: يرى ويحرّر', () {
      final s = sessionWith(
          modules: ['Payroll'], role: 'Manager', canManagePayroll: true);
      expect(s.canSeePayroll, isTrue);
      expect(s.canManagePayroll, isTrue);
    });

    test('السوبر أدمن يحرّر بحكم دوره ولو كان بلا إسناد', () {
      // ⚠️ عيبٌ حقيقي كُشف بالتشغيل الحيّ: السوبر أدمن قد يكون بلا `UserCompany`، فلا يحمل
      //    توكنه خريطة العلَم أصلاً وتعود القراءة `false` — فيُحجب عن وحدةٍ يملكها بدوره.
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canManageEmployees, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canManagePayroll, isTrue);
    });
  });

  group('عقد الصلاحيات لا يفقد العلَمين في الرحلة', () {
    test('CompanyAccess يحفظ العلَمين ذهاباً وإياباً', () {
      const access = CompanyAccess(
        companyId: 1,
        modules: ['Employees', 'Payroll', 'Outgoing'],
        canManageEmployees: true,
        canManagePayroll: false,
        canApprove: true,
      );
      final round = CompanyAccess.fromJson(access.toJson());
      expect(round.canManageEmployees, isTrue);
      expect(round.canManagePayroll, isFalse, reason: 'الفصل يصمد عبر التسلسل');
      expect(round.modules, containsAll(['Employees', 'Payroll']));
    });

    test('غياب العلَمين من ردّ الخادم يعني «لا صلاحية» لا انهياراً', () {
      // ⚠️ التوكنات الصادرة قبل ADR-025 لا تحمل `emp_mng`/`pay_mng` — **فشلٌ مغلق**.
      final a = CompanyAccess.fromJson({'companyId': 1, 'modules': ['Employees']});
      expect(a.canManageEmployees, isFalse);
      expect(a.canManagePayroll, isFalse);
    });
  });

  group('«لا شيء» من الخادم لا يُسقط الشاشة', () {
    // ⚠️ عيبٌ حقيقي أبلغ عنه المالك (2026-08-04): `Ok(null)` في ASP.NET Core يُنتج
    //    **204 بجسمٍ فارغ**، فيسلّم Dio نصّاً فارغاً `''` لا `null`. وفحصُ `data == null`
    //    كان يمرّ فوقه ثم ينهار التحويل، فتسقط شاشة كشف الرواتب **قبل أن يظهر زرّ
    //    «توليد كشف الشهر»** — أي أن أول شهر يفتحه المستخدم في نظام جديد يبدو معطوباً.

    test('نصّ فارغ (204) يعني «لا شيء» لا انهياراً', () {
      expect(jsonObjectOrNull(''), isNull);
    });

    test('null يعني «لا شيء» كذلك', () {
      expect(jsonObjectOrNull(null), isNull);
    });

    test('أيّ جسمٍ ليس كائناً يُعامَل «لا شيء» بدل أن يُرمى', () {
      expect(jsonObjectOrNull('نصّ'), isNull);
      expect(jsonObjectOrNull(<dynamic>[]), isNull);
      expect(jsonObjectOrNull(42), isNull);
    });

    test('الكائن الحقيقي يمرّ كما هو', () {
      final map = <String, dynamic>{'periodId': 1, 'year': 2026, 'month': 1};
      expect(jsonObjectOrNull(map), same(map));
    });

    test('كشفٌ حقيقي يُحوَّل بلا خسارة بعد المرور بالحارس', () {
      final json = jsonObjectOrNull(<String, dynamic>{
        'periodId': 3, 'year': 2026, 'month': 1, 'monthName': 'كانون الثاني',
        'status': 'Draft', 'workingDaysMode': 'Fixed', 'workingDays': 30,
        // base64 كما يرسله الخادم فعلاً — `byte[]` لا يصل مصفوفةَ أرقام.
        'rowVersion': 'AAAAAAAApBE=', 'totalIqd': 1200000, 'entries': <dynamic>[],
      });
      final p = PayrollPeriodModel.fromJson(json!);
      expect(p.year, 2026);
      expect(p.month, 1);
      expect(p.isPaid, isFalse);
      expect(p.rowVersion, 'AAAAAAAApBE=');
    });
  });

  group('قائمة الأقسام مرآةٌ للباك-إند', () {
    test('القسمان مدرَجان في kAllModules — وإلا لم يظهر مربّعهما ولم تُحفظ الصلاحية', () {
      // نمط «ميزة بلا مدخل» الذي كلّف المشروع أربع فجوات (G7 · G8 · G10 · المستمسكات).
      expect(kAllModules, containsAll(['Employees', 'Payroll']));
      expect(kAllModules, isNot(contains('HR')), reason: 'الاسم القديم زال بـADR-025');
      expect(kAllModules.length, 9);
      expect(kModuleLabels['Employees'], isNotNull);
      expect(kModuleLabels['Payroll'], isNotNull);
    });
  });
}
