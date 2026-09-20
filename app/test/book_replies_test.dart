import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';

/// حرّاس الربط **كثيرٌ إلى كثير** بين الوارد والصادر (ADR-045).
///
/// ⚠️ **سبب وجودها:** العقد تحوّل من حقلين مفردين إلى **قائمتين**، وهو تغييرٌ
/// **لا يُصدر خطأً** في Dart: `j['replyOutgoingId']` على ردٍّ جديد يعود `null` فيختفي قسم
/// الربط من الشاشة **بلا رسالة**. فالحارس هنا يقيس العقد نفسه لا رسمه.
void main() {
  group('🔗 عقد الردود — قائمةٌ تعبر JSON ذهاباً', () {
    test('الوارد يقرأ عدّة ردود بترتيبها', () {
      final d = IncomingDetail.fromJson({
        'incomingId': 1,
        'companyId': 1,
        'receivedDate': '2026-09-01T00:00:00',
        'entityId': 1,
        'entityName': 'وزارة',
        'subject': 'طلب معلومات',
        'receiveMethod': 'Manual',
        'receivedByUserId': 2,
        'receivedByUserName': 'موظف',
        'status': 'Replied',
        'createdAt': '2026-09-01T08:00:00',
        'replies': [
          {
            'bookId': 10,
            'number': 'DEN-2026-00010',
            'date': '2026-09-05T00:00:00',
            'subject': 'ردّ أوّليّ',
            'linkedAt': '2026-09-05T09:00:00',
          },
          {
            'bookId': 11,
            'number': 'DEN-2026-00011',
            'date': '2026-09-20T00:00:00',
            'subject': 'الجواب النهائي',
            'linkedAt': '2026-09-20T10:00:00',
          },
        ],
      });

      expect(d.replies.length, 2);
      expect(d.replies.first.number, 'DEN-2026-00010');
      expect(d.replies.last.subject, 'الجواب النهائي');
    });

    test('والصادر يقرأ عدّة واردات ردّ عليها', () {
      final o = OutgoingDetail.fromJson({
        'outgoingId': 5,
        'companyId': 1,
        'date': '2026-09-20T00:00:00',
        'entityId': 1,
        'entityName': 'وزارة',
        'templateId': 1,
        'subject': 'جواب شامل',
        'bodyHtml': '<p>x</p>',
        'status': 'Final',
        'createdAt': '2026-09-20T08:00:00',
        'rowVersion': 'AAAAAAAApBE=',
        'repliesTo': [
          {
            'bookId': 1,
            'number': 'DEN-IN-2026-00001',
            'date': '2026-09-01T00:00:00',
            'subject': 'وارد ١',
            'linkedAt': '2026-09-20T10:00:00',
          },
          {
            'bookId': 2,
            'number': 'DEN-IN-2026-00002',
            'date': '2026-09-02T00:00:00',
            'subject': 'وارد ٢',
            'linkedAt': '2026-09-20T10:00:01',
          },
        ],
      });

      // 🔴 **هذه هي الحالة التي كسرت النموذج القديم**: صادرٌ واحد أجاب أكثر من وارد،
      //    والعمود المفرد كان يُجبر على إخفاء البقيّة.
      expect(o.repliesTo.length, 2);
      expect(o.repliesTo.map((r) => r.bookId), [1, 2]);
    });

    test('⚠️ وغيابُ الحقل قائمةٌ فارغة لا استثناء — فردٌّ قديم لا يُسقط الشاشة', () {
      final d = IncomingDetail.fromJson({
        'incomingId': 1,
        'companyId': 1,
        'receivedDate': '2026-09-01T00:00:00',
        'entityId': 1,
        'entityName': 'وزارة',
        'subject': 'س',
        'receiveMethod': 'Manual',
        'receivedByUserId': 2,
        'receivedByUserName': 'م',
        'status': 'New',
        'createdAt': '2026-09-01T08:00:00',
      });
      expect(d.replies, isEmpty);

      final o = OutgoingDetail.fromJson({
        'outgoingId': 5,
        'companyId': 1,
        'date': '2026-09-20T00:00:00',
        'entityId': 1,
        'entityName': 'و',
        'templateId': 1,
        'subject': 'س',
        'bodyHtml': '',
        'status': 'Draft',
        'createdAt': '2026-09-20T08:00:00',
        'rowVersion': '',
      });
      expect(o.repliesTo, isEmpty);
    });
  });

  group('📅 التاريخ يومٌ واللحظة لحظة — داخل `ReplyLink` نفسها', () {
    test('`date` يومٌ تقويميّ لا يُنقص يوماً', () {
      // كتابٌ مؤرَّخ في الأول من الشهر يجب أن يبقى الأول (ADR-032).
      final r = ReplyLink.fromJson({
        'bookId': 1,
        'number': 'X',
        'date': '2026-09-01T00:00:00',
        'subject': 's',
        'linkedAt': '2026-09-01T21:31:00',
      });
      expect(r.date.day, 1);
      expect(r.date.month, 9);
    });

    test('و`linkedAt` لحظةٌ تُقرأ UTC — فلا تتأخّر ثلاث ساعات', () {
      final r = ReplyLink.fromJson({
        'bookId': 1,
        'number': 'X',
        'date': '2026-09-01T00:00:00',
        'subject': 's',
        'linkedAt': '2026-09-01T21:31:00',
      });
      expect(r.linkedAt.isUtc, isTrue);
      expect(r.linkedAt.hour, 21);
    });

    test('🔴 والحارس له أسنان: لو قُرئ `date` كلحظةٍ لاختلف عن قراءته يوماً', () {
      // بغداد ‎+03:00‎ بلا توقيت صيفي: يومٌ عند منتصف الليل يُقرأ لحظةً فيصير اليوم السابق
      // بعد التحويل. وهذا يُثبت أن التمييز بين الدالّتين **يقيس شيئاً**.
      const raw = '2026-09-01T00:00:00';
      expect(DateTime.parse(raw).day, 1);
      expect(parseInstant(raw).add(const Duration(hours: 3)).day, 1);
      expect(parseInstant(raw).subtract(const Duration(hours: 3)).day, 31);
    });
  });

  group('🔐 صلاحية إدارة الوارد في الجلسة', () {
    SessionState sessionWith({
      required String role,
      bool canManageIncoming = false,
    }) =>
        SessionState(
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
            companies: [
              CompanyAccess(
                companyId: 1,
                modules: const ['Incoming'],
                canManageIncoming: canManageIncoming,
              ),
            ],
          ),
        );

    test('موظفٌ مُنح العلَم يملكها', () {
      expect(sessionWith(role: 'Employee', canManageIncoming: true).canManageIncoming, isTrue);
    });

    test('وموظفٌ بلا العلَم لا يملكها', () {
      expect(sessionWith(role: 'Employee').canManageIncoming, isFalse);
    });

    test('🔴 والقارئ لا يملكها **ولو مُنح العلَم صراحةً**', () {
      // ⚠️ هذه ليست حالةً نظرية: `UserService.ResolveLinksAsync` يصفّر للقارئ الأعلامَ
      //    الحسّاسة الأربعة **ولا يمسّ `CanManageIncoming`** — فالقارئ **يستطيع حملَه فعلاً**
      //    في قاعدة البيانات. ولهذا يحجبه الخادم بفحصٍ صريح للدور، ونحن مرآتُه.
      expect(sessionWith(role: 'Reader', canManageIncoming: true).canManageIncoming, isFalse);
    });

    test('والمعفَون يملكونها بلا منحٍ صريح — قد يكونون بلا إسنادٍ لأي شركة', () {
      // 🔴 بلا هذا الإعفاء يُقفَل السوبر أدمن خارج ميزته — وهو عطلٌ وقع فعلاً في وحدة
      //    الرواتب (`/me` أعاد `canManageHR=false` لحساب الأدمن في أول تشغيل حيّ).
      expect(sessionWith(role: 'SuperAdmin').canManageIncoming, isTrue);
      expect(sessionWith(role: 'President').canManageIncoming, isTrue);
    });
  });
}
