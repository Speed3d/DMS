import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/outgoing_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/outgoing_detail_screen.dart';
import 'package:dms_app/screens/outgoing_list_screen.dart';
import 'package:dms_app/widgets/book_pdf_view.dart';
import 'package:dms_app/widgets/outgoing_movements.dart';

/// عرض الصادر (ADR-057 — الدفعة ٨): الكتاب كما يُطبع في التفاصيل · تفاصيل سجلّ الحركة · فلتر النوع · زرّ Word.
void main() {
  late _Api api;

  Future<void> pumpScreen(WidgetTester tester, Widget screen, {double width = 1600, double height = 1000, _Api? custom}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = custom ?? _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _Session()),
        apiClientProvider.overrideWithValue(api),
        outgoingMovementsProvider(9).overrideWith((ref) async => api.movements),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: screen,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('التفاصيل: الكتاب كما يُطبع', () {
    testWidgets('المسودّة: من المعاينة — مع التنبيه · والنصّ المجرّد لم يعُد', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9));
      expect(find.byType(BookPdfView), findsOneWidget);
      expect(find.byKey(const Key('book-pdf-draft-note')), findsOneWidget);
      expect(api.previewCalls, 1);
      expect(api.pdfCalls, 0, reason: 'المسودّة بلا ملفٍّ رسميّ');
      expect(find.text('الكتاب كما يُطبع'), findsOneWidget);
      expect(find.textContaining('نصٌّ قديم'), findsNothing, reason: 'المتن لا يُعرض نصّاً مجرّداً');
      expect(tester.takeException(), isNull);
    });

    testWidgets('المعتمد: من ملفّه المخزَّن (النسخة الرسمية) — لا معاينة', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9), custom: _Api(status: 'Final', hasPdf: true));
      expect(api.pdfCalls, 1);
      expect(api.previewCalls, 0);
      expect(find.byKey(const Key('book-pdf-draft-note')), findsNothing);
    });

    testWidgets('معتمدٌ بلا ملفّ: يُقال ذلك لا عارضٌ فارغ', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9), custom: _Api(status: 'Final', hasPdf: false));
      expect(find.byType(BookPdfView), findsNothing);
      expect(find.text('لا ملفّ PDF محفوظاً لهذا الكتاب.'), findsOneWidget);
    });

    testWidgets('فشل الجلب: رسالة الخادم وزرّ «إعادة المحاولة» يجلب ثانيةً', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9), custom: _Api(failPreview: true));
      expect(find.byKey(const Key('book-pdf-error')), findsOneWidget);
      expect(find.text('القالب غير موجود'), findsOneWidget);
      api.failPreview = false;
      await tester.tap(find.byKey(const Key('book-pdf-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.previewCalls, 2);
      expect(find.byKey(const Key('book-pdf-error')), findsNothing);
    });

    testWidgets('النوع وخيارات الطباعة في المعلومات · وزرّ Word ظاهرٌ للمسودّة (قرار المالك ت١٤)', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9));
      expect(find.text('نوع الكتاب'), findsOneWidget);
      expect(find.text('فاتورة'), findsOneWidget);
      expect(find.text('التوقيع والختم في الصفحة الأخيرة وحدها · بلا ترقيم صفحات · بلا سطر الجهة'), findsOneWidget);
      expect(find.text('تصدير Word'), findsOneWidget);
    });

    testWidgets('وزرّ Word للمعتمد كذلك', (tester) async {
      await pumpScreen(tester, const OutgoingDetailScreen(id: 9), custom: _Api(status: 'Final', hasPdf: true));
      expect(find.text('تصدير Word'), findsOneWidget);
    });

    for (final w in [390.0, 800.0, 1280.0, 1920.0]) {
      testWidgets('بلا فيضٍ عند ${w.toInt()} — والضيّق عمودٌ واحد (الهاتف للعرض والاعتماد)', (tester) async {
        await pumpScreen(tester, const OutgoingDetailScreen(id: 9), width: w, height: 900);
        expect(tester.takeException(), isNull);
        final info = tester.getTopLeft(find.text('المعلومات الأساسية'));
        final book = tester.getTopLeft(find.text('الكتاب كما يُطبع'));
        if (w < 900) {
          expect(book.dy, greaterThan(info.dy), reason: 'الكتاب تحت المعلومات');
        } else {
          expect((book.dy - info.dy).abs(), lessThan(20), reason: 'عمودان متجاوران');
        }
      });
    }
  });

  group('سجلّ الحركة: التفاصيل قابلةٌ للطيّ', () {
    testWidgets('مطويّةٌ افتراضاً بعددها — وتُفتح بالقديم والجديد وتُطوى', (tester) async {
      await pumpScreen(tester, const Scaffold(body: SingleChildScrollView(child: OutgoingMovementsSection(outgoingId: 9))));
      await tester.pump();
      expect(find.text('التفاصيل (3)'), findsOneWidget);
      expect(find.textContaining('1,000 ⟵ 1,250'), findsNothing);
      await tester.tap(find.byKey(const Key('movement-details-2')));
      await tester.pump();
      expect(find.textContaining('البند 3 — السعر الكلي: 1,000 ⟵ 1,250'), findsOneWidget);
      expect(find.textContaining('و4 غيرها'), findsOneWidget);
      await tester.tap(find.byKey(const Key('movement-details-2')));
      await tester.pump();
      expect(find.textContaining('1,000 ⟵ 1,250'), findsNothing);
      expect(find.byKey(const Key('movement-details-1')), findsNothing, reason: 'حركةٌ بلا تفاصيل بلا زرّ');
    });
  });

  group('القائمة: فلتر النوع', () {
    testWidgets('الأنواع من الخادم ⟵ اختيارُ نوعٍ يُرسَل للخادم · والنوع تحت الموضوع', (tester) async {
      await pumpScreen(tester, const OutgoingListScreen());
      expect(find.byKey(const Key('outgoing-type-filter')), findsOneWidget);
      expect(find.text('عرض سعر'), findsOneWidget, reason: 'النوع تحت موضوع الكتاب');
      await tester.tap(find.byKey(const Key('outgoing-type-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فاتورة').last);
      await tester.pumpAndSettle();
      expect(api.lastTypeId, 11);
    });

    testWidgets('الأنواع لم تصل (خادمٌ أقدم): لا فلتر — والقائمة تعمل', (tester) async {
      await pumpScreen(tester, const OutgoingListScreen(), custom: _Api(failTypes: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outgoing-type-filter')), findsNothing);
      expect(find.text('عرض سعر لمحطة'), findsOneWidget);
    });

    for (final w in [420.0, 700.0, 1400.0]) {
      testWidgets('شريط الأدوات بلا فيضٍ عند ${w.toInt()} ومعه فلتر النوع', (tester) async {
        await pumpScreen(tester, const OutgoingListScreen(), width: w, height: 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('outgoing-type-filter')), findsOneWidget);
      });
    }
  });
}

class _Session extends SessionNotifier {
  @override
  SessionState build() => SessionState(
        loaded: true,
        activeCompanyId: 1,
        auth: AuthResult(
          accessToken: 't', accessExpires: DateTime.now().add(const Duration(hours: 1)), refreshToken: 'r',
          userId: 1, fullName: 'مدير', username: 'admin', role: 'Manager', companyIds: const [1],
          mustChangePassword: false, companies: const [],
        ),
      );
}

class _Api extends ApiClient {
  _Api({this.status = 'Draft', this.hasPdf = false, this.failPreview = false, this.failTypes = false})
      : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);

  final String status;
  final bool hasPdf;
  bool failPreview;
  final bool failTypes;
  int previewCalls = 0;
  int pdfCalls = 0;
  int? lastTypeId;

  final movements = [
    OutgoingMovementItem(
        movementId: 1, action: 'Created', description: 'إنشاء مسودّة', performedByUserName: 'أحمد', performedAt: DateTime.utc(2026, 10, 4, 7)),
    OutgoingMovementItem(
      movementId: 2,
      action: 'Edited',
      description: 'تعديل المسودّة: الجداول',
      performedByUserName: 'أحمد',
      performedAt: DateTime.utc(2026, 10, 4, 8),
      details: 'الجدول: أُضيف صفّ · تغيّرت 5 خلايا\nالبند 3 — السعر الكلي: 1,000 ⟵ 1,250\nو4 غيرها',
    ),
  ];

  @override
  Future<OutgoingDetail> outgoingGet(int id) async => OutgoingDetail.fromJson({
        'outgoingId': 9, 'companyId': 1, 'number': status == 'Final' ? 'DEN-2026-00009' : null, 'date': '2026-10-04',
        'entityId': 1, 'entityName': 'وزارة النقل', 'templateId': 2, 'subject': 'فاتورة رقم 7',
        'bodyHtml': '<p>نصٌّ قديم</p>', 'status': status, 'rowVersion': 'AAAAAAAAB9E=', 'hasPdf': hasPdf,
        'outgoingBookTypeId': 11, 'outgoingBookTypeName': 'فاتورة', 'printEntity': false, 'pageNumbers': false,
        'signaturePlacement': 'LastPage', 'canApprove': true,
      });

  @override
  Future<Uint8List> previewDraftPdf(int id) async {
    previewCalls++;
    if (failPreview) throw ApiException(400, 'القالب غير موجود');
    return Uint8List(0);
  }

  @override
  Future<Uint8List> outgoingPdf(int id) async {
    pdfCalls++;
    return Uint8List(0);
  }

  @override
  Future<List<OutgoingMovementItem>> outgoingMovements(int id) async => movements;

  @override
  Future<CaseFileDetail?> caseFileRelated(CaseMemberKind kind, int bookId) async => null;

  @override
  Future<List<OutgoingBookTypeModel>> outgoingBookTypes() async {
    if (failTypes) throw ApiException(404, 'غير موجود');
    return [OutgoingBookTypeModel(10, 1, 'كتاب رسمي'), OutgoingBookTypeModel(11, 1, 'فاتورة'), OutgoingBookTypeModel(12, 1, 'عرض سعر')];
  }

  @override
  Future<List<OutgoingListItem>> outgoingList({String? status, String? search, int? typeId}) async {
    lastTypeId = typeId;
    return [
      OutgoingListItem.fromJson({
        'outgoingId': 9, 'number': null, 'date': '2026-10-04', 'subject': 'عرض سعر لمحطة', 'entityName': 'وزارة النقل',
        'status': 'Draft', 'outgoingBookTypeId': 12, 'outgoingBookTypeName': 'عرض سعر',
      }),
    ];
  }
}
