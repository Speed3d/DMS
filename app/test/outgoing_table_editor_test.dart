import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';
import 'package:dms_app/core/form_drafts.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/outgoing_editor_screen.dart';
import 'package:dms_app/widgets/book_table/bt_editor_hub.dart';
import 'package:dms_app/widgets/book_table/bt_table_editor.dart';

/// محرّر الجدول داخل «الورقة» (ADR-057 — الدفعة ٧): **تفاعلٌ حقيقيّ على الشاشة** لا نداءُ دوالّ.
///
/// 🔴 أوّل ما يحرسه **عيبُ تجربة الدفعة ٠**: النقر على خليةٍ ثم `Ctrl+A` **مسح المستند كلَّه** لأن المحرّر الرئيسيّ استردّ
/// التركيز. وبعده: ما كُتب ولم يُغادَر يُحفظ · Tab يتنقّل ويُضيف بنداً · الجمع حيّ · الحروف من الخادم · التراجع خطوةٌ لكل عملية.
void main() {
  late _Api api;

  Future<void> wait(WidgetTester t, [int ms = 50]) async {
    await t.pump(Duration(milliseconds: ms));
    await t.pump();
  }

  Future<void> pump(WidgetTester tester, {OutgoingEditorMode mode = OutgoingEditorMode.editDraft, String? body, _Store? store}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _Session()),
        apiClientProvider.overrideWithValue(api),
        formDraftStoreProvider.overrideWithValue(store ?? _Store()),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        home: _Launcher(mode: mode, book: mode == OutgoingEditorMode.create ? null : _book(bodyJson: body ?? invoiceBody())),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
  }

  BtEditorHub hubOf(WidgetTester t) => t.widget<BtTableEditor>(find.byType(BtTableEditor).first).hub;

  /// الجدول كما هو **في المستند** (لا الخلية المفتوحة).
  BtTable stored(BtEditorHub h, [int index = 0]) {
    final ops = h.main.document.toDelta().toList().where((op) => op.data is Map && (op.data as Map).containsKey(kDmsTableEmbed)).toList();
    return BtJson.fromEmbedData((ops[index].data as Map)[kDmsTableEmbed]);
  }

  FocusNode mainFocus(WidgetTester t) => t.widget<quill.QuillEditor>(find.byType(quill.QuillEditor).first).focusNode;

  Future<void> tapCell(WidgetTester t, int r, int c, {bool shift = false}) async {
    final f = find.byKey(ValueKey('bt-cell-$r-$c'));
    await t.ensureVisible(f);
    await t.pump();
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(f);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    // مؤقّت «النقر المزدوج» في Quill (300 ملّيثانية) — ينتهي قبل الخطوة التالية
    await wait(t, 350);
  }

  /// كتابةٌ في الخلية المفتوحة (عند المؤشّر) — ثم انتظار الجمع الحيّ.
  Future<void> type(WidgetTester t, String text) async {
    final c = hubOf(t).cell!;
    final at = c.selection;
    c.replaceText(at.start, at.end - at.start, text, TextSelection.collapsed(offset: at.start + text.length));
    await wait(t, 200);
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey k, {bool ctrl = false, bool shift = false}) async {
    if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(k);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await wait(t);
  }

  void clipboard(String text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }

  group('الإدراج والتركيز', () {
    testWidgets('«جدول» ⟵ الشبكة ⟵ يُدرج عند المؤشّر وتُفتح خليته الأولى للكتابة', (tester) async {
      await pump(tester, mode: OutgoingEditorMode.create);
      await tester.tap(find.byKey(const Key('insert-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bt-pick-2-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('bt-insert-ok')));
      await wait(tester);
      final h = hubOf(tester);
      final t = stored(h);
      expect([t.rowCount, t.colCount, t.headerRows], [2, 3, 1]);
      expect(find.byKey(const Key('bt-toolbar')), findsOneWidget);
      expect(h.editing, isTrue);
      expect(h.cellFocus!.hasFocus, isTrue, reason: 'الكتابة تبدأ فوراً');
      expect(tester.takeException(), isNull);
    });

    testWidgets('جدولٌ في آخر الكتاب يُدرج ومعه سطرٌ فارغ بعده — فيُكتب بعده (كما في Word)', (tester) async {
      await pump(tester, mode: OutgoingEditorMode.create);
      await tester.tap(find.byKey(const Key('insert-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bt-insert-ok')));
      await wait(tester);
      final h = hubOf(tester);
      final ops = h.main.document.toDelta().toJson();
      final i = ops.indexWhere((op) => op['insert'] is Map);
      expect(i, greaterThanOrEqualTo(0));
      final after = ops.sublist(i + 1).map((op) => op['insert']).join();
      expect(after, '\n\n', reason: 'سطر البلوك ثم فقرةٌ فارغة بعده');
      // وجدولٌ يُدرج وسط نصٍّ لا يُضاف بعده شيء
      h.exit();
      h.main.replaceText(0, 0, 'قبل', const TextSelection.collapsed(offset: 1));
      await wait(tester);
      final len = h.main.document.length;
      h.insertTable(BtOps.blank(2, 2));
      await wait(tester);
      expect(h.main.document.length, len + 1, reason: 'البلوك وحده — النصّ بعده يكفي');
    });

    testWidgets('كتابٌ محفوظٌ ينتهي بجدول: Esc يُخرج إلى سطرٍ جديد بعده — والمتن صاحب التركيز', (tester) async {
      final body = jsonEncode([
        {'insert': 'قبل الجدول\n'},
        {
          'insert': {kDmsTableEmbed: BtJson.toEmbedData(BtOps.invoice())}
        },
        {'insert': '\n'},
      ]);
      await pump(tester, body: body);
      final h = hubOf(tester);
      final len = h.main.document.length;
      await tapCell(tester, 1, 1);
      await key(tester, LogicalKeyboardKey.escape);   // الخلية ⟵ التحديد
      await key(tester, LogicalKeyboardKey.escape);   // التحديد ⟵ النصّ
      expect(h.active, isFalse);
      expect(h.main.document.length, len + 1, reason: 'سطرٌ جديد بعد الجدول');
      expect(mainFocus(tester).hasPrimaryFocus, isTrue);
      expect(h.main.selection.baseOffset, 'قبل الجدول\n'.length + 2, reason: 'المؤشّر في السطر الجديد');
      h.main.replaceText(h.main.selection.baseOffset, 0, 'بعد', null);
      expect(h.main.document.toPlainText().endsWith('بعد\n'), isTrue);
    });

    testWidgets('🔴 النقر على خلية يُبقي التركيز فيها — وCtrl+A يحدّد نصّ الخلية لا المستند (عيب الدفعة ٠)', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'جهاز اللوكلايزر');
      expect(h.cellFocus!.hasFocus, isTrue);
      expect(mainFocus(tester).hasPrimaryFocus, isFalse, reason: 'المحرّر الرئيسيّ لا يستردّ التركيز');
      final mainSel = h.main.selection;
      await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
      expect(h.cell!.selection.start, 0);
      expect(h.cell!.selection.end, 'جهاز اللوكلايزر'.length, reason: 'التحديد داخل الخلية');
      expect(h.main.selection, mainSel, reason: 'المستند لم يُحدَّد كلُّه');
      await type(tester, 'بديل');
      expect(h.main.document.toPlainText(), contains('قبل الجدول'), reason: 'النصّ خارج الجدول باقٍ');
      expect(h.current(stored(h)).rows[1].cells[1]!.text, 'بديل');
    });

    testWidgets('🔴 Backspace وCtrl+Z داخل الخلية للخلية وحدها — لا يمسّان المتن (محرّرٌ داخل محرّر)', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      final mainText = h.main.document.toPlainText();
      final mainLen = h.main.document.length;
      await tapCell(tester, 1, 1);
      await type(tester, 'أبجد');
      await key(tester, LogicalKeyboardKey.backspace);
      expect(h.cell!.document.toPlainText().trim(), 'أبج', reason: 'الحذف في الخلية');
      expect(h.main.document.toPlainText(), mainText, reason: 'المتن لم يُحذف منه حرف');
      expect(h.main.document.length, mainLen);
      // Quill يجمع خطوات التراجع بالساعة الحقيقية (لا تتقدّم في الاختبار) ⟵ خطوةٌ جديدة صراحةً، كمن توقّف ثم كتب
      h.cell!.document.history.lastRecorded = 0;
      await type(tester, 'هـ');
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(h.cell!.document.toPlainText().trim(), 'أبج', reason: 'التراجع في الخلية');
      expect(h.main.document.toPlainText(), mainText, reason: 'لا تراجع في المتن');
      expect(stored(h).rows[1].cells[1]!.text, isEmpty, reason: 'الخلية لم تُغادَر بعد');
    });

    testWidgets('🔴 المتن مُركَّزٌ ثم نقرٌ على خلية ⟵ التركيز للخلية، وCtrl+A وBackspace لا يمسحان المتن', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      final mainText = h.main.document.toPlainText();
      h.main.updateSelection(const TextSelection.collapsed(offset: 2), quill.ChangeSource.local);
      mainFocus(tester).requestFocus();
      await wait(tester);
      expect(mainFocus(tester).hasPrimaryFocus, isTrue);
      await tapCell(tester, 2, 5);
      expect(h.editing, isTrue);
      expect(h.cellFocus!.hasPrimaryFocus, isTrue, reason: 'المتن لا يحتفظ بالتركيز بعد النقر على خلية');
      expect(mainFocus(tester).hasPrimaryFocus, isFalse);
      await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(h.main.document.toPlainText(), mainText, reason: 'المتن كما هو');
      expect(h.tableCount, 1);
    });

    testWidgets('النقر في المتن يُغادر الجدول ويحفظ الخلية', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'نصٌّ في الخلية');
      mainFocus(tester).requestFocus();   // بعد نافذة الاسترداد (إطاران) — كنقرةٍ في المتن
      await wait(tester);
      expect(h.active, isFalse);
      expect(stored(h).rows[1].cells[1]!.text, 'نصٌّ في الخلية');
      expect(find.byKey(const Key('bt-toolbar')), findsNothing);
    });

    testWidgets('خلية الجمع لا تُكتب — تُحدَّد فقط', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 4, 2);
      expect(h.active, isTrue);
      expect(h.editing, isFalse);
      expect(h.headSlot!.cell.formula, isNotNull);
    });
  });

  group('ما يُكتب لا يضيع', () {
    testWidgets('خليةٌ لم تُغادَر تُرسَل مع الحفظ — في HTML الطباعة وفي Delta التحرير', (tester) async {
      await pump(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'CAT III Localizer');
      await tester.tap(find.text('حفظ التعديلات'));
      await wait(tester, 100);
      final body = api.updated!;
      expect(body['bodyHtml'], contains('data-dms-table'));
      expect(body['bodyHtml'], contains('CAT III Localizer'));
      expect(body['bodyJson'], contains('CAT III Localizer'));
    });

    testWidgets('المسوّدة تحفظ الجدول بما في الخلية المفتوحة', (tester) async {
      final store = _Store();
      await pump(tester, mode: OutgoingEditorMode.create, store: store);
      await tester.tap(find.byKey(const Key('insert-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bt-insert-invoice')));
      await wait(tester);
      await type(tester, 'ت');   // الخلية الأولى (عنوانٌ موجود) — يُضاف إليه
      await tapCell(tester, 1, 1);
      await type(tester, 'مادةٌ في المسوّدة');
      await tester.pump(kDraftAutosaveEvery + const Duration(milliseconds: 300));
      await tester.pump();
      expect(jsonEncode(store.all().single.fields['body']), contains('مادةٌ في المسوّدة'));
    });

    testWidgets('الرابط والتظليل لا يصلان الخادم — يُنقّيان عند الحفظ', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'رابط');
      h.cell!.formatText(0, 4, const quill.LinkAttribute('https://example.com'));
      h.cell!.formatText(0, 4, const quill.BackgroundAttribute('#ffff00'));
      h.cell!.formatText(0, 4, quill.Attribute.bold);
      await key(tester, LogicalKeyboardKey.tab);
      final cell = stored(h).rows[1].cells[1]!;
      expect(jsonEncode(cell.delta), isNot(contains('link')));
      expect(jsonEncode(cell.delta), isNot(contains('background')));
      expect(cell.inlineStyle?['bold'], isTrue, reason: 'العريض يُطبع فيبقى');
    });
  });

  group('التنقّل', () {
    testWidgets('Tab يحفظ الخلية وينتقل — وShift+Tab يعود إليها بنصّها', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'جهاز');
      await key(tester, LogicalKeyboardKey.tab);
      expect([h.sel!.hr, h.sel!.hc], [1, 2]);
      expect(stored(h).rows[1].cells[1]!.text, 'جهاز', reason: 'حُفظ في المستند');
      expect(h.cellFocus!.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      expect([h.sel!.hr, h.sel!.hc], [1, 1]);
      expect(h.cell!.document.toPlainText().trim(), 'جهاز');
    });

    testWidgets('🔴 Tab ثم كتابةٌ فوراً: المحرّر نفسه ينتقل بتركيزه — فلا يضيع حرف (كشفه المتصفّح)', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      final editor = h.cell, focus = h.cellFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);   // بلا أيّ إطارٍ بعده
      expect(identical(h.cell, editor), isTrue, reason: 'لا محرّرَ جديد ⟵ لا فجوة بين Tab والكتابة');
      expect(identical(h.cellFocus, focus), isTrue);
      expect(focus!.hasPrimaryFocus, isTrue, reason: 'التركيز لم يغادر لحظةً');
      editor!.replaceText(0, 0, 'فوري', const TextSelection.collapsed(offset: 4));   // كأنّ الحروف وصلت قبل الإطار التالي
      await wait(tester);
      expect([h.sel!.hr, h.sel!.hc], [1, 2]);
      expect(h.current(stored(h)).rows[1].cells[2]!.text, 'فوري', reason: 'وقعت في الخلية الجديدة');
      expect(stored(h).rows[1].cells[1]!.text, isEmpty, reason: 'لا في القديمة');
    });

    testWidgets('الجدول يُرسم من المستند — ما حُفظ بخليةٍ يظهر في الجمع ولو لم يُعِد Quill بناء المتن', (tester) async {
      await pump(tester);
      await tapCell(tester, 1, 5);
      await type(tester, '700');
      await tapCell(tester, 2, 5);   // حفظٌ بلا تركيزٍ للمتن ⟵ Quill لا يعيد البناء
      await type(tester, '300');
      final texts = find.descendant(of: find.byKey(const ValueKey('bt-cell-4-2')), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data);
      expect(texts, contains('1,000'));
    });

    testWidgets('Tab من آخر بندٍ قبل المجموع يُضيف بنداً مرقَّماً — والكتابة في الخلية التي بعد الترقيم', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 3, 5);
      await key(tester, LogicalKeyboardKey.tab);
      final t = stored(h);
      expect(t.rowCount, 6);
      expect(t.rows[4].cells[0]!.text, '4');
      expect(t.rows.last.cells[2]!.formula, isNotNull, reason: 'المجموع آخراً');
      expect([h.sel!.hr, h.sel!.hc], [4, 1]);
      expect(h.editing, isTrue);
    });

    testWidgets('Esc ⟵ تحديدٌ بلا كتابة · الأسهم تتنقّل (العربيّ: اليسار = التالي) · Esc ثانيةً يُغادر', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await key(tester, LogicalKeyboardKey.escape);
      expect(h.editing, isFalse);
      expect(h.tableFocus.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect([h.sel!.hr, h.sel!.hc], [1, 2]);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect([h.sel!.hr, h.sel!.hc], [2, 2]);
      await key(tester, LogicalKeyboardKey.escape);
      expect(h.active, isFalse);
    });

    testWidgets('حرفٌ يُكتب على خليةٍ محدّدة يفتحها به (كما في Excel)', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 3);
      await type(tester, '5');
      await key(tester, LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7, character: '7');
      await wait(tester);
      expect(h.editing, isTrue);
      expect(h.cell!.document.toPlainText().trim(), '7', reason: 'بدل نصّها');
    });
  });

  group('الجمع والحروف', () {
    testWidgets('Σ يتحدّث وأنت تكتب — قبل مغادرة الخلية · والحروف من الخادم', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 5);
      await type(tester, '1,000');
      await key(tester, LogicalKeyboardKey.tab);
      await wait(tester, 500);
      final before = api.wordsCalls;
      await tapCell(tester, 2, 5);
      for (final ch in '2,500'.split('')) {
        final c = hubOf(tester).cell!;
        c.replaceText(c.selection.start, 0, ch, TextSelection.collapsed(offset: c.selection.start + 1));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await wait(tester, 200);
      expect(find.text('3,500'), findsOneWidget, reason: 'الخلية لم تُغادَر بعد والجمع يراها');
      await wait(tester, 500);   // التفقيط بعد توقّفٍ قصير
      expect(find.text('نصّ 3500 IQD'), findsOneWidget);
      expect(api.wordsCalls - before, 1, reason: 'خمسة أحرفٍ ⟵ طلبٌ واحد لا خمسة');
      expect(h.editing, isTrue);
    });

    testWidgets('زرّ Σ: نافذةٌ لاختيار العمود ⟵ جمعٌ حيّ', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 2, 4);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const Key('bt-sum')));
      await tester.pumpAndSettle();
      expect(find.text('جمعٌ حيّ (Σ)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bt-sum-ok')));
      await wait(tester);
      expect(stored(h).rows[2].cells[4]!.formula?.col, 4);
    });

    testWidgets('«المبلغ كتابةً» يُزال من خلية الحروف — بنافذة تأكيد', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 4, 4);
      await tester.tap(find.byKey(const Key('bt-words')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bt-choose-remove')));
      await wait(tester);
      expect(stored(h).rows[4].cells[4]!.words, isNull);
    });
  });

  group('شريط الجدول والتراجع', () {
    testWidgets('«صفٌّ تحت» ثم Ctrl+Z يتراجع عنه وحده — والمكتوب قبله يبقى · وCtrl+Y يعيده', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await type(tester, 'باقٍ');
      await tester.tap(find.byKey(const Key('bt-row-below')));
      await wait(tester);
      expect(stored(h).rowCount, 6);
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(stored(h).rowCount, 5);
      expect(stored(h).rows[1].cells[1]!.text, 'باقٍ', reason: 'حفظ الخلية خطوةٌ مستقلّة');
      await key(tester, LogicalKeyboardKey.keyY, ctrl: true);
      expect(stored(h).rowCount, 6);
    });

    testWidgets('Shift+نقر يحدّد خليتين ⟵ دمج ⟵ فكّ — والبنية سليمة بقاعدة الخادم', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await tapCell(tester, 1, 2, shift: true);
      expect([h.sel!.left, h.sel!.right], [1, 2]);
      await tester.tap(find.byKey(const Key('bt-merge')));
      await wait(tester);
      var t = stored(h);
      expect(t.rows[1].cells[1]!.colSpan, 2);
      expect(BtOps.validate(t), isNull);
      await tester.tap(find.byKey(const Key('bt-unmerge')));
      await wait(tester);
      t = stored(h);
      expect(t.rows[1].cells[1]!.colSpan, 1);
      expect(BtOps.validate(t), isNull);
    });

    testWidgets('عريضٌ لعدّة خلايا محدّدة — وضغطةٌ ثانية تُزيله', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 4);
      await type(tester, '10');
      await tapCell(tester, 2, 4);
      await type(tester, '20');
      await tapCell(tester, 1, 4, shift: true);
      await tester.tap(find.byKey(const Key('bt-bold')));
      await wait(tester);
      // خلايا البنود في الفاتورة عريضةٌ أصلاً ⟵ الضغطة تُزيله عن الكلّ
      expect(stored(h).rows[1].cells[4]!.inlineStyle?['bold'], isNull);
      expect(stored(h).rows[2].cells[4]!.inlineStyle?['bold'], isNull);
      await tester.tap(find.byKey(const Key('bt-bold')));
      await wait(tester);
      expect(stored(h).rows[2].cells[4]!.inlineStyle?['bold'], isTrue);
    });

    testWidgets('سحب حدّ العمود يغيّر العرضين المتجاورين وحدهما — ويُكتب مرّةً عند الإفلات', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      final before = [for (final c in stored(h).cols) c.weight];
      final share0 = before[1] / before.reduce((a, b) => a + b);
      await tester.drag(find.byKey(const ValueKey('bt-col-edge-1')), const Offset(-40, 0));
      await wait(tester);
      final after = [for (final c in stored(h).cols) c.weight];
      final total = after.reduce((a, b) => a + b);
      // في الجدول العربيّ الحدّ 1 بين العمود 1 (يمينه) والعمود 2 — السحب يساراً يوسّع العمود 1
      expect(after[1] / total, greaterThan(share0));
      expect(after[0] / total, closeTo(before[0] / before.reduce((a, b) => a + b), 1e-9), reason: 'عمودٌ بعيدٌ لم يُمسّ');
    });

    testWidgets('حذف الجدول بتأكيد — ويعود بالتراجع', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      await tester.tap(find.byKey(const Key('bt-delete-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bt-delete-table-ok')));
      await wait(tester);
      expect(h.tableCount, 0);
      expect(find.byKey(const Key('bt-toolbar')), findsNothing);
      h.main.undo();
      await wait(tester);
      expect(h.tableCount, 1);
    });
  });

  group('اللصق', () {
    testWidgets('لصق جدولٍ من Excel في خلية: يملأ من هنا ويُدرج قبل المجموع', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      clipboard('أ\t1\nب\t2\nج\t3\nد\t4\n');
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await wait(tester, 100);
      final t = stored(h);
      expect(t.rowCount, 6, reason: 'أربعة بنودٍ في ثلاثة صفوف ⟵ صفٌّ قبل المجموع');
      expect([for (var r = 1; r <= 4; r++) t.rows[r].cells[1]!.text], ['أ', 'ب', 'ج', 'د']);
      expect(t.rows[4].cells[2]!.text, '4');
      expect(t.rows.last.cells[2]!.formula, isNotNull);
      expect(BtOps.validate(t), isNull);
    });

    testWidgets('لصق نصٍّ عاديّ في خلية: نصّاً خالصاً عند المؤشّر', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      await tapCell(tester, 1, 1);
      clipboard('نصٌّ ملصوق');
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await wait(tester, 100);
      expect(h.cell!.document.toPlainText().trim(), 'نصٌّ ملصوق');
      expect(stored(h).rowCount, 5);
    });

    testWidgets('لصق جدولٍ في المتن يسأل «إدراجه جدولاً؟» ⟵ جدولٌ ثانٍ', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      h.main.updateSelection(const TextSelection.collapsed(offset: 3), quill.ChangeSource.local);
      mainFocus(tester).requestFocus();
      await wait(tester);
      clipboard('البند\tالمبلغ\nأ\t1,000\n');
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      expect(find.text('لصق جدول'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bt-paste-as-table')));
      await wait(tester);
      expect(h.tableCount, 2);
      expect(stored(h).rows[1].cells[1]!.text, '1,000');
    });

    testWidgets('لصق نصّاً عاديّاً في المتن: يُدرج مرّةً واحدة — بلا سؤالٍ ثانٍ', (tester) async {
      await pump(tester);
      final h = hubOf(tester);
      h.main.updateSelection(const TextSelection.collapsed(offset: 3), quill.ChangeSource.local);
      mainFocus(tester).requestFocus();
      await wait(tester);
      clipboard('أ\tب\nج\tد\n');
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('bt-paste-as-text')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      expect(find.text('لصق جدول'), findsNothing, reason: 'لا يُسأل مرّتين');
      expect(h.tableCount, 1);
      expect('أ\tب'.allMatches(h.main.document.toPlainText()).length, 1, reason: 'النصّ مرّةً واحدة');
    });

    group('🔴 على الويب يلصق المتصفّح نفسه — نصٌّ خامّ بعلامات Tab يصل المحرّر مباشرة', () {
      testWidgets('في خلية: يصير لصق جدول (يملأ من هنا ويُدرج قبل المجموع) لا نصّاً في خليةٍ واحدة', (tester) async {
        await pump(tester);
        final h = hubOf(tester);
        await tapCell(tester, 1, 1);
        // ما يفعله المحرّر حين يكتب المتصفّح اللصق في حقله: replaceText بنصٍّ خامّ — بلا onClipboardPaste
        h.cell!.replaceText(0, 0, 'أ\t1\nب\t2\nج\t3\nد\t4', const TextSelection.collapsed(offset: 15));
        await wait(tester, 100);
        final t = stored(h);
        expect(t.rows[1].cells[1]!.text, 'أ', reason: 'لا «أ⇥1⏎ب…» في خليةٍ واحدة');
        expect(t.rowCount, 6);
        expect([for (var r = 1; r <= 4; r++) t.rows[r].cells[2]!.text], ['1', '2', '3', '4']);
        expect(BtOps.validate(t), isNull);
      });

      testWidgets('في المتن: «إدراجه جدولاً؟» ⟵ نصّاً عاديّاً يُدرج كما وصل', (tester) async {
        await pump(tester);
        final h = hubOf(tester);
        h.main.replaceText(3, 0, 'البند\tالمبلغ\nأ\t1,000', const TextSelection.collapsed(offset: 3));
        await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
        expect(find.text('لصق جدول'), findsOneWidget);
        await tester.tap(find.byKey(const Key('bt-paste-as-text')));
        await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
        expect(h.tableCount, 1);
        expect(h.main.document.toPlainText(), contains('البند\tالمبلغ'));
      });

      testWidgets('في المتن: «جدولاً» ⟵ جدولٌ عند موضع اللصق', (tester) async {
        await pump(tester);
        final h = hubOf(tester);
        h.main.replaceText(3, 0, 'البند\tالمبلغ\nأ\t1,000', const TextSelection.collapsed(offset: 3));
        await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
        await tester.tap(find.byKey(const Key('bt-paste-as-table')));
        await wait(tester);
        expect(h.tableCount, 2);
        expect(stored(h).rows[1].cells[1]!.text, '1,000');
        expect(h.main.document.toPlainText(), isNot(contains('البند\tالمبلغ')));
      });

      testWidgets('Tab واحد يُكتب في المتن كما هو — ليس لصقاً', (tester) async {
        await pump(tester);
        final h = hubOf(tester);
        h.main.replaceText(3, 0, '\t', const TextSelection.collapsed(offset: 4));
        await wait(tester);
        expect(find.text('لصق جدول'), findsNothing);
        expect(h.main.document.toPlainText().substring(3, 4), '\t');
      });
    });
  });
}

