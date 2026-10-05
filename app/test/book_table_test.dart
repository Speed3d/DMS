import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_formulas.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_paste.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';
import 'package:dms_app/core/quill_html.dart';

/// جدول الصادر في الواجهة (ADR-057) — النموذج والعمليات والجمع والترقيم والمُسلسِل واللصق.
///
/// 🔑 **بعد كل عمليةٍ تُفحص البنية بقاعدة الخادم نفسها** (`BtOps.validate`): كل خانةٍ تملكها خليةٌ واحدة — فعمليةٌ
/// تترك ثقباً أو تداخلاً تُكشف هنا قبل أن يرفضها الخادم بـ400 والمستخدم أمام جدوله.
void main() {
  BtTable grid(List<List<String>> texts, {int header = 0}) {
    final t = BtOps.blank(texts.length, texts.first.length, header: false)..headerRows = header;
    for (var r = 0; r < texts.length; r++) {
      for (var c = 0; c < texts[r].length; c++) {
        BtOps.setText(t.rows[r].cells[c]!, texts[r][c]);
      }
    }
    return t;
  }

  String text(BtTable t, int r, int c) => t.ownerOf(r, c)!.cell.text;

  void valid(BtTable t) => expect(BtOps.validate(t), isNull, reason: BtOps.validate(t));

  group('الإنشاء', () {
    test('جدولٌ فارغ: صفّ عناوين وشبكةٌ سليمة', () {
      final t = BtOps.blank(4, 3);
      valid(t);
      expect(t.headerRows, 1);
      expect(t.rowCount, 4);
      expect(t.colCount, 3);
    });

    test('جدول الفاتورة الجاهز بشكل نموذج المالك: 6 أعمدة · ترقيم · Σ للسعر الكلي · والحروف من Σ', () {
      final t = BtOps.invoice();
      valid(t);
      expect(t.colCount, 6);
      expect(t.numberingCol, 0);
      final total = t.rows.last;
      expect(total.cells.where((c) => c != null).length, 3);                 // ثلاث خلايا مدموجة اثنتين اثنتين
      final sum = total.cells[2]!;
      expect(sum.formula!.col, 5);                                            // تجمع «السعر الكلي» لا عمودها
      expect(total.cells[4]!.words!.sourceCellId, sum.id);
      expect([for (var r = 1; r <= 3; r++) text(t, r, 0)], ['1', '2', '3']);
    });

    test('الحدود القصوى تُحترم (30 عموداً · 600 صفّ)', () {
      final t = BtOps.blank(700, 40);
      expect(t.colCount, 30);
      expect(t.rowCount, 600);
    });
  });

  group('الصفوف', () {
    test('صفٌّ في الوسط يرث الشكل لا النصّ، ويأخذ الترقيم التالي', () {
      final t = BtOps.invoice();
      final t2 = BtOps.insertRow(t, 2);                 // بين البند 1 والبند 2
      valid(t2);
      expect(t2.rowCount, t.rowCount + 1);
      expect(text(t2, 2, 0), '2');                       // التالي لـ1
      expect(text(t2, 2, 1), isEmpty);
      expect(t.rowCount, 5, reason: 'الأصل لا يُمسّ');
    });

    test('الترقيم الفرعيّ: 17.3 ⟵ 17.4 · 17.9 ⟵ 17.10', () {
      final t = grid([['ت', 'م'], ['17.3', 'x']], header: 1)..numberingCol = 0;
      expect(text(BtOps.insertRow(t, 2), 2, 0), '17.4');
      BtOps.setText(t.rows[1].cells[0]!, '17.9');
      expect(text(BtOps.insertRow(t, 2), 2, 0), '17.10');
      expect(BtFormulas.increment('ت'), isNull);
    });

    test('صفٌّ يعبر خليةً مدموجة عمودياً يمدّها ولا يكسرها', () {
      var t = grid([['a', 'b'], ['c', 'd'], ['e', 'f']]);
      t = BtOps.merge(t, 0, 0, 2, 0);                    // العمود الأوّل صفوفه الثلاثة
      final t2 = BtOps.insertRow(t, 1);
      valid(t2);
      expect(t2.rows[0].cells[0]!.rowSpan, 4);
      expect(t2.rows[1].cells[0], isNull);
      expect(t2.rows[1].cells[1], isNotNull);
    });

    test('صفٌّ داخل العناوين يزيدها، وتحتها لا', () {
      final t = BtOps.blank(3, 2);
      expect(BtOps.insertRow(t, 0).headerRows, 2);
      expect(BtOps.insertRow(t, 1).headerRows, 1);
    });

    test('حذف صفٍّ تبدأ فيه خليةٌ مدموجة ينقلها بمحتواها إلى ما تحته', () {
      var t = grid([['أ', 'b'], ['c', 'd'], ['e', 'f']]);
      t = BtOps.merge(t, 0, 0, 1, 0);
      final t2 = BtOps.deleteRow(t, 0);
      valid(t2);
      expect(text(t2, 0, 0), contains('أ'));
      expect(t2.rows[0].cells[0]!.rowSpan, 1);
    });

    test('حذف صفٍّ يعبره دمجٌ من فوق يُقصّر الدمج', () {
      var t = grid([['a', 'b'], ['c', 'd'], ['e', 'f']]);
      t = BtOps.merge(t, 0, 0, 2, 0);
      final t2 = BtOps.deleteRow(t, 1);
      valid(t2);
      expect(t2.rows[0].cells[0]!.rowSpan, 2);
    });

    test('آخر صفٍّ لا يُحذف', () {
      final t = BtOps.blank(1, 2, header: false);
      expect(BtOps.deleteRow(t, 0).rowCount, 1);
    });
  });

  group('الأعمدة', () {
    test('عمودٌ يعبر خليةً مدموجة أفقياً يمدّها، وصيغ الجمع وعمود الترقيم بعده تُزاح', () {
      final t = BtOps.invoice();                        // Σ تجمع العمود 5 · الترقيم في 0
      final t2 = BtOps.insertCol(t, 1);
      valid(t2);
      expect(t2.colCount, 7);
      expect(t2.rows.last.cells[0]!.colSpan, 3);        // «المجموع» كانت عمودين فعبرها الإدراج
      final sum = t2.masters.firstWhere((s) => s.cell.formula != null).cell;
      expect(sum.formula!.col, 6);
      expect(t2.numberingCol, 0);
    });

    test('عمودٌ قبل خليةٍ مدموجة عمودياً: خانته الجديدة خليةٌ مستقلّة لا ثقب', () {
      var t = grid([['a', 'b'], ['c', 'd']]);
      t = BtOps.merge(t, 0, 1, 1, 1);
      final t2 = BtOps.insertCol(t, 1);
      valid(t2);
      expect(t2.rows[1].cells[1], isNotNull);
      expect(t2.rows[0].cells[2]!.rowSpan, 2);
    });

    test('حذف العمود الذي تجمعه Σ يُزيل الصيغة · ومصدرُ «الحروف» المحذوف يُزيلها', () {
      final t = BtOps.invoice();
      var t2 = BtOps.deleteCol(t, 5);
      valid(t2);
      expect(t2.masters.where((s) => s.cell.formula != null), isEmpty);

      // حذف عمود بداية Σ نفسها (العمود 2، Σ مدموجة على 2-3) ينقلها لا يحذفها
      t2 = BtOps.deleteCol(t, 2);
      valid(t2);
      expect(t2.masters.where((s) => s.cell.formula != null).length, 1);
      expect(t2.masters.where((s) => s.cell.words != null).length, 1);
    });

    test('آخر عمودٍ لا يُحذف · والترقيم يتبع العمود', () {
      expect(BtOps.deleteCol(BtOps.blank(2, 1), 0).colCount, 1);
      expect(BtOps.deleteCol(BtOps.invoice(), 0).numberingCol, isNull);
    });
  });

  group('الدمج', () {
    test('دمج مستطيلٍ يجمع النصوص في خليته العليا، والفكّ يعيد الشبكة', () {
      final t = grid([['أ', 'ب'], ['ج', 'د']]);
      final m = BtOps.merge(t, 0, 0, 1, 1);
      valid(m);
      expect(m.rows[0].cells[0]!.rowSpan, 2);
      expect(m.rows[0].cells[0]!.colSpan, 2);
      expect(text(m, 1, 1), allOf(contains('أ'), contains('د')));
      final u = BtOps.unmerge(m, 1, 1);
      valid(u);
      expect(u.masters.length, 4);
    });

    test('تحديدٌ يقطع خليةً مدموجة يُرفض بسبب', () {
      final t = BtOps.merge(grid([['a', 'b', 'c'], ['d', 'e', 'f']]), 0, 0, 0, 1);
      expect(BtOps.canMerge(t, 0, 1, 1, 2), contains('يقطع'));
      expect(BtOps.merge(t, 0, 1, 1, 2), same(t));
    });

    test('لا تُدمج العناوين مع ما تحتها (قاعدة الخادم)', () {
      final t = BtOps.blank(3, 2);
      expect(BtOps.canMerge(t, 0, 0, 1, 0), contains('العناوين'));
    });

    test('خليةٌ واحدة ليست دمجاً', () => expect(BtOps.canMerge(BtOps.blank(2, 2), 1, 1, 1, 1), isNotNull));
  });

  group('الجمع — مرآة الخادم', () {
    test('Σ تجمع العمود المختار حتى العناوين وتتخطّى صفّ «مواد احتياطية» الفارغ', () {
      final t = BtOps.invoice();
      for (final (r, v) in [(1, '2,850,000,000'), (2, '100,000,000'), (3, '')]) {
        BtOps.setText(t.rows[r].cells[5]!, v);
      }
      final sumId = t.rows.last.cells[2]!.id;
      final c = BtFormulas.evaluate(t)[sumId]!;
      expect(c.value, 2950000000);
      expect(c.text, '2,950,000,000');
    });

    test('المجاميع الفرعية لا تُحسب مرّتين · والكسر يعطي منزلتين', () {
      final t = grid([['1,000'], ['430.3'], [''], ['5'], ['']]);
      t.rows[2].cells[0]!.formula = BtFormula(col: 0);
      t.rows[4].cells[0]!.formula = BtFormula(col: 0);
      final r = BtFormulas.evaluate(t);
      expect(r[t.rows[2].cells[0]!.id]!.text, '1,430.30');
      expect(r[t.rows[4].cells[0]!.id]!.text, '1,435.30');
    });

    test('أرقامٌ هندية وفواصل · والنصّ ليس رقماً', () {
      expect(BtFormulas.parseNumber('١٬٤٢٥٬٠٠٠'), 1425000);
      expect(BtFormulas.parseNumber('١٤٣٠٫٣٣'), 1430.33);
      expect(BtFormulas.parseNumber('2 قطعة'), isNull);
      expect(BtFormulas.parseNumber('ـــــ'), isNull);
      expect(BtFormulas.format(9450000000, decimals: false), '9,450,000,000');
    });

    test('مصدر «الحروف»: من Σ المحسوبة', () {
      final t = BtOps.invoice();
      BtOps.setText(t.rows[1].cells[5]!, '1,000');
      final w = t.rows.last.cells[4]!.words!;
      expect(BtFormulas.wordsSource(t, w), 1000);
    });
  });

  group('العرض', () {
    test('«توزيع تلقائي»: الرقم بطوله كاملاً فلا ينكسر', () {
      final t = grid([['ت', 'وصفٌ طويلٌ جداً لمادةٍ ما في الفاتورة', '1,425,000,000']]);
      final f = BtOps.autoFit(t);
      expect(f.cols[2].weight, greaterThanOrEqualTo(14));   // 13 حرفاً + 1
      expect(f.cols[0].weight, lessThan(f.cols[2].weight));
      final e = BtOps.distributeEvenly(f);
      expect(e.cols.map((c) => c.weight).toSet(), {1});
    });

    test('تطبيق لونٍ على تحديدٍ يمسّ خلاياه وحدها', () {
      final t = BtOps.editCells(grid([['a', 'b'], ['c', 'd']]), 0, 0, 0, 1, (c) => c.bg = '#AEAAAA');
      expect(t.rows[0].cells.map((c) => c!.bg), ['#AEAAAA', '#AEAAAA']);
      expect(t.rows[1].cells[0]!.bg, isNull);
    });
  });

  group('اللصق', () {
    test('من Excel: Tab وأسطر · وخليةٌ بأسطرٍ بين علامتي تنصيص · و"" تنصيصٌ داخلها', () {
      // هكذا يكتب Excel فعلاً: الخلية التي فيها تنصيصٌ أو سطرٌ تُحاط بعلامتي تنصيص و"" داخلها
      final g = BtPaste.parseTsv('1\t"سطر أوّل\nسطر ثانٍ"\t1,425,000,000\r\n2\t"قال ""نعم"""\t50\r\n')!;
      expect(g, [
        ['1', 'سطر أوّل\nسطر ثانٍ', '1,425,000,000'],
        ['2', 'قال "نعم"', '50'],
      ]);
    });

    test('سطرٌ واحد بلا Tab ليس جدولاً (لصقٌ عاديّ داخل الخلية)', () {
      expect(BtPaste.parseTsv('نصٌّ عادي'), isNull);
      expect(BtPaste.parseTsv('عمودٌ\nمن سطرين'), [['عمودٌ'], ['من سطرين']]);
    });

    test('من Word: جدول HTML · و<br> سطر · وcolspan خاناتٌ فارغة', () {
      final g = BtPaste.parseHtmlTable('<html><body><table>'
          '<tr><td><p>ت</p></td><td colspan="2"><b>المادة</b></td></tr>'
          '<tr><td>1</td><td>CAT III<br>Dual</td><td>2</td></tr></table></body></html>')!;
      expect(g, [
        ['ت', 'المادة', ''],
        ['1', 'CAT III\nDual', '2'],
      ]);
      expect(BtPaste.parseHtmlTable('<p>بلا جدول</p>'), isNull);
    });

    test('اللصق يملأ من الخلية المحدّدة ويُضيف الصفوف الناقصة — ويتخطّى Σ والخانات المدموجة', () {
      final t = BtOps.invoice();                        // 3 بنود
      final g = [
        for (var i = 1; i <= 5; i++) ['Item $i', 'مادة $i', '1', '10', '10'],
      ];
      final p = BtOps.paste(t, 1, 1, g);
      valid(p);
      expect(p.rowCount, t.rowCount + 2);               // بندان جديدان
      expect(text(p, 5, 1), 'Item 5');
      expect(p.masters.where((s) => s.cell.formula != null).length, 1, reason: 'Σ لم تُكتب فوقها');
      // 🐛 صفّ المجموع يبقى آخراً لم يُكتب فوقه، والترقيم استمرّ في البندين الجديدين
      expect(text(p, p.rowCount - 1, 0), 'المجموع');
      expect([for (var r = 1; r <= 5; r++) text(p, r, 0)], ['1', '2', '3', '4', '5']);
      final sumId = p.rows.last.cells[2]!.id;
      expect(BtFormulas.evaluate(p)[sumId]!.value, 50);   // خمسة بنودٍ في كلٍّ 10
    });
  });

  group('تنسيق الخلية الفارغة', () {
    test('🐛 لصقٌ في بنود الفاتورة الفارغة يبقى عريضاً (كان يخرج رفيعاً — كشفته معاينة العقد)', () {
      final p = BtOps.paste(BtOps.invoice(), 1, 1, [['Item 1', 'مادة', '2', '10', '20']]);
      expect(BtJson.cellHtml(p.rows[1].cells[1]!), contains('<strong'));
    });

    test('خليةٌ أُفرغت ثم كُتب فيها تستعيد تنسيقها · والصفّ الجديد يرث عريض جاره', () {
      final cell = BtOps.textCell('نص', bold: true, size: 14);
      BtOps.setText(cell, '');
      BtOps.setText(cell, 'جديد');
      expect(cell.delta.first['attributes'], {'bold': true, 'size': '14'});

      final t = BtOps.insertRow(BtOps.invoice(), 4);   // بندٌ رابع قبل المجموع
      BtOps.setText(t.rows[4].cells[1]!, 'X');
      expect(BtJson.cellHtml(t.rows[4].cells[1]!), contains('<strong'));
    });

    test('التنسيق المحفوظ للمحرّر وحده: في JSON التحرير لا في صورة الطباعة', () {
      final t = BtOps.invoice();
      expect(jsonEncode(BtJson.toJson(t)), contains('textStyle'));
      expect(jsonEncode(BtJson.toJson(t, forPrint: true)), isNot(contains('textStyle')));
    });
  });

  group('المُسلسِل', () {
    test('ذهابٌ وإياب بلا فقدان: الدمج والألوان والصيغ والحروف والترقيم', () {
      final t = BtOps.invoice()..dir = 'ltr'..widthPct = 80..align = 'start'..repeatHeader = false;
      final back = BtJson.fromEmbedData(BtJson.toEmbedData(t));
      valid(back);
      expect(jsonEncode(BtJson.toJson(back)), jsonEncode(BtJson.toJson(t)));
    });

    test('صورة الطباعة: html لكل خلية بلا Delta · وكل الحقول التي يقرؤها الخادم', () {
      final j = BtJson.toJson(BtOps.invoice(), forPrint: true);
      final cell = ((j['rows'] as List).first['cells'] as List).first as Map;
      expect(cell.containsKey('delta'), isFalse);
      expect(cell['html'], allOf(contains('<strong'), contains('font-size: 14pt')));
      expect(j.keys, containsAll(['id', 'v', 'dir', 'widthPct', 'align', 'border', 'headerRows', 'repeatHeader', 'cols', 'rows']));
    });

    test('الوسم مُهرَّبٌ كاملاً: علامات التنصيص والأقواس داخل نصّ خلية لا تكسر السمة', () {
      final t = BtOps.blank(1, 1, header: false);
      BtOps.setText(t.rows[0].cells[0]!, 'قال "x" <y> & \'z\'');
      final tag = BtJson.htmlTag(t);
      final inner = RegExp(r'^<div data-dms-table="([^"]*)"></div>$').firstMatch(tag);
      expect(inner, isNotNull, reason: 'لا علامة تنصيصٍ خامّة داخل السمة');
      expect(tag, isNot(contains('<y>')));
    });

    test('Quill ⟵ HTML: البلوك المضمَّن يصير وسم الجدول بمكانه بين الفقرات', () {
      final t = BtOps.blank(2, 2);
      final html = quillDeltaToHtml([
        {'insert': 'قبل\n'},
        {'insert': {kDmsTableEmbed: BtJson.toEmbedData(t)}},
        {'insert': 'بعد\n'},
      ]);
      expect(html, contains('data-dms-table='));
      expect(html.indexOf('قبل'), lessThan(html.indexOf('data-dms-table')));
      expect(html.indexOf('data-dms-table'), lessThan(html.indexOf('بعد')));
    });

    test('بلوكٌ تالف لا يُسقط تحويل الكتاب', () {
      final html = quillDeltaToHtml([
        {'insert': 'نص\n'},
        {'insert': {kDmsTableEmbed: '{bad json'}},
      ]);
      expect(html, contains('نص'));
      expect(html, isNot(contains('data-dms-table')));
    });

    test('قراءةٌ متسامحة: جدولٌ بحقولٍ ناقصة (مسوّدةٌ قديمة) يأخذ افتراضاته', () {
      final t = BtJson.fromJson({
        'id': 't1',
        'cols': [{'id': 'a'}],
        'rows': [
          {'id': 'r', 'cells': [{'id': 'c'}]}
        ],
      });
      valid(t);
      expect(t.dir, 'rtl');
      expect(t.rows[0].cells[0]!.delta, BtCell.emptyDelta());
    });
  });
}
