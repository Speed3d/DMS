import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/outgoing_movements.dart';

/// سجلّ حركة الصادر وصورة السوبر أدمن (ADR-056).
void main() {
  test('🔐 كلُّ الأدوار ترى سجلّ الصادر عدا القارئ — مرآةٌ لحارس الخادم', () {
    for (final r in ['SuperAdmin', 'President', 'Manager', 'Employee']) {
      expect(canViewOutgoingMovements(r), isTrue, reason: r);
    }
    expect(canViewOutgoingMovements('Reader'), isFalse);
    expect(canViewOutgoingMovements(null), isFalse, reason: 'لا جلسة ⇒ لا طلب');
  });

  test('الحركة تُقرأ من الخادم — ورقم الوارد غائبٌ لمن لا يراه', () {
    final seen = OutgoingMovementItem.fromJson({
      'movementId': 1, 'action': 'LinkedIncoming', 'description': 'رُبط ردّاً على كتابٍ وارد',
      'relatedIncomingId': 9, 'relatedIncomingNumber': 'A-IN-2026-00009',
      'performedByUserName': 'أحمد مجيد', 'performedAt': '2026-09-25T10:00:00',
    });
    expect(seen.relatedIncomingNumber, 'A-IN-2026-00009');
    final hidden = OutgoingMovementItem.fromJson({
      'movementId': 2, 'action': 'LinkedIncoming', 'description': 'رُبط ردّاً على كتابٍ وارد',
      'performedByUserName': 'سنان', 'performedAt': '2026-09-25T10:00:00',
    });
    expect(hidden.relatedIncomingNumber, isNull);
  });

  test('صورة الحساب: الحقل من الخادم — وغيابُه (خادمٌ أقدم) يعود إلى البطاقة وحدها', () {
    expect(MyProfile.fromJson({'userId': 1, 'role': 'SuperAdmin', 'canChangePhoto': true}).canChangePhoto, isTrue);
    expect(MyProfile.fromJson({'userId': 1, 'role': 'SuperAdmin'}).canChangePhoto, isFalse);
    expect(MyProfile.fromJson({'userId': 2, 'role': 'Employee', 'employeeId': 5}).canChangePhoto, isTrue);
  });

  group('قسم السجلّ', () {
    Future<void> pump(WidgetTester tester, List<OutgoingMovementItem> items) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [outgoingMovementsProvider(7).overrideWith((ref) async => items)],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: OutgoingMovementsSection(outgoingId: 7))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    OutgoingMovementItem m(int id, String d, {String? number}) => OutgoingMovementItem(
        movementId: id, action: 'x', description: d, relatedIncomingNumber: number,
        performedByUserName: 'أحمد مجيد', performedAt: DateTime.utc(2026, 9, 25, 7));

    testWidgets('يعرض الحركات بترتيبها ومَن قام بها', (tester) async {
      await pump(tester, [
        m(1, 'إنشاء مسودّة'),
        m(2, 'تعديل المسودّة: الموضوع · المبلغ'),
        m(3, 'اعتماد برقم A-2026-00001'),
        m(4, 'رُبط ردّاً على كتابٍ وارد', number: 'A-IN-2026-00009'),
      ]);
      expect(find.text('سجل الحركة'), findsOneWidget);
      expect(find.text('تعديل المسودّة: الموضوع · المبلغ'), findsOneWidget);
      expect(find.text('رُبط ردّاً على كتابٍ وارد (A-IN-2026-00009)'), findsOneWidget);
      expect(find.textContaining('أحمد مجيد'), findsNWidgets(4));
    });

    testWidgets('🔐 وبلا رقم الوارد: الوصف المحايد وحده', (tester) async {
      await pump(tester, [m(1, 'رُبط ردّاً على كتابٍ وارد')]);
      expect(find.text('رُبط ردّاً على كتابٍ وارد'), findsOneWidget);
      expect(find.textContaining('IN-'), findsNothing);
    });

    testWidgets('كتابٌ أقدم من السجلّ: يُقال ذلك لا فراغٌ صامت', (tester) async {
      await pump(tester, []);
      expect(find.text('لا حركات مسجَّلة لهذا الكتاب بعد.'), findsOneWidget);
    });
  });
}
