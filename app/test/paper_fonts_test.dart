import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/paper_fonts.dart';

/// خطوط «الورقة» = خطوط الطباعة **بايتاً ببايت** (ADR-057) — خطٌّ يُستبدل في الخادم ولا يُستبدل هنا يُعيد الورقة كاذبة.
void main() {
  const files = ['times.ttf', 'timesbd.ttf', 'arial.ttf', 'arialbd.ttf', 'Amiri-Regular.ttf', 'Amiri-Bold.ttf', 'Cairo-Regular.ttf', 'Cairo-Bold.ttf'];

  test('كل خطٍّ في الواجهة هو ملفّ الخادم نفسه', () {
    for (final f in files) {
      final app = File('assets/fonts/$f');
      final server = File('../backend/Dms.Documents/Assets/Fonts/$f');
      expect(app.existsSync(), isTrue, reason: '$f غائبٌ عن الواجهة');
      expect(server.existsSync(), isTrue, reason: '$f غائبٌ عن الخادم');
      expect(app.readAsBytesSync(), server.readAsBytesSync(), reason: '$f يختلف بين الواجهة والخادم');
    }
  });

  test('الخادم يسجّل كل خطٍّ تحمّله الواجهة', () {
    final cs = File('../backend/Dms.Documents/Fonts/ArabicFonts.cs').readAsStringSync();
    for (final f in files) {
      expect(cs, contains('Assets.Fonts.$f'), reason: '$f لا يطبع به الخادم');
    }
  });

  testWidgets('التحميل لا يرمي — ونداءٌ ثانٍ ينتظر التحميل نفسه', (tester) async {
    await tester.runAsync(() async {
      final a = PaperFonts.ensureLoaded();
      final b = PaperFonts.ensureLoaded();
      expect(identical(a, b), isTrue);
      await a;
    });
  });
}
