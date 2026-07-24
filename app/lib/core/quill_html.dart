import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

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
  return converter.convert();
}

/// يحوّل حجم الخط الرقمي (مثل "18") إلى نمط CSS صريح.
/// Hint: الأحجام المسمّاة يتكفّل بها المحوّل نفسه، فنتجاهلها هنا كي لا نكرّرها.
List<String>? _numericFontSizeStyle(DeltaInsertOp op) {
  final size = op.attributes.size;
  if (size == null || size.isEmpty) return null;

  final numeric = double.tryParse(size);
  if (numeric == null || numeric <= 0) return null; // مسمّى (small/large/huge) أو "0" للمسح

  // px هي وحدة أزرار الحجم الرقمية في المحرر، والباك-إند يحوّلها إلى نقاط PDF.
  return ['font-size: ${size}px'];
}
