// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:dio/dio.dart';

/// رقم البناء المنشور الآن على الخادم — من `version.json` الذي يكتبه `flutter build web`
/// (`build_number` = `--build-number`). **وبلا ذاكرة مؤقتة** (`?t=`) وإلا قرأنا القديم.
Future<String?> fetchDeployedBuild() async {
  try {
    final res = await Dio().get<dynamic>(
      Uri.base.resolve('version.json').toString(),
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
    );
    final data = res.data;
    return data is Map ? data['build_number']?.toString() : null;
  } catch (_) {
    return null;
  }
}

void reloadPage() => html.window.location.reload();
