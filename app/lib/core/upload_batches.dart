import '../models.dart';

/// أقصى حجمٍ لطلب رفعٍ واحد — **تحت حدّ Cloudflare (100 ميغابايت للطلب في الخطة المجانية)**
/// بهامشٍ لترويسات الـmultipart ولبطء الاتصال.
///
/// 🔴 **لماذا؟** الاستيراد بالجملة كان يُرسل الدفعة كلّها (حتى 600 ميغابايت) في طلبٍ واحد —
/// ويعمل تماماً على جهاز التطوير، **ويرفضه Cloudflare بالخطأ 413 قبل أن يصل الخادم**.
const int kMaxUploadBatchBytes = 40 * 1024 * 1024;

/// سقفُ الملفات في الطلب الواحد — **مرآةٌ لسقف الخادم** (`maxPerBatch` في `ArchiveController`).
const int kMaxUploadBatchFiles = 50;

/// يقسم الملفات إلى دفعاتٍ **متتالية بترتيبها** لا تتجاوز أيٌّ منها [maxBytes] ولا [maxFiles].
///
/// ⚠️ **ملفٌّ أكبر من [maxBytes] وحده يذهب في دفعةٍ وحده** — لا يُرفض هنا: حدُّ الملف الواحد
/// (50 ميغابايت) يفرضه الخادم برسالته العربية، وهو تحت حدّ Cloudflare أصلاً.
/// ⚠️ **والترتيب محفوظ** — فتقرير الاستيراد يسرد الملفات كما اختارها المستخدم.
List<List<T>> splitIntoBatches<T>(
  List<T> items,
  int Function(T) sizeOf, {
  int maxBytes = kMaxUploadBatchBytes,
  int maxFiles = kMaxUploadBatchFiles,
}) {
  final batches = <List<T>>[];
  var current = <T>[];
  var bytes = 0;
  for (final item in items) {
    final size = sizeOf(item);
    final full = current.isNotEmpty && (bytes + size > maxBytes || current.length >= maxFiles);
    if (full) {
      batches.add(current);
      current = <T>[];
      bytes = 0;
    }
    current.add(item);
    bytes += size;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// يدمج حصائل الدفعات في تقريرٍ واحد — **كأنها دفعةٌ واحدة** كما يراها المستخدم.
BulkImportResult mergeBulkResults(List<BulkImportResult> parts) => BulkImportResult(
      total: parts.fold(0, (s, r) => s + r.total),
      created: parts.fold(0, (s, r) => s + r.created),
      failed: parts.fold(0, (s, r) => s + r.failed),
      needTitleCount: parts.fold(0, (s, r) => s + r.needTitleCount),
      rows: [for (final r in parts) ...r.rows],
    );
