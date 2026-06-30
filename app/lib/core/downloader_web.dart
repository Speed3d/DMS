// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// تنزيل ملف في المتصفح عبر Blob + رابط تنزيل.
Future<void> downloadBytes(List<int> bytes, String filename, String mime) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}
