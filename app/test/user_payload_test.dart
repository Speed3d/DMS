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
  // حمولة كما ينتجها نموذج المستخدم لموظف مُسنَد لقسم وبصلاحية إدارة الوارد.
  Map<String, dynamic> formPayload() => {
        'fullName': 'سنان',
        'username': 'sinan',
        'password': 'Secret@12345',
        'role': 'Employee',
        'companyIds': [1, 2],
        'canApprove': false,
        'isActive': true,
        'canManageIncoming': true,
        'departmentId': 7,
        'modules': ['Outgoing', 'Incoming'],
      };

  group('buildUserUpdateBody', () {
    test('يحتفظ بالقسم وصلاحية إدارة الوارد (العيب الذي تكرّر)', () {
      final body = buildUserUpdateBody(formPayload());
      expect(body['departmentId'], 7);
      expect(body['canManageIncoming'], true);
    });

    test('يحتفظ بإسناد الشركات (العيب الأول من نفس النوع)', () {
      expect(buildUserUpdateBody(formPayload())['companyIds'], [1, 2]);
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
      final form = formPayload()..['departmentId'] = null;
      final body = buildUserUpdateBody(form);
      expect(body.containsKey('departmentId'), isTrue);
      expect(body['departmentId'], isNull);
    });
  });
}