/// متنٌ فيه نصٌّ ثم جدول فاتورة.
String invoiceBody() => jsonEncode([
      {'insert': 'قبل الجدول\n'},
      {
        'insert': {kDmsTableEmbed: BtJson.toEmbedData(BtOps.invoice())}
      },
      {'insert': 'بعد الجدول\n'},
    ]);

class _Launcher extends StatelessWidget {
  const _Launcher({required this.mode, this.book});
  final OutgoingEditorMode mode;
  final OutgoingDetail? book;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutgoingEditorScreen(mode: mode, book: book))),
            child: const Text('افتح'),
          ),
        ),
      );
}

OutgoingDetail _book({String? bodyJson}) => OutgoingDetail.fromJson({
      'outgoingId': 9, 'companyId': 1, 'number': null, 'date': '2026-10-04', 'entityId': 1, 'entityName': 'وزارة النقل',
      'templateId': 2, 'subject': 'فاتورة', 'bodyHtml': '<p>نص</p>', 'bodyJson': bodyJson, 'status': 'Draft',
      'rowVersion': 'AAAAAAAAB9E=', 'outgoingBookTypeId': 10, 'printEntity': true, 'signaturePlacement': 'LastPage',
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
  Map<String, dynamic>? updated;
  int wordsCalls = 0;

  @override
  Future<List<EntityModel>> entities() async => [EntityModel(1, 1, 'وزارة النقل', 'Both', null)];
  @override
  Future<List<TemplateModel>> templates() async => [_template(2)];
  @override
  Future<List<OutgoingBookTypeModel>> outgoingBookTypes() async => [OutgoingBookTypeModel(10, 1, 'كتاب رسمي')];
  @override
  Future<List<Company>> companies({bool includeInactive = false}) async => const [];
  @override
  Future<Uint8List?> getTemplateImage(int id, String kind) async => null;
  @override
  Future<Uint8List> previewOutgoing(Map<String, dynamic> body) async => Uint8List(0);
  @override
  Future<String> numberWords(num value, String currency) async {
    wordsCalls++;
    return 'نصّ ${value.toInt()} $currency';
  }

  @override
  Future<OutgoingDetail> createOutgoing(Map<String, dynamic> body, {String? idempotencyKey}) async {
    created = body;
    return _book();
  }

  @override
  Future<OutgoingDetail> updateOutgoing(int id, Map<String, dynamic> body) async {
    updated = body;
    return _book();
  }
}

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
