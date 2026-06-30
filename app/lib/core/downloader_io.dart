import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

/// تنزيل/فتح ملف على سطح المكتب: يُحفظ في مجلد مؤقت ثم يُفتح.
Future<void> downloadBytes(List<int> bytes, String filename, String mime) async {
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  await launchUrl(Uri.file(file.path));
}
