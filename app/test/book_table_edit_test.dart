import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_formulas.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_paste.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';

/// عمليات محرّر الجدول (ADR-057، الدفعة ٧) — التنسيق والمسح والجمع والحروف والعناوين والعرض والنسخ واللصق الغنيّ.
///
/// 🔑 بعد كل عمليةٍ تُفحص البنية بقاعدة الخادم (`BtOps.validate`) — كما في `book_table_test.dart`.
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

  void valid(BtTable t) => expect(BtOps.validate(t), isNull, reason: BtOps.validate(t));
  BtCell at(BtTable t, int r, int c) => t.ownerOf(r, c)!.cell;

  group('تنسيق عدّة خلايا', () {
    test('العريض والحجم يُطبَّقان على كل نصّ الخلايا — والأصل لا يُمسّ', () {
      final src = grid([
        ['أ', 'ب'],
        ['ج', 'د'],
      ]);
      final t = BtOps.formatCells(src, 0, 0, 1, 0, {'bold': true, 'size': '14'});
      valid(t);
      expect(at(t, 0, 0).inlineStyle, {'bold': true, 'size': '14'});
      expect(at(t, 1, 0).inlineStyle, {'bold': true, 'size': '14'});
      expect(at(t, 0, 1).inlineStyle, isNull, reason: 'خارج التحديد');
      expect(at(src, 0, 0).inlineStyle, isNull, reason: 'العملية نقيّة');
    });

    test('null يُزيل السمة · والخلية الفارغة تحفظ تنسيقها لما يُكتب فيها', () {
      final t = BtOps.formatCells(grid([
        ['', 'نص'],
      ]), 0, 0, 0, 1, {'bold': true});
      expect(at(t, 0, 0).textStyle, {'bold': true}, reason: 'Quill لا يحفظ تنسيقاً بلا نصّ');
      final off = BtOps.formatCells(t, 0, 0, 0, 1, {'bold': null});
      expect(at(off, 0, 1).inlineStyle, isNull);
      expect(at(off, 0, 0).textStyle, isNull);
    });

    test('المحاذاة على كل أسطر الخلية — والنصّ وتنسيقه كما هما', () {
      final src = grid([
        ['سطر'],
      ]);
      BtOps.setText(at(src, 0, 0), 'أوّل\nثانٍ');
      final bold = BtOps.formatCells(src, 0, 0, 0, 0, {'bold': true});
      final t = BtOps.formatCells(bold, 0, 0, 0, 0, {'align': 'center'});
      final lines = at(t, 0, 0).delta.where((op) => op['insert'] == '\n').toList();
      expect(lines, hasLength(2));
      expect(lines.every((op) => (op['attributes'] as Map)['align'] == 'center'), isTrue);
      expect(at(t, 0, 0).text, 'أوّل\nثانٍ');
      expect(at(t, 0, 0).inlineStyle, {'bold': true});
    });
  });

  group('المسح', () {
    test('Delete يمسح النصّ والجمع والحروف — ويُبقي اللون والتنسيق', () {
      final t = BtOps.invoice();
      BtOps.setText(t.rows[1].cells[5]!, '1,000');
      final sum = t.rows.last.cells[2]!;
      final cleared = BtOps.clearCells(t, 1, 5, t.rowCount - 1, 5);
      valid(cleared);
      expect(at(cleared, 1, 5).text, isEmpty);
      final total = BtOps.clearCells(t, t.rowCount - 1, 0, t.rowCount - 1, 5);
      final s = total.findCell(sum.id)!.cell;
      expect(s.formula, isNull);
      expect(s.bg, '#AEAAAA');
      expect(total.rows.last.cells.whereType<BtCell>().every((c) => c.words == null), isTrue);
    });
  });

  group('الجمع والكتابة بالحروف', () {
    test('Σ يمسح النصّ والحروف — والخادم يرفض الاثنين معاً فلا يجتمعان أبداً', () {
      final t = BtOps.invoice();
      final words = t.rows.last.cells[4]!;
      final asSum = BtOps.setSum(t, words.id, 5);
      final c = asSum.findCell(words.id)!.cell;
      expect(c.formula?.col, 5);
      expect(c.words, isNull);
      final back = BtOps.setWords(asSum, words.id, BtWords(sourceCellId: t.rows.last.cells[2]!.id));
      final w = back.findCell(words.id)!.cell;
      expect(w.formula, isNull);
      expect(w.words, isNotNull);
    });

    test('إزالة Σ بـnull — وعمودٌ خارج الجدول يُحصر', () {
      final t = grid([
        ['1', ''],
      ]);
      final id = at(t, 0, 1).id;
      expect(BtOps.setSum(t, id, 99).findCell(id)!.cell.formula!.col, 1);
      expect(BtOps.setSum(BtOps.setSum(t, id, 0), id, null).findCell(id)!.cell.formula, isNull);
    });

    test('الحروف لا تشير إلى نفسها (الخادم يرفضها)', () {
      final t = grid([
        ['1'],
      ]);
      final id = at(t, 0, 0).id;
      expect(identical(BtOps.setWords(t, id, BtWords(sourceCellId: id)), t), isTrue);
    });

    test('المصدر المقترح: جمعُ الصفّ نفسه — وإلا آخر جمعٍ قبلها', () {
      final t = BtOps.invoice();
      final words = t.rows.last.cells[4]!;
      final sum = t.rows.last.cells[2]!;
      expect(BtOps.suggestWordsSource(t, words.id), sum.id);
      final below = BtOps.insertRow(t, t.rowCount);
      final cell = below.rows.last.cells[0]!;
      expect(BtOps.suggestWordsSource(below, cell.id), sum.id);
      expect(BtOps.suggestWordsSource(grid([
        ['أ'],
      ]), 'x'), isNull);
    });
  });

  group('العناوين والترقيم والعرض', () {
    test('صفوف العناوين لا تقطع دمجاً — والسبب بالعربية', () {
      var t = grid([
        ['أ', 'ب'],
        ['ج', 'د'],
        ['هـ', 'و'],
      ]);
      t = BtOps.merge(t, 0, 0, 1, 0);
      expect(BtOps.headerRowsProblem(t, 1), contains('مدموجة'));
      expect(identical(BtOps.setHeaderRows(t, 1), t), isTrue);
      final ok = BtOps.setHeaderRows(t, 2);
      valid(ok);
      expect(ok.headerRows, 2);
    });

    test('عمود الترقيم يُضبط ويُوقف — والصفّ الجديد يأخذ التالي', () {
      final t = BtOps.setNumberingCol(grid([
        ['ت', 'المادة'],
        ['1', 'أ'],
      ], header: 1), 0);
      expect(t.numberingCol, 0);
      expect(at(BtOps.insertRow(t, 2), 2, 0).text, '2');
      expect(BtOps.setNumberingCol(t, null).numberingCol, isNull);
    });

    test('سحب الحدّ: الأوزان نِسَبٌ — ولا عمودَ أضيق من الحدّ الأدنى', () {
      final t = BtOps.setColumnWeights(grid([
        ['أ', 'ب', 'ج'],
      ]), [0, 50, 50]);
      final shares = [for (final c in t.cols) c.weight];
      expect(shares.first, greaterThan(0), reason: 'عمودٌ بعرض صفر لا يُرى ولا يُنقر');
      expect(shares[1], shares[2]);
      expect(identical(BtOps.setColumnWeights(t, [1, 2]), t), isTrue, reason: 'عددٌ لا يطابق الأعمدة يُرفض');
    });
  });

  group('النسخ', () {
    test('خلية الجمع تُنسخ بقيمتها — والمدموجة فارغة · وTSV يُقرأ كما كُتب', () {
      final t = BtOps.invoice();
      BtOps.setText(t.rows[1].cells[5]!, '1,500');
      BtOps.setText(t.rows[2].cells[5]!, '2,500');
      final last = t.rowCount - 1;
      final g = BtOps.copyGrid(t, last, 0, last, 5);
      expect(g.single[2], '4,000');
      expect(g.single[1], '', reason: 'خانة يغطّيها دمج');
      final tsv = BtPaste.toTsv([
        ['سطران\nفي خلية', 'عادي', 'فيه "تنصيص"'],
        ['1', '2', '3'],
      ]);
      expect(BtPaste.parseTsv(tsv), [
        ['سطران\nفي خلية', 'عادي', 'فيه "تنصيص"'],
        ['1', '2', '3'],
      ]);
    });
  });

  group('تنقية الخلية', () {
    test('الرابط والتظليل والعناوين تُسقط — والعريض واللون والحجم والمحاذاة تبقى', () {
      final d = BtOps.sanitizeDelta([
        {
          'insert': 'رابط',
          'attributes': {'link': 'https://x', 'bold': true, 'background': '#ffff00', 'color': '#ff0000', 'size': '14'}
        },
        {
          'insert': '\n',
          'attributes': {'align': 'center', 'header': 1, 'list': 'bullet'}
        },
      ]);
      expect(d.first['attributes'], {'bold': true, 'color': '#ff0000', 'size': '14'});
      expect(d.last['attributes'], {'align': 'center'});
      final html = BtJson.cellHtml(BtCell(id: 'c', delta: d));
      expect(html, isNot(contains('<a')), reason: 'الخادم يرفض <a> في الخلية بـ400');
      expect(html, isNot(contains('background')));
    });

    test('بلا سطرٍ أخير يُضاف · والصورة والبلوك يُسقطان', () {
      final d = BtOps.sanitizeDelta([
        {'insert': 'نص'},
        {
          'insert': {'image': 'x.png'}
        },
      ]);
      expect(d, [
        {'insert': 'نص'},
        {'insert': '\n'},
      ]);
      expect(BtOps.sanitizeDelta(const []), [
        {'insert': '\n'}
      ]);
    });
  });

  group('اللصق الغنيّ (Word)', () {
    const word = '''
<table>
  <tr><td style="background:#AEAAAA"><b>ت</b></td><td style="background:#AEAAAA"><p><strong>المادة</strong></p></td></tr>
  <tr><td>1</td><td><span style="font-weight:700">عريضٌ كلُّه</span></td></tr>
  <tr><td bgcolor="#ffffff">2</td><td>نصفه <b>عريض</b></td></tr>
  <tr><td style="background-color: rgb(255, 242, 204)">3</td><td></td></tr>
</table>''';

    test('النصّ والعريض ولون الخلفية — والأبيض بلا لون · ونصفُ العريض ليس عريضاً', () {
      final cells = BtPaste.parseHtmlCells(word)!;
      expect(cells[0][0].bg, '#AEAAAA');
      expect(cells[0][1].bold, isTrue);
      expect(cells[1][1].bold, isTrue);
      expect(cells[2][0].bg, isNull, reason: 'Word يكتب الأبيض لكل خلية');
      expect(cells[2][1].bold, isFalse);
      expect(cells[3][0].bg, '#FFF2CC');
      expect(cells[3][1].bold, isNull, reason: 'خليةٌ فارغة لا تحدّد شيئاً');
    });

    test('يُلصق في الجدول بالعريض واللون — وما لم يحدّده المصدر يبقى كما هو', () {
      final t = BtOps.pasteCells(BtOps.invoice(), 1, 0, BtPaste.parseHtmlCells(word)!.sublist(1));
      valid(t);
      expect(at(t, 1, 1).inlineStyle?['bold'], isTrue);
      expect(at(t, 2, 1).inlineStyle?['bold'], isNull, reason: 'المصدر قال: ليس عريضاً');
      expect(at(t, 3, 0).bg, '#FFF2CC');
      expect(at(t, 2, 0).bg, isNull);
    });

    test('بنودٌ أكثر من صفوف الفاتورة: تُدرج قبل المجموع — وتنسيقها يقع على صفوفها لا على المجموع', () {
      final rows = [
        for (var i = 0; i < 5; i++) [BtPasteCell('${i + 1}'), BtPasteCell('مادة $i', bg: '#FFF2CC')]
      ];
      final src = BtOps.invoice();
      final sumId = src.rows.last.cells[2]!.id;
      final t = BtOps.pasteCells(src, 1, 0, rows);
      valid(t);
      expect(t.rows.last.cells[2]!.id, sumId, reason: 'المجموع آخراً');
      for (var r = 1; r <= 5; r++) {
        expect(at(t, r, 1).bg, '#FFF2CC', reason: 'الصفّ $r');
      }
      expect(t.rows.last.cells[0]!.bg, '#AEAAAA', reason: 'لون المجموع لم يُمسّ');
    });

    test('جدولٌ ملصوقٌ في المتن: الصفّ الأوّل عناوين — والنصّ كما هو', () {
      final t = BtOps.fromGrid(BtPaste.plainCells([
        ['البند', 'المبلغ'],
        ['أ', '1,000'],
        ['ب', '2,000'],
      ]));
      valid(t);
      expect(t.headerRows, 1);
      expect(t.rowCount, 3);
      expect(at(t, 2, 1).text, '2,000');
      expect(BtFormulas.parseNumber(at(t, 1, 1).text), 1000);
    });
  });
}
