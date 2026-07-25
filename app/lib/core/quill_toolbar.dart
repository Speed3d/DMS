import 'package:flutter_quill/flutter_quill.dart' as quill;

/// إعداد موحَّد لشريط أدوات محرّر Quill.
///
/// Hint: كان الإعداد مكرّراً حرفياً في ثلاث شاشات صادر، ورابعة (الأرشيف) بلا إعداد أصلاً
///       فكانت بلا خطوط عربية. التوحيد هنا على نمط [quillDeltaToHtml] — أي اختلاف بين
///       الشاشات يعني أن خياراً يظهر في شاشة ويغيب عن أخرى.

/// أحجام الخط المتاحة في المحرر — **قياسات رقمية** كما في Word و Excel.
///
/// Hint: كانت الأحجام مسمّاة (صغير/كبير/ضخم) وهي ثلاث درجات فقط لا تكفي لضبط كتاب رسمي.
///       الوحدة **px**، ويحوّلها [quillDeltaToHtml] إلى `font-size: Npx` ثم يحوّلها
///       `HtmlToQuestPdf` في الباك-إند إلى نقاط PDF. القيمة `0` تمسح الحجم.
const Map<String, String> kQuillFontSizes = {
  '8': '8', '9': '9', '10': '10', '11': '11', '12': '12',
  '14': '14', '16': '16', '18': '18', '20': '20', '22': '22',
  '24': '24', '28': '28', '32': '32', '36': '36', '48': '48', '72': '72',
  'مسح': '0',
};

/// الخطوط المتاحة — مضمّنة في `Dms.Documents` ليطابق الـPDF ما يراه المستخدم.
const Map<String, String> kQuillFontFamilies = {
  'Amiri': 'Amiri',
  'Cairo': 'Cairo',
  'Arial': 'Arial',
  'Times New Roman': 'Times New Roman',
  'مسح': 'Clear',
};

/// خيارات أزرار الشريط (الخطوط + الأحجام) — تصلح لأي شريط مهما اختلف تخطيطه.
const kQuillButtonOptions = quill.QuillSimpleToolbarButtonOptions(
  fontFamily: quill.QuillToolbarFontFamilyButtonOptions(
    renderFontFamilies: false,
    items: kQuillFontFamilies,
  ),
  fontSize: quill.QuillToolbarFontSizeButtonOptions(
    items: kQuillFontSizes,
  ),
);

/// الإعداد الكامل لشريط أدوات تحرير متن الكتاب.
const kQuillToolbarConfig = quill.QuillSimpleToolbarConfig(
  multiRowsDisplay: true,
  showAlignmentButtons: true,
  showCodeBlock: false,
  showInlineCode: false,
  showQuote: false,
  showClearFormat: false,
  showSearchButton: false,
  showSubscript: false,
  showSuperscript: false,
  showListCheck: false,
  buttonOptions: kQuillButtonOptions,
);
