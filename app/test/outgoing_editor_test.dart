import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';
import 'package:dms_app/core/form_drafts.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/outgoing_editor_screen.dart';
import 'package:dms_app/widgets/book_paper.dart';

/// محرّر الصادر المشترك و«الورقة» (ADR-057 — الدفعة ٦).
void main() {
  Future<_Api> pump(
    WidgetTester tester, {
    OutgoingEditorMode mode = OutgoingEditorMode.create,
    OutgoingDetail? book,
    double width = 1600,
    double height = 1000,
    ThemeData? theme,
    _Api? api,
    _Store? store,
    String? draftId,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = api ?? _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _Session()),
        apiClientProvider.overrideWithValue(a),
        formDraftStoreProvider.overrideWithValue(store ?? _Store()),
      ],
      child: MaterialApp(
        theme: theme ?? ThemeData.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        home: _Launcher(mode: mode, book: book, draftId: draftId),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    return a;
  }

  Future<void> selectEntity(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('entity-field')), 'وزارة');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'وزارة النقل'));   // من القائمة — فتُغلق فوق القالب
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'القالب المعتمد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قالب 2').last);
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, {String subject = 'فاتورة رقم 7', String body = 'نصّ الكتاب'}) async {
    await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), subject);
    final controller = (tester.widget(find.byType(quill.QuillEditor)) as quill.QuillEditor).controller;
    controller.document.insert(0, body);
    await tester.pump();
  }

  group('التخطيط', () {
    for (final w in [1200.0, 1440.0, 1920.0]) {
      for (final dark in [false, true]) {
        testWidgets('ثلاثة أعمدة بلا فيض عند ${w.toInt()} ${dark ? 'ليلاً' : 'نهاراً'}', (tester) async {
          await pump(tester, width: w, theme: dark ? ThemeData.dark() : ThemeData.light());
          expect(tester.takeException(), isNull);
          expect(find.byType(BookPaper), findsOneWidget);
          expect(find.text('خيارات الطباعة'), findsOneWidget);
        });
      }
    }

    for (final w in [760.0, 1000.0]) {
      testWidgets('تبويبان (الورقة · المعاينة) بلا فيض عند ${w.toInt()}', (tester) async {
        await pump(tester, width: w, height: 900);
        expect(tester.takeException(), isNull);
        expect(find.text('الورقة'), findsOneWidget);
        expect(find.text('المعاينة'), findsWidgets);
      });
    }

    testWidgets('📱 الهاتف: «التحرير متاح على الحاسوب» — لا محرّر', (tester) async {
      await pump(tester, width: 390, height: 844);
      expect(find.text('التحرير متاح على الحاسوب'), findsOneWidget);
      expect(find.byType(quill.QuillEditor), findsNothing);
      await tester.tap(find.byKey(const Key('phone-back')));
      await tester.pumpAndSettle();
      expect(find.byType(OutgoingEditorScreen), findsNothing, reason: 'الرجوع بلا اعتراض');
    });
  });

  group('النوع وخيارات الطباعة', () {
    testWidgets('الكتاب الجديد يبدأ بالنوع الأوّل والخيارات الافتراضية — وتُرسَل كلّها', (tester) async {
      final api = await pump(tester);
      await selectEntity(tester);
      await write(tester);
      await tester.tap(find.text('حفظ كمسودة نهائية'));
      await tester.pumpAndSettle();
      final p = api.created!;
      expect(p['outgoingBookTypeId'], 10);
      expect([p['printEntity'], p['printSubject'], p['pageNumbers']], [true, true, true]);
      expect(p['signaturePlacement'], 'LastPage');
      expect(api.createKey, isNotNull, reason: 'مفتاح منع التكرار (ADR-051)');
    });

    testWidgets('إطفاء سطر الجهة يُخفيه من الورقة ويُرسَل — والجهة نفسها تُرسَل', (tester) async {
      final api = await pump(tester);
      await selectEntity(tester);
      await write(tester);
      expect(find.descendant(of: find.byType(BookPaper), matching: find.text('وزارة النقل')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('print-entity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('print-entity')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(BookPaper), matching: find.text('وزارة النقل')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('signature-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signature-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الختم في كل صفحة والتوقيع في الأخيرة').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ كمسودة نهائية'));
      await tester.pumpAndSettle();
      expect(api.created!['printEntity'], false);
      expect(api.created!['entityId'], 1);
      expect(api.created!['signaturePlacement'], 'StampEveryPage');
    });

    testWidgets('الموضوع يظهر على الورقة وهو يُكتب · وإطفاؤه يُخفيه', (tester) async {
      await pump(tester);
      await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), 'فاتورة');
      await tester.pump();
      expect(find.descendant(of: find.byType(BookPaper), matching: find.text('الموضوع / فاتورة')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('print-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('print-subject')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(BookPaper), matching: find.textContaining('الموضوع /')), findsNothing);
    });

    testWidgets('«يُولَّد عند الاعتماد» معزولةٌ داخل سطر No: فلا ينقلب ترتيبها', (tester) async {
      await pump(tester);
      expect(find.descendant(of: find.byType(BookPaper), matching: find.text('No: \u2068يُولَّد عند الاعتماد\u2069')),
          findsOneWidget);
    });

    testWidgets('الأحجام في المتن تُرسَل نقاطاً', (tester) async {
      final api = await pump(tester);
      await selectEntity(tester);
      await write(tester);
      final controller = (tester.widget(find.byType(quill.QuillEditor)) as quill.QuillEditor).controller;
      controller.formatText(0, 3, const quill.SizeAttribute('14'));
      await tester.pump();
      await tester.tap(find.text('حفظ كمسودة نهائية'));
      await tester.pumpAndSettle();
      expect(api.created!['bodyHtml'], contains('font-size: 14pt'));
    });
  });

  group('المعاينة التلقائية', () {
    testWidgets('تتحدّث وحدها بعد توقّف الكتابة — طلبٌ واحد لا طلبٌ لكل حرف', (tester) async {
      final api = await pump(tester);
      await selectEntity(tester);
      await write(tester);
      for (var i = 0; i < 5; i++) {
        await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), 'فاتورة $i');
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(api.previews, 0);
      await tester.pump(OutgoingEditorScreen.previewDebounce);
      await tester.pump();
      expect(api.previews, 1);
    });

    testWidgets('🔐 جهةٌ جديدة لا تُنشأ بالمعاينة التلقائية — زرّ «تحديث» وحده ينشئها', (tester) async {
      final api = await pump(tester);
      await tester.enterText(find.byKey(const Key('entity-field')), 'جهةٌ جديدة تماماً');
      await write(tester);
      await tester.pump(OutgoingEditorScreen.previewDebounce);
      await tester.pump();
      expect(api.entitiesCreated, 0);
      expect(api.previews, 0);
      expect(find.textContaining('جهةٌ جديدة: اضغط «تحديث»'), findsOneWidget);
    });

    testWidgets('طلبٌ أثناء آخر يُصفّ ولا يتزاحم — ثم يُرسَل بآخر المدخلات', (tester) async {
      final api = _Api()..slowFirstPreview = true;
      await pump(tester, api: api);
      await selectEntity(tester);
      await write(tester);
      await tester.pump(OutgoingEditorScreen.previewDebounce);   // الأوّل يبدأ وينتظر
      await tester.pump();
      expect(api.previews, 1);
      await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), 'معدَّل');
      await tester.pump(OutgoingEditorScreen.previewDebounce);   // الثاني يجد الأوّل جارياً ⟵ يُصفّ
      await tester.pump();
      expect(api.previews, 1, reason: 'لا طلبان متزامنان');
      api.release.complete();
      await tester.pump();                                       // الأوّل ينتهي ⟵ المصفوف يُجدوَل
      await tester.pump(OutgoingEditorScreen.previewDebounce);
      await tester.pump();
      expect(api.previews, 2);
      expect(api.lastPreview!['subject'], 'معدَّل');
      expect(tester.takeException(), isNull);
    });
  });

  group('التعديل', () {
    testWidgets('بلا تغيير: الرجوع بلا سؤال', (tester) async {
      await pump(tester, mode: OutgoingEditorMode.editDraft, book: _book());
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(OutgoingEditorScreen), findsNothing);
    });

    testWidgets('الكتاب يُفتح فتظهر معاينته وحدها — بلا انتظار أوّل تعديل', (tester) async {
      final api = await pump(tester, mode: OutgoingEditorMode.editApproved, book: _book(status: 'Final'));
      await tester.pump(OutgoingEditorScreen.previewDebounce);
      await tester.pump();
      expect(api.previews, 1);
      expect(api.lastPreview!['subject'], isNotEmpty);
    });

    testWidgets('بعد تغيير: الرجوع يسأل — «متابعة» تُبقي و«تجاهل» تخرج', (tester) async {
      await pump(tester, mode: OutgoingEditorMode.editDraft, book: _book());
      await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), 'موضوعٌ معدَّل');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('تعديلاتٌ لم تُحفظ'), findsOneWidget);
      await tester.tap(find.text('متابعة التحرير'));
      await tester.pumpAndSettle();
      expect(find.byType(OutgoingEditorScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجاهل التعديلات'));
      await tester.pumpAndSettle();
      expect(find.byType(OutgoingEditorScreen), findsNothing);
    });

    testWidgets('النوع والخيارات تُفتح من الكتاب وتُرسَل كما هي — مع الإصدار والسبب', (tester) async {
      final api = await pump(tester,
          mode: OutgoingEditorMode.editApproved,
          book: _book(status: 'Final', type: 11, printEntity: false, placement: 'EveryPage'));
      await tester.enterText(find.byKey(const Key('change-note')), 'تصحيح');
      await tester.tap(find.text('حفظ كإصدار جديد'));
      await tester.pumpAndSettle();
      final p = api.editedApproved!;
      expect(p['outgoingBookTypeId'], 11);
      expect(p['printEntity'], false);
      expect(p['signaturePlacement'], 'EveryPage');
      expect(p['rowVersion'], 'AAAAAAAAB9E=');
      expect(p['changeNote'], 'تصحيح');
    });

    testWidgets('كتابٌ فيه جدول يُفتح ويُعرض جدولُه على الورقة — ويُحفظ الجدول كما هو', (tester) async {
      final t = BtOps.invoice();
      BtOps.setText(t.rows[1].cells[1]!, 'CAT III Localizer');
      final body = [
        {'insert': 'قبل\n'},
        {'insert': {kDmsTableEmbed: BtJson.toEmbedData(t)}},
        {'insert': 'بعد\n'},
      ];
      final api = await pump(tester, mode: OutgoingEditorMode.editDraft, book: _book(bodyJson: jsonEncode(body)));
      expect(tester.takeException(), isNull);
      expect(find.text('CAT III Localizer'), findsOneWidget);
      expect(find.text('المادة بالإنجليزي'), findsOneWidget);
      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();
      expect(api.updated!['bodyHtml'], contains('data-dms-table'));
      expect(api.updated!['bodyHtml'], contains('CAT III Localizer'));
    });
  });

  group('المسوّدة (ADR-051)', () {
    testWidgets('تحفظ النوع وخيارات الطباعة وتستعيدها', (tester) async {
      final store = _Store();
      await pump(tester, store: store);
      await tester.enterText(find.widgetWithText(TextField, 'موضوع الكتاب'), 'فاتورة');
      await tester.ensureVisible(find.byKey(const Key('page-numbers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-numbers')));
      await tester.pumpAndSettle();
      await tester.pump(kDraftAutosaveEvery + const Duration(milliseconds: 200));
      final d = store.all().single;
      expect(d.fields['pageNumbers'], false);
      expect(d.fields['typeId'], 10);
      expect(d.fields['placement'], 'LastPage');

      // نموذجٌ جديد يعرض المسوّدة للاستعادة — والخيار يعود كما حُفظ
      await tester.pumpWidget(const SizedBox());
      await pump(tester, store: store);
      await tester.tap(find.text('استعادة'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('page-numbers')));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('page-numbers'))).value, isFalse);
      expect(find.widgetWithText(TextField, 'فاتورة'), findsOneWidget);
    });

    testWidgets('مسوّدةٌ تُفتح من «مسوّداتي» تظهر معاينتها وحدها', (tester) async {
      final store = _Store();
      var api = await pump(tester, store: store);
      await selectEntity(tester);
      await write(tester);
      await tester.pump(kDraftAutosaveEvery + const Duration(milliseconds: 200));
      final id = store.all().single.id;

      await tester.pumpWidget(const SizedBox());
      api = await pump(tester, store: store, draftId: id);
      expect(find.widgetWithText(TextField, 'فاتورة رقم 7'), findsOneWidget);
      await tester.pump(OutgoingEditorScreen.previewDebounce);
      await tester.pump();
      expect(api.previews, 1);
      expect(find.textContaining('اضغط «تحديث المعاينة»'), findsNothing, reason: 'البايتات وصلت اللوحة');
    });
  });

  group('القالب', () {
    testWidgets('صور القالب تُطلب للقالب المختار — وتغييره يطلب صوره', (tester) async {
      final api = await pump(tester, mode: OutgoingEditorMode.editDraft, book: _book());
      expect(api.imagesFor, contains(2));
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'القالب المعتمد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('قالب 3').last);
      await tester.pumpAndSettle();
      expect(api.imagesFor, contains(3));
    });
  });
}

