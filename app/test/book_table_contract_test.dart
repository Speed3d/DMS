import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
import 'package:dms_app/core/book_table/table_paste.dart';
import 'package:dms_app/core/book_table/table_serializer.dart';
import 'package:dms_app/core/quill_html.dart';

/// عقدُ الواجهة والخادم (ADR-057): يكتب ما تحفظه الواجهة فعلاً إلى ملفّ يُرسَل للخادم الحيّ في فحص الدفعة —
/// فاختلافٌ بين قواعد الطرفين (وسمٌ لا يقبله · حقلٌ ناقص) يظهر 400 هنا لا عند المستخدم.
///
/// ⚠️ لا يحتاج خادماً ليعمل: يكتب الملف فقط إن ضُبط `DMS_CONTRACT_OUT`، وإلا يكتفي بفحص البنية.
void main() {
  test('أجسام كتبٍ بجداول كما تحفظها الواجهة', () {
    var edited = BtOps.invoice();
    edited = BtOps.paste(edited, 1, 1, [
      for (var i = 1; i <= 4; i++) ['Item $i', 'مادة $i', '2', '1,000', '2,000'],
    ]);
    edited = BtOps.insertCol(edited, 3);
    edited = BtOps.merge(edited, 1, 2, 2, 2);
    edited = BtOps.editCells(edited, 1, 0, 1, 6, (c) => c.bg = '#FCE4D6');

    // الدفعة ٧: ما يُنتجه محرّر الجدول — تنسيقُ عدّة خلايا · تنسيقٌ مختلط في خليةٍ بعد التنقية · جمعٌ لعمودٍ آخر ·
    // حروفٌ بـ«قبل» و«بعد» بالدولار · عناوين بصفّين · ترقيم · لصقٌ من Word بلونه وعريضه · وأوزانٌ مسحوبة.
    var editor = BtOps.invoice();
    editor = BtOps.pasteCells(editor, 1, 1, BtPaste.parseHtmlCells('''
<table><tr><td><b>CAT III Localizer</b></td><td style="background:#FFF2CC">جهاز اللوكلايزر</td><td>1</td><td>2,850,000,000</td><td>2,850,000,000</td></tr>
<tr><td>Monitor</td><td>جهاز مراقبة</td><td>2</td><td>50,000,000</td><td>100,000,000</td></tr></table>''')!);
    editor = BtOps.formatCells(editor, 1, 4, 2, 5, {'size': '11', 'color': '#C00000', 'align': 'center'});
    final mixed = editor.rows[2].cells[1]!;
    mixed.delta = BtOps.sanitizeDelta([
      {'insert': 'Monitor ', 'attributes': {'bold': true, 'link': 'https://x'}},
      {'insert': 'v2', 'attributes': {'italic': true, 'underline': true, 'background': '#ffff00', 'font': 'Arial'}},
      {'insert': '\n', 'attributes': {'align': 'right', 'header': 2}},
    ]);
    final sumId = editor.rows.last.cells[2]!.id;
    final wordsId = editor.rows.last.cells[4]!.id;
    editor = BtOps.setSum(editor, sumId, 5);
    editor = BtOps.setWords(editor, wordsId, BtWords(sourceCellId: sumId, currency: 'USD', prefix: 'فقط', suffix: 'لا غير'));
    editor = BtOps.insertRow(editor, 0);
    editor = BtOps.setHeaderRows(editor, 2);
    editor = BtOps.setNumberingCol(editor, 0);
    editor = BtOps.setColumnWeights(editor, [5, 30, 25, 8, 16, 16]);
    editor = BtOps.clearCells(editor, 3, 3, 3, 3);
    editor = editor.copy()..borderWidthPt = 1.5..borderColor = '#404040';

    final bodies = <String, BtTable>{
      'blank': BtOps.blank(3, 4),
      'invoice': BtOps.invoice(),
      'edited': edited,
      'editor-b7': editor,
      'ltr-narrow': BtOps.blank(2, 3)..dir = 'ltr'..widthPct = 60..align = 'start'..repeatHeader = false,
    }.map((name, t) {
      expect(BtOps.validate(t), isNull, reason: '$name: ${BtOps.validate(t)}');
      final html = quillDeltaToHtml([
        {'insert': 'فاتورة\n', 'attributes': {'align': 'center'}},
        {'insert': {kDmsTableEmbed: BtJson.toEmbedData(t)}},
        {'insert': 'بعد الجدول\n'},
      ]);
      expect(html, contains('data-dms-table='));
      return MapEntry(name, html);
    });

    final out = Platform.environment['DMS_CONTRACT_OUT'];
    if (out != null) File(out).writeAsStringSync(jsonEncode(bodies));
  });
}
