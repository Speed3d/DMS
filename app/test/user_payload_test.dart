import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/screens/users_screen.dart';

/// حارس انحدار لعيب تكرّر مرتين: حمولة تعديل المستخدم كانت تُبنى بقائمة حقول
/// مختارة يدوياً، فسقط منها `companyIds` أولاً ثم `canManageIncoming`/`departmentId`.
/// ولأن عقد التعديل في الباك-إند يمنح الحقلين القيمتين الافتراضيتين `false`/`null`،
/// كان كل تعديل يمسح قسم الموظف وصلاحيته بصمت — بلا رسالة خطأ.
///
/// ملاحظة مهمة: اختبار E2E للأقسام مرّ **10/10 والميزة مكسورة**، لأن السكربت يرسل
/// الحمولة كاملة بينما العميل كان يُسقط حقلين. فالحارس يجب أن يكون هنا (جهة العميل).
void main() {
  // حمولة كما ينتجها نموذج المستخدم: موظف في شركتين بصلاحيات وأقسام **مختلفة** (ADR-017).
  Map<String, dynamic> formPayload() => {
        'fullName': 'سنان',
        'username': 'sinan',
        'password': 'Secret@12345',
        'role': 'Employee',
        'isActive': true,
        // Hint: النوع مُصرَّح لأن `departmentId` قد يصير null (إزالة الإسناد)، والاستنتاج
        //       الضمني كان يُنتج Map<String, Object> فيرفض الإسناد.
        'companies': <Map<String, dynamic>>[
          {
            'companyId': 1,
            'modules': ['Outgoing', 'Incoming'],
            'departmentId': 7,
            'canApprove': false,
            'canManageIncoming': true,
          },
          {
            'companyId': 2,
            'modules': ['Outgoing', 'Reports'],
            'departmentId': 9,
            'canApprove': true,
            'canManageIncoming': false,
          },
        ],
      };

  group('buildUserUpdateBody', () {
    test('يحتفظ بالقسم وصلاحية إدارة الوارد (العيب الذي تكرّر)', () {
      final companies = buildUserUpdateBody(formPayload())['companies'] as List;
      expect(companies[0]['departmentId'], 7);
      expect(companies[0]['canManageIncoming'], true);
    });

    test('يحتفظ باختلاف الصلاحيات والأقسام بين شركتَي المستخدم', () {
      final companies = buildUserUpdateBody(formPayload())['companies'] as List;
      expect(companies.length, 2);
      // لو انهار التمييز بين الشركات لتساوت القيم — وهذا جوهر ADR-017.
      expect(companies[0]['departmentId'], isNot(companies[1]['departmentId']));
      expect(companies[0]['modules'], isNot(companies[1]['modules']));
      expect(companies[0]['canApprove'], isNot(companies[1]['canApprove']));
    });

    test('يحذف حقول الإنشاء فقط ويُبقي كل ما عداها', () {
      final form = formPayload();
      final body = buildUserUpdateBody(form);
      expect(body.containsKey('username'), isFalse);
      expect(body.containsKey('password'), isFalse);
      // كل مفتاح آخر في النموذج يجب أن يصل — هذا ما يمنع عودة القائمة البيضاء.
      for (final key in form.keys.where((k) => !kUserCreateOnlyFields.contains(k))) {
        expect(body.containsKey(key), isTrue, reason: 'الحقل «$key» سقط من حمولة التعديل');
      }
    });

    test('لا يعدّل حمولة النموذج الأصلية', () {
      final form = formPayload();
      buildUserUpdateBody(form);
      expect(form.containsKey('username'), isTrue);
    });

    test('حذف القسم يبقى ممكناً (null تعني إزالة الإسناد لا «لا تغيير»)', () {
      final form = formPayload();
      (form['companies'] as List)[0]['departmentId'] = null;
      final companies = buildUserUpdateBody(form)['companies'] as List;
      expect(companies[0].containsKey('departmentId'), isTrue);
      expect(companies[0]['departmentId'], isNull);
    });

    test('قائمة الشركات تصل كاملة ولا تُختزل', () {
      // Hint: حارس ضد «إرسال الشركة الفعّالة وحدها» — وهو الخطأ الطبيعي عند التبسيط،
      //       ونتيجته مسحُ صلاحيات المستخدم في بقية شركاته.
      final body = buildUserUpdateBody(formPayload());
      expect((body['companies'] as List).map((c) => c['companyId']), [1, 2]);
    });
  });
}
