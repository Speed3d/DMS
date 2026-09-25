import 'dart:async';
import 'dart:typed_data';

import 'api_client.dart';
import 'job_watcher.dart';

/// يعيد تقطيع تدفّق بايتاتٍ إلى قطعٍ بحجمٍ ثابت (**والأخيرة أصغر**) — **دالّةٌ نقيّة** تُختبر.
///
/// 🔑 المتصفّح يعطي الملف بقطعٍ صغيرةٍ غير منتظمة؛ والخادم ينتظر قطعاً بترتيبٍ وحجمٍ معروف.
/// ⚠️ **لا يُحمَّل الملف كلُّه في الذاكرة** — قطعةٌ واحدة في كل لحظة (عكس G24).
Stream<Uint8List> rechunk(Stream<List<int>> source, int size) async* {
  assert(size > 0);
  final buffer = BytesBuilder(copy: false);
  await for (final part in source) {
    var offset = 0;
    while (offset < part.length) {
      final take = (size - buffer.length).clamp(0, part.length - offset);
      buffer.add(part.sublist(offset, offset + take));
      offset += take;
      if (buffer.length == size) yield buffer.takeBytes();
    }
  }
  if (buffer.length > 0) yield buffer.takeBytes();
}

/// يرفع نسخةً من جهاز المستخدم ثم يبدأ فحصها في الخادم ويعيد عملية الفحص (ADR-055).
///
/// [onProgress]: نسبة الرفع (0..1). ⚠️ **كلُّ قطعةٍ تُعاد حتى 3 مرّات** عند انقطاعٍ عابر — والخادم
/// يتجاهل قطعةً وصلت من قبل، فالإعادة آمنة. **وأيُّ فشلٍ نهائيّ يُلغي الرفع** فلا يبقى نصفُ ملفٍّ.
Future<JobInfo> uploadBackupFile(
  ApiClient api, {
  required String fileName,
  required int sizeBytes,
  required Stream<List<int>> content,
  void Function(double progress)? onProgress,
  Duration retryDelay = const Duration(seconds: 3),
}) async {
  final session = await api.backupUploadStart(fileName, sizeBytes);
  var sent = 0;
  var index = 0;
  try {
    await for (final chunk in rechunk(content, session.chunkSize)) {
      for (var attempt = 1;; attempt++) {
        try {
          await api.backupUploadChunk(session.uploadId, index, chunk);
          break;
        } on ApiException catch (e) {
          if (!e.isNetworkError || attempt >= 3) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
      index++;
      sent += chunk.length;
      onProgress?.call(sizeBytes == 0 ? 1 : sent / sizeBytes);
    }
    return await api.backupUploadComplete(session.uploadId);
  } catch (_) {
    try { await api.backupUploadAbort(session.uploadId); } catch (_) {}
    rethrow;
  }
}
