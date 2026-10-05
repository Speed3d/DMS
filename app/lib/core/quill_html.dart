import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'book_table/table_serializer.dart';

/// تحويل محتوى محرّر Quill (Delta) إلى HTML يفهمه مولّد الـ PDF في الباك-إند.
///
/// Hint: موحَّد في مكان واحد لأن ثلاث شاشات تستخدمه (إنشاء صادر · تعديل مسودة · تعديل بعد الاعتماد)،
///       وأي اختلاف بينها يعني أن التنسيق يظهر في شاشة ويختفي في أخرى.
String quillDeltaToHtml(List<dynamic> deltaJson) {
  final converter = QuillDeltaToHtmlConverter(
    deltaJson.cast<Map<String, dynamic>>(),
    ConverterOptions(
      converterOptions: OpConverterOptions(
        inlineStylesFlag: true,
        // Hint: المحوّل يعرف الأحجام المسمّاة فقط (small/large/huge) ويُسقط أي قيمة رقمية
        //       بصمت — فيظهر للمستخدم أن «حجم الخط لا يُحفظ». نعوّضها هنا يدوياً.
        customCssStyles: _numericFontSizeStyle,
      ),
      sanitizerOptions: OpAttributeSanitizerOptions(allow8DigitHexColors: true),
    ),
  );
  // ADR-057: الجدول المضمَّن ⟵ وسمٌ واحد يحمل نموذجه — بلا هذا يُسقطه المحوّل بصمت ويُطبع الكتاب بلا جدوله.
  converter.renderCustomWith = (customOp, contextOp) {
    final insert = customOp.insert;
    if (insert.type != kDmsTableEmbed) return '';
    try {
      return BtJson.htmlTag(BtJson.fromEmbedData(insert.value));
    } catch (_) {
      return ''; // بلوكٌ تالف لا يُسقط الكتاب كلَّه — والخادم يرفض ما لا يُقرأ بقواعده
    }
  };
  return converter.convert();
}

/// يحوّل حجم الخط الرقمي (مثل "12") إلى نمط CSS صريح **بالنقاط** — كما في Word (ADR-057، قرار المالك).
/// Hint: الأحجام المسمّاة يتكفّل بها المحوّل نفسه، فنتجاهلها هنا كي لا نكرّرها.
/// ⚠️ كانت «بكسل» يضربها الخادم في 0.75 فيخرج 12 كأنه 9 — والمسوّدات القديمة (`px`) يبقى الخادم يقرؤها صحيحة.
List<String>? _numericFontSizeStyle(DeltaInsertOp op) {
  final size = op.attributes.size;
  if (size == null || size.isEmpty) return null;

  final numeric = double.tryParse(size);
  if (numeric == null || numeric <= 0) return null; // مسمّى (small/large/huge) أو "0" للمسح

  return ['font-size: ${size}pt'];
}