/// يفتح المحرّر بزرّ — فيكون للرجوع مكانٌ يعود إليه.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.mode, this.book, this.draftId});
  final OutgoingEditorMode mode;
  final OutgoingDetail? book;
  final String? draftId;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutgoingEditorScreen(mode: mode, book: book, draftId: draftId))),
            child: const Text('افتح'),
          ),
        ),
      );
}

OutgoingDetail _book({
  String status = 'Draft',
  int type = 10,
  bool printEntity = true,
  String placement = 'LastPage',
  String? bodyJson,
}) =>
    OutgoingDetail.fromJson({
      'outgoingId': 9, 'companyId': 1, 'number': status == 'Final' ? 'DEN-2026-00009' : null, 'date': '2026-10-04',
      'entityId': 1, 'entityName': 'وزارة النقل', 'templateId': 2, 'subject': 'فاتورة',
      'bodyHtml': '<p>نص</p>', 'bodyJson': bodyJson ?? '[{"insert":"نص\\n"}]', 'status': status, 'rowVersion': 'AAAAAAAAB9E=',
      'outgoingBookTypeId': type, 'printEntity': printEntity, 'signaturePlacement': placement,
    });

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

TemplateModel _template(int id) => TemplateModel(
    templateId: id, companyId: 1, name: 'قالب $id', watermarkOpacity: 10, marginTop: 24, marginRight: 40,
    marginBottom: 24, marginLeft: 40, pageSize: 'A4', fontFamily: 'Amiri', isActive: true,
    hasHeader: false, hasFooter: false, hasWatermark: false);

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);

  Map<String, dynamic>? created;
  String? createKey;
  Map<String, dynamic>? updated;
  Map<String, dynamic>? editedApproved;
  int previews = 0;
  int entitiesCreated = 0;
  final imagesFor = <int>{};
  bool slowFirstPreview = false;
  final release = Completer<void>();

  @override
  Future<List<EntityModel>> entities() async => [EntityModel(1, 1, 'وزارة النقل', 'Both', null)];
  @override
  Future<List<TemplateModel>> templates() async => [_template(2), _template(3)];
  @override
  Future<List<OutgoingBookTypeModel>> outgoingBookTypes() async =>
      [OutgoingBookTypeModel(10, 1, 'كتاب رسمي'), OutgoingBookTypeModel(11, 1, 'فاتورة')];
  @override
  Future<List<Company>> companies({bool includeInactive = false}) async => const [];
  @override
  Future<Uint8List?> getTemplateImage(int id, String kind) async {
    imagesFor.add(id);
    return null;
  }

  Map<String, dynamic>? lastPreview;

  @override
  Future<Uint8List> previewOutgoing(Map<String, dynamic> body) async {
    previews++;
    lastPreview = body;
    if (slowFirstPreview && previews == 1) await release.future;
    return Uint8List(0);
  }

  @override
  Future<EntityModel> createEntity(String name, String kind, {String? idempotencyKey}) async {
    entitiesCreated++;
    return EntityModel(99, 1, name, kind, null);
  }

  @override
  Future<OutgoingDetail> createOutgoing(Map<String, dynamic> body, {String? idempotencyKey}) async {
    created = body;
    createKey = idempotencyKey;
    return _book();
  }

  @override
  Future<OutgoingDetail> updateOutgoing(int id, Map<String, dynamic> body) async {
    updated = body;
    return _book();
  }

  @override
  Future<OutgoingDetail> editApproved(int id, Map<String, dynamic> body) async {
    editedApproved = body;
    return _book(status: 'Final');
  }
}

/// مخزن مسوّداتٍ في الذاكرة.
class _Store extends FormDraftStore {
  final Map<String, FormDraft> _items = {};
  final ValueNotifier<int> _tick = ValueNotifier(0);
  @override
  bool get isOpen => true;
  @override
  ValueListenable<Object?> listenable() => _tick;
  @override
  List<FormDraft> all() => _items.values.toList();
  @override
  FormDraft? get(String id) => _items[id];
  @override
  Future<FormDraft> put(FormDraft d, {List<DraftFileData>? files}) async {
    _items[d.id] = d;
    _tick.value++;
    return d;
  }

  @override
  Future<List<DraftFileData>> loadFiles(FormDraft d) async => const [];
  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _tick.value++;
  }
}
