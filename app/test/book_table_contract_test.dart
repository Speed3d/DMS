import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/book_table/book_table.dart';
import 'package:dms_app/core/book_table/table_ops.dart';
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

    final bodies = <String, BtTable>{
      'blank': BtOps.blank(3, 4),
      'invoice': BtOps.invoice(),
      'edited': edited,
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
