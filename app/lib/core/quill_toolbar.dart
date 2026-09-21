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
///
/// 🔴 **أزرارٌ أصغر — بلاغ المالك (2026-09-21): الشريط يأكل مساحة المحرر.**
/// والتقليصُ في **المقاس لا في الوظائف**، ولم يُحذف زرٌّ واحد: حذفُ الأزرار يوفّر
/// مساحةً اليوم و**يكلّف بلاغاً غداً** حين يحتاجها المستخدم ولا يجدها.
///
/// افتراضات `flutter_quill`: أيقونة **15** وعاملُ زرّ **1.6** ⇒ زرٌّ **24** بكسلاً.
/// وصارت **13 × 1.45 ⇒ 18.85** — أي **~21٪ أقصر في كل صفّ**.
/// ⚠️ **ولم أنزل أكثر**: الزرُّ هدفُ نقرٍ بالفأرة، وتصغيرُه دون ~18 بكسلاً يجعل
/// الإصابة تحتاج تصويباً — **ومساحةٌ تُكسب بخطأٍ في النقر ليست مكسباً**.
const kQuillButtonOptions = quill.QuillSimpleToolbarButtonOptions(
  base: quill.QuillToolbarBaseButtonOptions(
    iconSize: 13,
    iconButtonFactor: 1.45,
  ),
  fontFamily: quill.QuillToolbarFontFamilyButtonOptions(
    renderFontFamilies: false,
    items: kQuillFontFamilies,
  ),
  fontSize: quill.QuillToolbarFontSizeButtonOptions(
    items: kQuillFontSizes,
  ),
);

/// الإعداد الكامل لشريط أدوات تحرير متن الكتاب.
///
/// 🔴 **صُغِّر بطلب المالك (2026-09-21)** — والمكسبُ الأكبر ليس في حجم الزرّ بل في
/// **عدد الصفوف**: `multiRowsDisplay` يلفّ الأزرار في `Wrap`، فكلُّ ما يُضيّق العنصر
/// يُدخل أزراراً أكثر في الصفّ **فيسقط صفٌّ كامل دفعةً واحدة**.
///
/// ⚠️ **ولم يُجعَل `multiRowsDisplay: false`** — يصير الشريط صفّاً واحداً يُمرَّر أفقياً،
/// فيختفي نصفُ الأزرار خلف حافةٍ **لا يعرف المستخدم أن خلفها شيئاً**. وإخفاءُ أداةٍ
/// أسوأ من إظهارها صغيرة.
///
/// و`showDividers: false`: الفواصلُ زينةٌ تأخذ عرضاً، **والأقسام تتمايز بالتباعد**.
const kQuillToolbarConfig = quill.QuillSimpleToolbarConfig(
  multiRowsDisplay: true,
  showDividers: false,
  toolbarSectionSpacing: 2,
  toolbarRunSpacing: 2,
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
