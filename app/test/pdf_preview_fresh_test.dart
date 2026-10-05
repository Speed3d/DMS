import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

import 'package:dms_app/widgets/pdf_preview_pane.dart';

/// 🔴 **عارضٌ جديد لكل ملفّ** (بلاغ المالك 2026-10-05): مكتبة `printing` تُهمل ملفّاً يصل أثناء رسم سابقه، فكانت
/// المعاينة تبقى على شكلٍ قديم أو خليطٍ من الشكلين («يتغيّر ترتيب الأوراق وتبقى ورقةٌ بيضاء»).
/// الحارس: حالةُ العارض (State) تُستبدل حين يتغيّر الملفّ، وتبقى حين يُعاد البناء بالملفّ نفسه.
void main() {
  Future<void> pump(WidgetTester tester, Uint8List bytes) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfPreviewPane(bytes: bytes, busy: false, stale: false, error: null, onRefresh: () {}),
        ),
      ));

  State previewState(WidgetTester tester) => tester.state(find.byType(PdfPreview));

  testWidgets('ملفٌّ جديد ⟵ عارضٌ جديد · والملفّ نفسه ⟵ العارض نفسه', (tester) async {
    final a = Uint8List.fromList([1, 2, 3]);
    final b = Uint8List.fromList([1, 2, 3]);   // المحتوى نفسه وردٌّ آخر — الهويّة هي ما يُقارن

    await pump(tester, a);
    final first = previewState(tester);

    await pump(tester, a);
    expect(identical(previewState(tester), first), isTrue, reason: 'إعادة البناء بالملفّ نفسه لا تعيد الرسم');

    await pump(tester, b);
    expect(identical(previewState(tester), first), isFalse,
        reason: 'الملفّ الجديد يبدأ عارضاً جديداً فلا يُهمَل لأن القديم ما زال يرسم');
    expect(first.mounted, isFalse, reason: 'العارض القديم هُدم فيتوقّف رسمه');
  });
}
