import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/settings_screen.dart';

/// أنواع الصادر وخيارات الطباعة في الواجهة (ADR-057).
void main() {
  group('العقد مع الخادم', () {
    test('تفاصيل الصادر تقرأ النوع وخيارات الطباعة', () {
      final d = OutgoingDetail.fromJson({
        'outgoingId': 1, 'companyId': 1, 'entityId': 1, 'templateId': 1, 'date': '2026-10-04',
        'outgoingBookTypeId': 2, 'outgoingBookTypeName': 'فاتورة',
        'printEntity': false, 'printSubject': false, 'pageNumbers': false, 'signaturePlacement': 'StampEveryPage',
      });
      expect(d.bookTypeId, 2);
      expect(d.bookTypeName, 'فاتورة');
      expect([d.printEntity, d.printSubject, d.pageNumbers], [false, false, false]);
      expect(d.signaturePlacement, SignaturePlacement.stampEveryPage);
    });

    test('غيابُها (خادمٌ أقدم) هو الافتراض لا انهيار — وقيمةٌ مجهولة ⟵ «الأخيرة»', () {
      final d = OutgoingDetail.fromJson({'outgoingId': 1, 'companyId': 1, 'entityId': 1, 'templateId': 1, 'date': '2026-10-04'});
      expect([d.printEntity, d.printSubject, d.pageNumbers], [true, true, true]);
      expect(d.signaturePlacement, SignaturePlacement.lastPage);
      expect(SignaturePlacement.parse('Something'), SignaturePlacement.lastPage);
      expect(SignaturePlacement.values.map((v) => v.wire), ['LastPage', 'StampEveryPage', 'EveryPage']);
    });

    test('القائمة تحمل النوع · وسجلّ الحركة تفاصيله', () {
      final i = OutgoingListItem.fromJson({'outgoingId': 1, 'outgoingBookTypeId': 3, 'outgoingBookTypeName': 'عرض سعر'});
      expect((i.bookTypeId, i.bookTypeName), (3, 'عرض سعر'));
      final m = OutgoingMovementItem.fromJson({'movementId': 1, 'details': 'الجدول 1: تغيّرت خلية', 'performedAt': '2026-10-04T10:00:00Z'});
      expect(m.details, 'الجدول 1: تغيّرت خلية');
    });
  });

  group('تبويب «أنواع الصادر»', () {
    Future<_Api> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _Session()),
          apiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SettingsScreen())),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أنواع الصادر'));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('يعرض الأنواع، والأوّل موسومٌ «الافتراضي للكتاب الجديد»', (tester) async {
      await pump(tester);
      expect(find.text('كتاب رسمي'), findsOneWidget);
      expect(find.text('فاتورة'), findsOneWidget);
      expect(find.text('عرض سعر'), findsOneWidget);
      expect(find.text('الافتراضي للكتاب الجديد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الحذف المرفوض (نوعٌ مستعمل) يُعرض برسالة الخادم', (tester) async {
      final api = await pump(tester);
      await tester.tap(find.byTooltip('حذف').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
      await tester.pumpAndSettle();
      expect(api.deleted, [2]);
      expect(find.textContaining('مستخدَم في 3 كتاب'), findsOneWidget);
    });
  });
}

class _Session extends SessionNotifier {
  @override
  SessionState build() => SessionState(
        loaded: true,
        auth: AuthResult(
          accessToken: 't', accessExpires: DateTime.now().add(const Duration(hours: 1)), refreshToken: 'r',
          userId: 1, fullName: 'مدير', username: 'admin', role: 'Manager', companyIds: const [1],
          mustChangePassword: false, companies: const [],
        ),
      );
}

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);
  final deleted = <int>[];

  @override
  Future<List<OutgoingBookTypeModel>> outgoingBookTypes() async => [
        OutgoingBookTypeModel(1, 1, 'كتاب رسمي'),
        OutgoingBookTypeModel(2, 1, 'فاتورة'),
        OutgoingBookTypeModel(3, 1, 'عرض سعر'),
      ];

  @override
  Future<void> deleteOutgoingBookType(int id) async {
    deleted.add(id);
    throw ApiException(409, 'لا يمكن حذف النوع «فاتورة» لأنه مستخدَم في 3 كتاب صادر. عدّل اسمه بدل حذفه.');
  }

  @override
  Future<List<Company>> companies({bool includeInactive = false}) async => const [];
}
