import 'dart:convert';
import 'dart:io';

import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_formula_text.dart';
import 'package:dms_app/core/book_table/table_formulas.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// معادلات الجداول (ADR-060) — **الأمثلة المشتركة مع الخادم** (`backend/Dms.Tests/Fixtures/table-calc-vectors.json`):
/// يجب أن يُخرج المحرّر لكل خليةٍ النصَّ نفسه الذي يطبعه الخادم. والمحلّل والتقريب والتنسيق بقيم اختبار الخادم نفسها.
void main() {
  final vectors = (jsonDecode(File('../backend/Dms.Tests/Fixtures/table-calc-vectors.json').readAsStringSync())
      as Map<String, dynamic>)['vectors'] as List;

  group('الأمثلة المشتركة مع الخادم', () {
    for (final v in vectors.cast<Map<String, dynamic>>()) {
      test(v['name'] as String, () {
        final computed = BtFormulas.evaluate(build(v));
        (v['expected'] as Map<String, dynamic>).forEach((id, expected) {
          final c = computed[id];
          expect(c, isNotNull, reason: 'الخلية $id لم تُحسب');
          expect(c!.isError ? '$kCalcErrorText:${c.error}' : c.text, expected, reason: 'الخلية $id');
        });
        for (final id in (v['absent'] as List? ?? const [])) {
          expect(computed.containsKey(id), isFalse, reason: 'الخلية $id حُسبت ولا يجب');
        }
      });
    }
  });

  group('المحلّل — بالرسائل نفسها التي يردّها الخادم', () {
    test('يقبل الشكل المخزَّن ويعدّ المراجع مرّةً واحدة', () {
      expect(BtExpression.parse('{c1}*{c2}').refs, ['c1', 'c2']);
      expect(BtExpression.parse('({a}+{b})÷{a}').refs, ['a', 'b']);
      expect(BtExpression.parse('12.5 × 2 − 1').refs, isEmpty);
      expect(BtExpression.parse('١٢٫٥*٢').refs, isEmpty);
    });

    for (final bad in ['', '2+', '(2+3', '2+3)', '{a', '{}', '{a b}', '{../x}', '2 ^ 3', '1.2.3', 'SUM(A1)', '1234567890123456789']) {
      test('يرفض «$bad»', () {
        expect(() => BtExpression.parse(bad), throwsA(isA<BtExprError>()));
      });
    }

    test('الحدود: الطول · عدد المراجع · العمق', () {
      expect(() => BtExpression.parse('1111111111${List.filled(260, '+1').join()}'), throwsA(isA<BtExprError>()));
      expect(() => BtExpression.parse([for (var i = 0; i < 51; i++) '{c$i}'].join('+')), throwsA(isA<BtExprError>()));
      final open = List.filled(25, '(').join(), close = List.filled(25, ')').join();
      expect(() => BtExpression.parse('${open}1$close'), throwsA(isA<BtExprError>()));
      expect(BtExpression.parse([for (var i = 0; i < 50; i++) '{c$i}'].join('+')).refs.length, 50);
    });
  });

  group('الدقة والتنسيق', () {
    BtRational eval(String e) => BtExpression.parse(e).evaluate((_) => const BtCalcResult.fail('x')).value!;

    test('كسرٌ دقيق حيث يخطئ double', () {
      expect(eval('0.1+0.2'), BtRational(BigInt.from(3), BigInt.from(10)));
      expect(eval('(1/3)*3'), BtRational.integer(1));
    });

    for (final (v, r) in [('2.345', '2.35'), ('-2.345', '-2.35'), ('2.344', '2.34'), ('0.005', '0.01'), ('-0.005', '-0.01')]) {
      test('التقريب $v ⟵ $r (النصف بعيداً عن الصفر)', () {
        expect(eval(v).roundCents(), BtRational.tryParseDecimal(r));
      });
    }

    test('التنسيق: N0 و N2 كالخادم', () {
      expect(eval('2850004501.5').format(decimals: true), '2,850,004,501.50');
      expect(eval('9450000000').format(decimals: false), '9,450,000,000');
      expect(eval('-0.001').format(decimals: true), '0.00');
      expect(eval('-1234.5').format(decimals: true), '-1,234.50');
      expect(eval('2.5').format(decimals: false), '3');
    });

    test('حرف العمود', () {
      expect([0, 25, 26, 29].map(btColumnLetter), ['A', 'Z', 'AA', 'AD']);
    });
  });

  group('العمليات', () {
    String text(BtTable t, String id) => BtFormulas.evaluate(t)[id]?.text ?? t.findCell(id)!.cell.text;

    BtTable invoice() {
      // فاتورة المالك من المحرّر نفسه: الكمية (3) × سعر المفرد (4) في «السعر الكلي» (5)، والمجموع Σ عليه
      final t = BtOps.invoice();
      BtOps.setText(t.rows[1].cells[3]!, '2');
      BtOps.setText(t.rows[1].cells[4]!, '1,425,000,000');
      return BtOps.setColumnCalc(t, 5, '{${t.cols[3].id}}*{${t.cols[4].id}}');
    }

    test('العمود المحسوب: صفوف البند تحسب · والمجموع والحروف يقرآنها · والصفّ الجديد يرثها', () {
      var t = invoice();
      final sumId = t.rows.last.cells[2]!.id;
      expect(text(t, t.rows[1].cells[5]!.id), '2,850,000,000');
      expect(BtFormulas.evaluate(t)[sumId]!.text, '2,850,000,000');
      expect(BtFormulas.wordsSource(t, t.rows.last.cells[4]!.words!), 2850000000);

      t = BtOps.insertRow(t, 2);
      BtOps.setText(t.rows[2].cells[3]!, '3');
      BtOps.setText(t.rows[2].cells[4]!, '1,000');
      expect(text(t, t.rows[2].cells[5]!.id), '3,000');
      expect(BtFormulas.evaluate(t)[sumId]!.text, '2,850,003,000');
      expect(BtOps.validate(t), isNull);
    });

    test('اللصق لا يكتب فوق خليةٍ محسوبة · والنسخ يأخذ ناتجها', () {
      var t = invoice();
      t = BtOps.paste(t, 1, 3, [['5', '10', '999']]);
      expect(t.rows[1].cells[5]!.text, isEmpty);
      expect(text(t, t.rows[1].cells[5]!.id), '50');
      expect(BtOps.copyGrid(t, 1, 3, 1, 5), [['5', '10', '50']]);
    });

    test('معادلة خلية: تُزيل الجمع · وإزالتها تُبقي ناتجها نصّاً · والمسح يُزيلها', () {
      var t = invoice();
      final a = t.rows[1].cells[3]!.id;
      final target = t.rows.last.cells[2]!.id;   // خلية المجموع
      t = BtOps.setCalc(t, target, '{$a}*100');
      expect(t.findCell(target)!.cell.formula, isNull);
      expect(text(t, target), '200');
      t = BtOps.setCalc(t, target, null);
      expect(t.findCell(target)!.cell.calc, isNull);
      expect(t.findCell(target)!.cell.text, '200');
      t = BtOps.setCalc(t, target, '{$a}+1');
      final s = t.findCell(target)!;
      t = BtOps.clearCells(t, s.row, s.col, s.row, s.col);
      expect(t.findCell(target)!.cell.calc, isNull);
    });

    test('إزالة معادلة العمود تُبقي نواتجها نصّاً', () {
      var t = invoice();
      t = BtOps.setColumnCalc(t, 5, null);
      expect(t.cols[5].calc, isNull);
      expect(t.rows[1].cells[5]!.text, '2,850,000,000');
    });

    test('المراجع بالمعرّف: إدراج عمودٍ لا يغيّرها · وحذف المرجع خطأٌ ظاهر لا رقمٌ خاطئ', () {
      var t = invoice();
      t = BtOps.insertCol(t, 0);
      expect(text(t, t.rows[1].cells[6]!.id), '2,850,000,000');
      t = BtOps.deleteCol(t, 4);   // «الكمية»
      final c = BtFormulas.evaluate(t)[t.rows[1].cells[5]!.id]!;
      expect(c.error, kCalcErrRef);
    });
  });

  group('العرض ⟷ التخزين', () {
    // جدول 3×3 بلا عناوين: A1..C3 — ومعرّفاتٌ معروفة
    BtTable grid3() => BtTable(id: 't', cols: [
          for (final k in ['ka', 'kb', 'kc']) BtCol(id: k)
        ], rows: [
          for (var r = 0; r < 3; r++)
            BtRow(id: 'r$r', cells: [for (final c in ['a', 'b', 'c']) BtCell(id: '$c${r + 1}')])
        ]);

    test('الخلية: B3 × C3 ⟷ {b3}*{c3} — والأحرف الصغيرة والأرقام الهندية تُقبل', () {
      final t = grid3();
      expect(BtFormulaText.toStorage(t, '= B3 × C3', column: false), '{b3}*{c3}');
      expect(BtFormulaText.toStorage(t, 'b١ ÷ (a2 − 1)', column: false), '{b1}/({a2}-1)');
      expect(BtFormulaText.toDisplay(t, '{b3}*{c3}', column: false), 'B3 × C3');
    });

    test('العمود: B × C ⟷ {kb}*{kc}', () {
      final t = grid3();
      expect(BtFormulaText.toStorage(t, 'B × C', column: true), '{kb}*{kc}');
      expect(BtFormulaText.toDisplay(t, '{kb}*{kc}', column: true), 'B × C');
    });

    test('الخلية المدموجة باسم ركنها: B2 داخل دمجٍ يبدأ في A1 ⟵ {a1}', () {
      final t = BtOps.merge(grid3(), 0, 0, 1, 1);
      expect(BtFormulaText.toStorage(t, 'B2+1', column: false), '{a1}+1');
    });

    test('أخطاءٌ تقول أين: خارج الجدول · حرفٌ بلا رقم · رقمٌ في معادلة العمود · مرجعٌ محذوف', () {
      final t = grid3();
      expect(() => BtFormulaText.toStorage(t, 'D1+1', column: false), throwsA(isA<BtExprError>()));
      expect(() => BtFormulaText.toStorage(t, 'A9', column: false), throwsA(isA<BtExprError>()));
      expect(() => BtFormulaText.toStorage(t, 'A+B', column: false), throwsA(isA<BtExprError>()));
      expect(() => BtFormulaText.toStorage(t, 'A1+B', column: true), throwsA(isA<BtExprError>()));
      expect(() => BtFormulaText.toStorage(t, 'A1+', column: false), throwsA(isA<BtExprError>()));
      expect(BtFormulaText.toDisplay(t, '{gone}*2', column: false), '${BtFormulaText.deleted} × 2');
      expect(() => BtFormulaText.toStorage(t, '${BtFormulaText.deleted} × 2', column: false), throwsA(isA<BtExprError>()));
    });

    test('التبديل بين الخلية والعمود · والمراجع للتلوين', () {
      expect(BtFormulaText.switchMode('B3 × C3', toColumn: true, row: 2), 'B × C');
      expect(BtFormulaText.switchMode('B × C + 1', toColumn: false, row: 4), 'B5 × C5 + 1');
      final t = grid3();
      expect(BtFormulaText.refsOf(t, 'A1 + C2 + Z9 +', column: false), {'a1', 'c2'});
      expect(BtFormulaText.refsOf(t, 'A × C', column: true), {'ka', 'kc'});
    });

    test('المعاينة قبل التطبيق', () {
      final t = grid3();
      BtOps.setText(t.rows[0].cells[0]!, '6');
      BtOps.setText(t.rows[0].cells[1]!, '4');
      expect(BtFormulaText.preview(t, '{a1}/{b1}', cellId: 'c1')!.text, '1.50');
      expect(BtFormulaText.preview(t, '{a1}/0', cellId: 'c1')!.error, kCalcErrDivZero);
      expect(BtFormulaText.preview(t, '{ka}*{kb}', col: 2, row: 0)!.text, '24');
    });
  });

  group('المُسلسِل', () {
    test('معادلة الخلية والعمود تذهبان وتعودان', () {
      final t = build(vectors.cast<Map<String, dynamic>>().first);
      final back = BtJson.fromJson(jsonDecode(jsonEncode(BtJson.toJson(t))) as Map<String, dynamic>);
      expect(back.cols[5].calc?.expr, '{k3}*{k4}');
      expect(BtFormulas.evaluate(back)['s']!.text, '2,850,004,501.50');
    });

    test('للطباعة: الخلية المحسوبة غلافُ تنسيقها فارغاً — والخادم يُدرج الرقم فيه', () {
      final t = build(vectors.cast<Map<String, dynamic>>().first);
      final target = t.findCell('t1')!.cell..textStyle = {'bold': true};
      expect(BtJson.cellHtml(target, computed: true), contains('<strong></strong>'));
      final j = BtJson.toJson(t, forPrint: true);
      final cells = [for (final r in j['rows'] as List) ...(r['cells'] as List)].whereType<Map>();
      expect(cells.firstWhere((c) => c['id'] == 't1')['html'], contains('<strong>'));
      expect((j['cols'] as List)[5]['calc'], {'expr': '{k3}*{k4}'});
    });

    test('جدولٌ بلا معادلات يُسلسَل كما كان حرفاً', () {
      final t = build(vectors.cast<Map<String, dynamic>>()[6]);   // Σ يحمل خطأ — بلا عمودٍ محسوب
      t.findCell('x')!.cell.calc = null;
      final j = BtJson.toJson(t, forPrint: true);
      expect(jsonEncode(j), isNot(contains('calc')));
    });
  });
}

