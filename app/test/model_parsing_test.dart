import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';

/// حرّاس عطلَين بلّغ عنهما المالك في 2026-08-12، وكلاهما **عائلةٌ لا حالة**.
void main() {
  group('🔴 وقت الخادم لحظةٌ بتوقيت UTC — لا نصٌّ بلا منطقة', () {
    // السبب: الخادم يرسل "2026-08-11T21:31:00.846" بلا Z (EF يقرأ datetime2 بـ Kind
    // = Unspecified)، وDart يقرأ ما لا منطقةَ له على أنه **محليّ** — فيُعرض وقت غرينتش
    // على أنه وقت بغداد: متأخّرٌ ثلاث ساعات، **والتاريخ يتأخّر يوماً** بعد التاسعة مساءً.

    test('نصٌّ بلا منطقة يُقرأ UTC لا محليّاً', () {
      final t = parseInstant('2026-08-11T21:31:00.8464773');
      expect(t.isUtc, isTrue);
      expect(t.year, 2026);
      expect(t.month, 8);
      expect(t.day, 11);
      expect(t.hour, 21);
      expect(t.minute, 31);
    });

    test('🔴 وبتوقيت بغداد يصير اليوم التالي — وهو بيت العطل', () {
      // 21:31 UTC = 00:31 من اليوم التالي في بغداد (+03:00 بلا توقيت صيفي منذ 2015).
      final baghdad = parseInstant('2026-08-11T21:31:00').add(const Duration(hours: 3));
      expect(baghdad.day, 12);
      expect(baghdad.hour, 0);
      expect(baghdad.minute, 31);
    });

    test('نصٌّ يحمل Z يُقرأ كما هو بلا إزاحةٍ مضاعفة', () {
      final a = parseInstant('2026-08-11T21:31:00Z');
      final b = parseInstant('2026-08-11T21:31:00');
      expect(a.isAtSameMomentAs(b), isTrue, reason: 'إضافة Z مرّتين تزيح الوقت');
    });

    test('نصٌّ يحمل إزاحةً صريحة يُحترم', () {
      // 2026-08-12T00:31+03:00 هي 21:31 UTC نفسها.
      final t = parseInstant('2026-08-12T00:31:00+03:00');
      expect(t.isUtc, isTrue);
      expect(t.hour, 21);
      expect(t.day, 11);
    });

    test('الفارغ لا يُسقط التطبيق', () {
      expect(parseInstant(null).isUtc, isTrue);
      expect(parseInstant('').isUtc, isTrue);
      expect(parseInstant('ليس تاريخاً').isUtc, isTrue);
    });

    test('🔴 وسطر النشاط يمرّ بالدالّة فعلاً — لا اختبارَ للدالّة وحدها', () {
      // درسٌ مسجَّل: «اختبرتُ الدالّة ولم أختبر استدعاءها». العيّنة بصيغة الخادم الحقيقية.
      final row = ActivityRow.fromJson({
        'timestamp': '2026-08-11T21:31:00.8464773',
        'userId': 1,
        'userName': 'مدير النظام',
        'action': 'Login',
        'actionLabel': 'تسجيل دخول',
        'entityType': 'User',
        'entityLabel': 'مستخدم',
        'entityId': '1',
        'details': null,
      });
      expect(row.timestamp.isUtc, isTrue, reason: 'لو قُرئ محليّاً لعُرض الوقت ناقصاً 3 ساعات');
      expect(row.timestamp.hour, 21);
    });

    test('⚠️ والتواريخ التقويمية لا تمرّ بها — يومٌ لا لحظة', () {
      // كتابٌ مؤرَّخ في الأول من الشهر يجب أن يبقى الأول، لا أن ينقص يوماً بالمنطقة الزمنية.
      final book = OutgoingListItem.fromJson({
        'outgoingId': 1,
        'number': 'DEN-2026-00001',
        'date': '2026-08-01T00:00:00',
        'subject': 'كتاب',
        'entityName': 'جهة',
        'status': 'Final',
      });
      expect(book.date.day, 1, reason: 'تحويلُ يومٍ بالمنطقة الزمنية يُنقصه يوماً');
      expect(book.date.month, 8);
    });
  });

  group('🔴 منسدلةٌ لا تسقط بقيمةٍ خارج خياراتها', () {
    // السبب: القيمة محفوظةٌ في مزوّد يعيش أطول من الشاشة، وقائمتها تُجلب غير متزامنة.
    // فيقع إطارٌ قيمتُه 7 وقائمتُه فارغة ⇒ Material يرمي assertion وتسقط الشاشة.

    test('القيمة الموجودة تُعاد كما هي', () {
      expect(safeDropdownValue(7, [3, 7, 9]), 7);
    });

    test('🔴 القيمة الغائبة تصير null بدل أن تُسقط الشاشة', () {
      expect(safeDropdownValue(7, <int>[]), isNull, reason: 'القائمة لم تصل بعد');
      expect(safeDropdownValue(7, [1, 2, 3]), isNull, reason: 'القسم/النوع حُذف');
    });

    test('null يبقى null', () {
      expect(safeDropdownValue<int>(null, [1, 2]), isNull);
    });

    test('تعمل على أي نوع لا على الأعداد وحدها', () {
      expect(safeDropdownValue('Paper', ['Incoming', 'Paper']), 'Paper');
      expect(safeDropdownValue('Ghost', ['Incoming', 'Paper']), isNull);
    });

    // 🔴 **وبالرسم لا بالحساب**: الدالّة سليمة لا يعني أن المنسدلة لا تسقط. هذان يبنيان
    //    `DropdownButton` فعلاً — الأول **يُثبت أن التركيب الخاطئ يرمي**، والثاني أن
    //    الحارس يمنعه. (نظير حارس `hr_render_test` الذي يتأكّد أن الخطأ يقع بلا الإصلاح.)
    test('🔴 بلا الحارس: قيمةٌ خارج الخيارات **ترمي** فعلاً', () {
      // ⚠️ التأكيد يقع في **مُنشئ** `DropdownButton` لا أثناء الرسم
      //    (`dropdown.dart:1034 new` في بلاغ المالك) — فيُرمى متزامناً قبل أي `pump`.
      //    ولهذا هو `test` لا `testWidgets`: الرمي لا ينتظر إطاراً.
      expect(() => _dropdownHost(value: 7, ids: const []), throwsAssertionError,
          reason: 'لو لم يعد يرمي، فقد تغيّر Material — تُراجَع الحاجة للحارس لا يُحذف');
    });

    testWidgets('✅ ومع الحارس: تُبنى بلا استثناء وتعرض «الكل»', (tester) async {
      await tester.pumpWidget(_dropdownHost(value: safeDropdownValue(7, const <int>[]), ids: const []));
      expect(tester.takeException(), isNull);
      expect(find.text('كل الأنواع'), findsOneWidget);
    });
  });
}

/// أصغر شجرةٍ تُعيد إنتاج منسدلة المرشِّح في شاشتَي الوارد والأرشيف.
Widget _dropdownHost({required int? value, required List<int> ids}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: DropdownButton<int?>(
            value: value,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('كل الأنواع')),
              ...ids.map((i) => DropdownMenuItem<int?>(value: i, child: Text('نوع $i'))),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
