import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';

/// حرّاس صلاحيات وحدة المهام (ADR-037).
///
/// ⚠️ سبب وجودها هو سبب نظائرها في `hr_access_test.dart`: القسم محكومٌ بـ**حدَّين معاً** —
/// القسم **ودورٌ فوق القارئ** — والباك-إند يردّ 403 على من نقصه أحدهما. فلو اكتفت الواجهة
/// بفحص القسم لظهر بندٌ في الشريط يقود إلى شاشة تردّ 403، وهو **أسوأ من إخفائه**.
///
/// 🔴 وتحرس معها القاعدة التي لا يكشفها إلا اختبار: **قسمٌ خارج `AppModule.All` يجب أن يبقى
/// خارج [kDefaultModules]** — وإلا ناله كلُّ مستخدمٍ جديد بلا أن يمنحه أحد.
void main() {
  SessionState sessionWith({
    required List<String> modules,
    required String role,
    bool canManageTasks = false,
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
              canManageTasks: canManageTasks,
            ),
          ],
        ),
      );

  group('🔐 رؤية قسم المهام — القسم مع الدور', () {
    test('موظفٌ مُنح القسم يراه', () {
      expect(sessionWith(modules: ['Tasks'], role: 'Employee').canSeeTasks, isTrue);
    });

    test('🔴 والقارئ لا يراه **ولو مُنح القسم صراحةً**', () {
      // قرار المالك: دور القارئ اطّلاعٌ على الوثائق، والمهمة **تكليفٌ يُنفَّذ ويُحدَّث**.
      // ونظيرُ هذا الحارس في الخادم `ResolveModules` يجرّد القسم منه أصلاً — وهذا حزامٌ ثانٍ.
      expect(sessionWith(modules: ['Tasks'], role: 'Reader').canSeeTasks, isFalse);
    });

    test('ومَن لم يُمنح القسم لا يراه مهما علا دورُه دون الإعفاء', () {
      expect(sessionWith(modules: ['Outgoing'], role: 'Manager').canSeeTasks, isFalse);
    });

    test('والمعفَون يرونه بلا منحٍ صريح — قد يكونون بلا إسنادٍ لأي شركة', () {
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canSeeTasks, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canSeeTasks, isTrue);
    });
  });

  group('🔐 علَم إدارة مهام الآخرين — مستقلٌّ عن القسم', () {
    test('القسم بلا العلَم: يرى الوحدة ولا يوزّع', () {
      final s = sessionWith(modules: ['Tasks'], role: 'Employee');
      expect(s.canSeeTasks, isTrue);
      expect(s.canManageTasks, isFalse);
    });

    test('والقسم مع العلَم: يوزّع', () {
      final s = sessionWith(modules: ['Tasks'], role: 'Employee', canManageTasks: true);
      expect(s.canManageTasks, isTrue);
    });

    test('🔴 والمدير لا ينال العلَم بدوره — قد يكون مديرَ قسمٍ يستلم لا يوزّع', () {
      expect(sessionWith(modules: ['Tasks'], role: 'Manager').canManageTasks, isFalse);
    });

    test('والمعفَون يملكونه بدورهم', () {
      expect(sessionWith(modules: const [], role: 'SuperAdmin').canManageTasks, isTrue);
      expect(sessionWith(modules: const [], role: 'President').canManageTasks, isTrue);
    });
  });

  group('🔐 المهام خارج الأقسام الافتراضية', () {
    test('🔴 [kDefaultModules] بلا الأقسام الحسّاسة الثلاثة', () {
      // العيب الذي كان حيّاً: الشاشة تُهيّئ كل إسنادٍ جديد بكل الأقسام، فيبدأ المربّع
      // مؤشَّراً ويُرسَل إلى الخادم فيُحفَظ — منحٌ بلا أن يقصده أحد.
      expect(kDefaultModules, isNot(contains('Tasks')));
      expect(kDefaultModules, isNot(contains('Employees')));
      expect(kDefaultModules, isNot(contains('Payroll')));
    });

    test('وهي في [kAllModules] — وإلا مات المربّع بصمت', () {
      // مرآةُ `AppModuleExtensions.Individual`: قسمٌ ناقصٌ هنا لا يظهر مربّعه في شاشة
      // المستخدمين ولا تُحفظ صلاحيته أبداً (نمط «ميزة بلا مدخل»).
      expect(kAllModules, contains('Tasks'));
      expect(kModuleLabels['Tasks'], 'المهام');
    });

    test('ولكل قسمٍ في [kAllModules] تسميةٌ عربية', () {
      for (final m in kAllModules) {
        expect(kModuleLabels[m], isNotNull, reason: 'القسم $m بلا تسمية عربية');
      }
    });
  });

  group('🔗 حلقة العقد — العلَم يعبر JSON ذهاباً وإياباً', () {
    test('🔴 الحلقة التي تُنسى: علَمٌ لا يمرّ من العقد يصل فارغاً **دائماً**', () {
      // وقع حرفياً في `PaidAt` (ADR-026): يُحسب في الخدمة ويصل النموذجَ والواجهة، وعقد
      // الـAPI لا يمرّره — فاكتُشف بقراءة الملف لعملٍ آخر لا ببلاغٍ ولا باختبار.
      final parsed = CompanyAccess.fromJson({
        'companyId': 1,
        'modules': ['Tasks'],
        'canManageTasks': true,
      });

      expect(parsed.canManageTasks, isTrue);
      expect(parsed.toJson()['canManageTasks'], isTrue);
    });

    test('وغيابُه في ردٍّ قديم يُقرأ «لا صلاحية» — فشلٌ مغلق', () {
      final parsed = CompanyAccess.fromJson({'companyId': 1, 'modules': ['Tasks']});
      expect(parsed.canManageTasks, isFalse);
    });
  });
}