/// جدولٌ من صيغة الأمثلة المختصرة — مرآةُ `TableCalcTests.Build` في الخادم.
BtTable build(Map<String, dynamic> v) {
  final rows = <BtRow>[];
  var ri = 0;
  for (final row in (v['rows'] as List)) {
    final cells = <BtCell?>[];
    var ci = 0;
    for (final x in (row as List)) {
      final auto = 'r${ri}c$ci';
      if (x == null) {
        cells.add(null);
      } else if (x is String) {
        cells.add(BtCell(id: auto, delta: _delta(x)));
      } else {
        final m = x as Map<String, dynamic>;
        final span = m['span'] as List?;
        cells.add(BtCell(
          id: m['id'] as String? ?? auto,
          delta: _delta(m['text'] as String? ?? ''),
          rowSpan: span == null ? 1 : span[0] as int,
          colSpan: span == null ? 1 : span[1] as int,
          calc: m['calc'] == null ? null : BtCalc(m['calc'] as String),
          formula: m['sum'] == null ? null : BtFormula(col: m['sum'] as int),
          words: m['words'] == null ? null : BtWords(sourceCellId: m['words'] as String),
        ));
      }
      ci++;
    }
    rows.add(BtRow(id: 'r$ri', cells: cells));
    ri++;
  }
  return BtTable(
    id: 't',
    headerRows: v['headerRows'] as int,
    cols: [
      for (final c in (v['cols'] as List).cast<Map<String, dynamic>>())
        BtCol(id: c['id'] as String, calc: c['calc'] == null ? null : BtCalc(c['calc'] as String)),
    ],
    rows: rows,
  );
}

List<Map<String, dynamic>> _delta(String text) => [
      {'insert': '$text\n'}
    ];
