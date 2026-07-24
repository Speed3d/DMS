import 'dart:io';

/// حفظ نسخة محلية من الكتاب المعتمد على جهاز المستخدم (سطح المكتب).
///
/// Hint: نسخة **اطلاع لا سجل رسمي** — الأصل يبقى في السيرفر بختمه ورقمه وتوقيعه.
///       المسار: المستندات\DMS\<القسم>\<السنة>\ — منظّم ليسهل على المستخدم إيجاده لاحقاً.
///       يعيد المسار الكامل عند النجاح، أو null عند التعذّر (لا نُفشل عملية الاعتماد بسبب نسخة محلية).
Future<String?> saveLocalCopy(List<int> bytes, String fileName, String section) async {
  try {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;

    final sep = Platform.pathSeparator;
    final dir = Directory('$home${sep}Documents${sep}DMS$sep$section$sep${DateTime.now().year}');
    await dir.create(recursive: true);

    final safeName = _sanitize(fileName);
    final file = File('${dir.path}$sep$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    // Hint: الحفظ المحلي إضافة راحة — فشله لا يعني فشل الاعتماد.
    return null;
  }
}

/// يزيل المحارف الممنوعة في أسماء ملفات ويندوز (Hint: أرقام الكتب تحوي شرطات فقط، لكن الموضوع قد يُضاف لاحقاً).
String _sanitize(String name) => name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
