import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/core/quill_html.dart';
import 'package:dms_app/core/quill_toolbar.dart';

/// حارس لمسار «حجم الخط» من المحرر إلى الـPDF.
///
/// Hint: محوّل Delta→HTML يعرف الأحجام المسمّاة (small/large/huge) ويُسقط **أي قيمة رقمية
///       بصمت**، فيظهر للمستخدم أن «حجم الخط لا يُحفظ». عُوّض ذلك يدوياً في [quillDeltaToHtml]،
///       وهذه الاختبارات تحرس التعويض بعد تحويل قائمة الأحجام إلى قياسات رقمية.
void main() {
  List<Map<String, dynamic>> delta(String text, {String? size}) => [
        {
          'insert': text,
          if (size != null) 'attributes': {'size': size},
        },
        {'insert': '\n'},
      ];

  group('حجم الخط الرقمي يصل إلى HTML', () {
    test('حجم 18 يُنتج font-size: 18px', () {
      expect(quillDeltaToHtml(delta('نص', size: '18')), contains('font-size: 18px'));
    });

    test('كل حجم في قائمة المحرر يصل فعلاً (عدا «مسح»)', () {
      for (final entry in kQuillFontSizes.entries) {
        if (entry.value == '0') continue; // «مسح» تزيل الحجم عمداً
        final html = quillDeltaToHtml(delta('نص', size: entry.value));
        expect(html, contains('font-size: ${entry.value}px'),
            reason: 'الحجم «${entry.key}» لا يصل إلى الـHTML');
      }
    });

    test('«مسح» (القيمة 0) لا تُنتج حجماً', () {
      expect(quillDeltaToHtml(delta('نص', size: '0')), isNot(contains('font-size')));
    });

    test('نص بلا حجم لا يُنتج حجماً', () {
      expect(quillDeltaToHtml(delta('نص')), isNot(contains('font-size')));
    });
  });

  group('قائمة الأحجام', () {
    test('كلها أرقام صالحة (لا أحجام مسمّاة متبقّية)', () {
      for (final v in kQuillFontSizes.values) {
        expect(double.tryParse(v), isNotNull, reason: 'القيمة «$v» ليست رقماً');
      }
    });

    test('تغطّي المدى الذي طلبه المالك (من 8 إلى 24 على الأقل)', () {
      final sizes = kQuillFontSizes.values.map(double.parse).where((v) => v > 0).toList();
      expect(sizes.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(8));
      expect(sizes.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(24));
    });
  });
}
