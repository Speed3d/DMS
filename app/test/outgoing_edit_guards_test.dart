import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/outgoing_edit_approved_screen.dart';
import 'package:dms_app/screens/outgoing_edit_draft_screen.dart';

/// الدفعة ١ (0.11.1) — حرّاس شاشتَي تعديل الصادر:
/// (١) قالبٌ عُطِّل بعد الحفظ كان يُسقط الشاشة (قيمة المنسدلة ليست في عناصرها).
/// (٢) «سبب التعديل» بعد الاعتماد كان مُعرَّفاً ويُرسَل فارغاً دائماً لأنه لم يُعرض قطّ.
class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);

  Map<String, dynamic>? sentEditApproved;
  Map<String, dynamic>? sentUpdate;

  @override
  Future<List<EntityModel>> entities() async => [EntityModel(1, 1, 'وزارة النقل', 'Both', null)];

  @override
  Future<List<TemplateModel>> templates() async => [_template(2, true), _template(5, false)];

  // ADR-057: المحرّر المشترك يطلب الأنواع وصور القالب والمعاينة — والشبكة الحقيقية لا تكتمل داخل الاختبار.
  @override
  Future<List<OutgoingBookTypeModel>> outgoingBookTypes() async => [OutgoingBookTypeModel(1, 1, 'كتاب رسمي')];

  @override
  Future<Uint8List?> getTemplateImage(int id, String kind) async => null;

  @override
  Future<Uint8List> previewOutgoing(Map<String, dynamic> body) async => Uint8List(0);

  @override
  Future<OutgoingDetail> editApproved(int id, Map<String, dynamic> body) async {
    sentEditApproved = body;
    return _book(templateId: 2);
  }

  @override
  Future<OutgoingDetail> updateOutgoing(int id, Map<String, dynamic> body) async {
    sentUpdate = body;
    return _book(templateId: 2);
  }
}

TemplateModel _template(int id, bool active) => TemplateModel(
    templateId: id, companyId: 1, name: 'قالب $id', watermarkOpacity: 10, marginTop: 24, marginRight: 40,
    marginBottom: 24, marginLeft: 40, pageSize: 'A4', fontFamily: 'Amiri', isActive: active,
    hasHeader: false, hasFooter: false, hasWatermark: false);

OutgoingDetail _book({required int templateId, String status = 'Final'}) => OutgoingDetail.fromJson({
      'outgoingId': 9, 'companyId': 1, 'number': 'DEN-2026-00009', 'date': '2026-09-29', 'entityId': 1,
      'entityName': 'وزارة النقل', 'templateId': templateId, 'subject': 'فاتورة', 'bodyHtml': '<p>نص</p>',
      'bodyJson': '[{"insert":"نص\\n"}]', 'status': status, 'rowVersion': 'AAAAAAAAB9E=',
    });

Future<_FakeApi> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        quill.FlutterQuillLocalizations.delegate,
      ],
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('التعديل بعد الاعتماد: قالبٌ معطَّل لا يُسقط الشاشة — ويُطلب اختيار قالبٍ بدل إرسال المعطَّل',
      (tester) async {
    final api = await _pump(tester, OutgoingEditApprovedScreen(book: _book(templateId: 5)));
    expect(tester.takeException(), isNull);
    expect(find.text('قالب 5'), findsNothing, reason: 'المعطَّل ليس بين الخيارات');

    await tester.tap(find.text('حفظ كإصدار جديد'));
    await tester.pumpAndSettle();
    expect(api.sentEditApproved, isNull, reason: 'لا يُرسَل معرّف قالبٍ يرفضه الخادم');
    expect(find.textContaining('اختر القالب'), findsOneWidget);
  });

  testWidgets('تعديل المسودّة: قالبٌ معطَّل لا يُسقط الشاشة', (tester) async {
    final api = await _pump(tester, OutgoingEditDraftScreen(book: _book(templateId: 5, status: 'Draft')));
    expect(tester.takeException(), isNull);
    expect(api.sentUpdate, isNull);
  });

  testWidgets('«سبب التعديل» ظاهرٌ ويُرسَل مع الإصدار الجديد', (tester) async {
    final api = await _pump(tester, OutgoingEditApprovedScreen(book: _book(templateId: 2)));
    final note = find.byKey(const Key('change-note'));
    expect(note, findsOneWidget);

    await tester.enterText(note, '  تصحيح الكمية في البند 3  ');
    await tester.tap(find.text('حفظ كإصدار جديد'));
    await tester.pumpAndSettle();
    expect(api.sentEditApproved?['changeNote'], 'تصحيح الكمية في البند 3');
    expect(api.sentEditApproved?['templateId'], 2);
  });

  testWidgets('بلا سببٍ مكتوب يُرسَل null لا نصٌّ فارغ', (tester) async {
    final api = await _pump(tester, OutgoingEditApprovedScreen(book: _book(templateId: 2)));
    await tester.tap(find.text('حفظ كإصدار جديد'));
    await tester.pumpAndSettle();
    expect(api.sentEditApproved, isNotNull);
    expect(api.sentEditApproved!['changeNote'], isNull);
  });
}
