import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';

/// حرّاس صلاحيات وحدة الموظفين والرواتب (ADR-023).
///
/// ⚠️ سبب وجودها: الوحدة محكومة بـ**حدَّين معاً** — قسم `HR` **ودورٌ مديرٌ فأعلى** — والباك-إند
/// يردّ 403 على من نقصه أحدهما. لو اكتفت الواجهة بفحص القسم لظهر بندٌ في الشريط الجانبي
/// يقود إلى شاشة تردّ 403، وهو **أسوأ من إخفائه**: يظنّ المستخدم أن النظام معطوب لا أنه
/// غير مخوَّل. وحارسٌ آليّ خيرٌ من فحص بصري لا يُعاد.
void main() {
  SessionState sessionWith({
    required List<String> modules,
    required String role,
    bool canManageHR = false,
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
            CompanyAccess(companyId: 1, modules: modules, canManageHR: canManageHR),
          ],
        ),
      );

  group('رؤية الوحدة تتطلّب القسم والدور معاً', () {
    test('مدير بقسم HR: يرى الوحدة', () {
      expect(sessionWith(modules: ['HR'], role: 'Manager').canSeeHr, isTrue);
    });

    test('موظف بقسم HR: **لا** يراها — الدور يحجبها', () {
      // هذا هو الحارس الأهمّ: الرواتب أحسّ بيانات في النظام.
      expect(sessionWith(modules: ['HR'], role: 'Employee').canSeeHr, isFalse);
    });

    test('قارئ بقسم HR: لا يراها', () {
      expect(sessionWith(modules: ['HR'], role: 'Reader').canSeeHr, isFalse);
    });

    test('مدير بلا قسم HR: لا يراها — القسم يحجبها', () {
      expect(sessionWith(modules: ['Outgoing', 'Incoming'], role: 'Manager').canSeeHr, isFalse);
    });

    test('سوبر أدمن ورئيس الشركة: يريانها بحكم الإعفاء ولو بقائمة أقسام فارغة', () {
      // المعفَون يعودون بكل الأقسام من `modulesIn` — كما يفعل الباك-إند تماماً.
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canSeeHr, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canSeeHr, isTrue);
    });
  });

  group('الكتابة تنفصل عن الرؤية', () {
    test('مدير بقسم HR بلا العلَم: يرى ولا يحرّر', () {
      final s = sessionWith(modules: ['HR'], role: 'Manager');
      expect(s.canSeeHr, isTrue);
      expect(s.canManageHr, isFalse);
    });

    test('مدير بقسم HR مع العلَم: يرى ويحرّر', () {
      final s = sessionWith(modules: ['HR'], role: 'Manager', canManageHR: true);
      expect(s.canSeeHr, isTrue);
      expect(s.canManageHr, isTrue);
    });

    test('السوبر أدمن يحرّر بحكم دوره ولو كان بلا إسناد', () {
      // ⚠️ عيبٌ حقيقي كُشف بالتشغيل الحيّ: السوبر أدمن قد يكون بلا `UserCompany`، فلا يحمل
      //    توكنه خريطة `hr_mng` أصلاً وتعود القراءة `false` — فيُحجب عن وحدةٍ يملكها بدوره.
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canManageHr, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canManageHr, isTrue);
    });
  });

  group('عقد الصلاحيات لا يفقد العلَم في الرحلة', () {
    test('CompanyAccess يحفظ canManageHR ذهاباً وإياباً', () {
      const access = CompanyAccess(
        companyId: 1,
        modules: ['HR', 'Outgoing'],
        canManageHR: true,
        canApprove: true,
      );
      final round = CompanyAccess.fromJson(access.toJson());
      expect(round.canManageHR, isTrue);
      expect(round.modules, contains('HR'));
    });

    test('غياب canManageHR من ردّ الخادم يعني «لا صلاحية» لا انهياراً', () {
      final a = CompanyAccess.fromJson({'companyId': 1, 'modules': ['HR']});
      expect(a.canManageHR, isFalse);
    });
  });

  group('قائمة الأقسام مرآةٌ للباك-إند', () {
    test('HR مدرَجة في kAllModules — وإلا لم يظهر مربّعها ولم تُحفظ الصلاحية أبداً', () {
      // نمط «ميزة بلا مدخل» الذي كلّف المشروع ثلاث فجوات (G7 · G8 · G10).
      expect(kAllModules, contains('HR'));
      expect(kAllModules.length, 8);
      expect(kModuleLabels['HR'], isNotNull);
    });
  });
}
