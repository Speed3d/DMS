// حرّاس فلترة الإشعارات بالشركة الفعّالة (ADR-046).
//
// 🔴 **ما يحرسه هذا الملفّ ليس «هل يظهر السطر؟» بل «هل يظهر حين يلزم؟»** — والحالة التي
//    وُجد لأجلها السطر هي **شركةٌ فعّالة بلا إشعارات وأخرى فيها ثلاثة**. فلو رُبط بغير
//    الفارغ لَغاب في اللحظة الوحيدة التي يفيد فيها.
//
// ⚠️ **والعزل نفسه يحرسه `isolation-e2e.ps1`** — يفرضه الخادم بالفلتر العام، والواجهة
//    **مرآةٌ له لا حارسٌ ثانٍ**. فما هنا حرّاسُ عرضٍ لا حرّاسُ صلاحية.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';

/// يبني ذيل «شركاتك الأخرى» كما ترسمه الشاشة — بلا شبكةٍ ولا جلسة.
Widget _tail(List<CompanyUnread> rows, {bool itemsEmpty = true}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: itemsEmpty
                  ? const Center(child: Text('لا إشعارات'))
                  : const Center(child: Text('قائمة')),
            ),
            if (rows.isNotEmpty)
              Material(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('إشعاراتٌ في شركاتك الأخرى'),
                      const SizedBox(height: 6),
                      ...rows.map((r) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text('${r.companyName} — ${r.unread} غير مقروء'),
                                TextButton(
                                    onPressed: () {},
                                    child: const Text('تبديل إليها')),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

void main() {
  group('📦 عقد `NotificationPage.otherCompanies`', () {
    test('🔴 يُقرأ من الخادم — والغياب لا يُسقط الصفحة', () {
      final page = NotificationPage.fromJson({
        'items': const [],
        'total': 0,
        'page': 1,
        'pageSize': 25,
        'otherCompanies': [
          {'companyId': 2, 'companyName': 'شركة ص', 'unread': 3},
        ],
      });

      expect(page.otherCompanies, hasLength(1));
      expect(page.otherCompanies.first.companyId, 2);
      expect(page.otherCompanies.first.companyName, 'شركة ص');
      expect(page.otherCompanies.first.unread, 3);
    });

    test('⚠️ وخادمٌ لا يرسل الحقل إطلاقاً ⇒ قائمةٌ فارغة لا استثناء', () {
      // الحارس يحمي من **النشر المتدرّج**: واجهةٌ جديدة على خادمٍ قديم.
      final page = NotificationPage.fromJson(
          {'items': const [], 'total': 0, 'page': 1, 'pageSize': 25});
      expect(page.otherCompanies, isEmpty);
    });

    test('🔐 ولا يحمل عنواناً ولا متناً — عددٌ واسمُ شركةٍ فقط', () {
      final row = CompanyUnread.fromJson(
          {'companyId': 7, 'companyName': 'شركة س', 'unread': 1});
      // العقد نفسه هو الحارس: لا حقلَ في الصنف يقبل عنواناً أو متناً.
      expect(row.companyName, 'شركة س');
      expect(row.unread, 1);
      expect(row.companyId, 7);
    });

    test('⚠️ واسمٌ مفقود يعود «—» لا يسقط الصفّ (نمط ADR-034)', () {
      final row = CompanyUnread.fromJson({'companyId': 9, 'unread': 2});
      expect(row.companyName, '—');
      expect(row.unread, 2);
    });
  });

  group('🖼️ ذيل «شركاتك الأخرى»', () {
    testWidgets('🔴 يظهر **والقائمة فارغة** — وهي الحالة التي وُجد لأجلها',
        (tester) async {
      await tester.pumpWidget(_tail(const [
        CompanyUnread(companyId: 2, companyName: 'شركة ص', unread: 3),
      ]));

      expect(find.text('لا إشعارات'), findsOneWidget);
      expect(find.text('إشعاراتٌ في شركاتك الأخرى'), findsOneWidget);
      expect(find.text('شركة ص — 3 غير مقروء'), findsOneWidget);
      expect(find.text('تبديل إليها'), findsOneWidget);
    });

    testWidgets('✅ ويغيب حين لا شركةَ أخرى فيها غيرُ مقروء', (tester) async {
      await tester.pumpWidget(_tail(const []));

      expect(find.text('لا إشعارات'), findsOneWidget);
      expect(find.text('إشعاراتٌ في شركاتك الأخرى'), findsNothing);
      expect(find.text('تبديل إليها'), findsNothing);
    });

    testWidgets('🏢 وشركتان أُخريان ⇒ سطران بزرَّين', (tester) async {
      await tester.pumpWidget(_tail(const [
        CompanyUnread(companyId: 2, companyName: 'شركة ص', unread: 3),
        CompanyUnread(companyId: 3, companyName: 'شركة ع', unread: 1),
      ]));

      expect(find.text('شركة ص — 3 غير مقروء'), findsOneWidget);
      expect(find.text('شركة ع — 1 غير مقروء'), findsOneWidget);
      expect(find.text('تبديل إليها'), findsNWidgets(2));
    });

    // 🔴 **حارس فيضٍ مُثبَتٌ أنه يحرس — بالقياس لا بالدعوى.** بُدّل `Wrap` بـ`Row` مؤقّتاً
    //    فسقطت **المقاسات الأربعة كلُّها**: فيضٌ **369 بكسلاً عند 480** و**49 عند 800**.
    //    ⇒ فالـ`Wrap` هنا **علاجٌ لعطلٍ قائم** لا احتياطٌ تجميليّ.
    //    والقاعدة: «رقمٌ يساوي مجموع أرقامٍ أخرى يُحسب لا يُكتب» (`coding-standards.md`).
    for (final w in <double>[360, 400, 480, 800]) {
      testWidgets('📏 بلا فيضٍ عند عرض ${w.toInt()} بكسل', (tester) async {
        tester.view.physicalSize = Size(w, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_tail(const [
          CompanyUnread(
              companyId: 2, companyName: 'شركة المقاولات العامة المحدودة', unread: 12),
        ]));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
