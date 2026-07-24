import 'downloader_web.dart';

/// حفظ نسخة محلية من الكتاب المعتمد (نسخة الويب).
///
/// Hint: المتصفح لا يسمح بالكتابة في مجلد يختاره التطبيق — يُنزّل الملف لمجلد التنزيلات
///       الافتراضي للمستخدم، وهو يفي بالغرض (نسخة على جهازه). نعيد null لأن المسار غير معروف
///       للتطبيق، فتعرض الواجهة رسالة عامة بدل مسار محدّد.
Future<String?> saveLocalCopy(List<int> bytes, String fileName, String section) async {
  await downloadBytes(bytes, fileName, 'application/pdf');
  return null;
}
