import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/upload_batches.dart';
import 'package:dms_app/models.dart';

/// حرّاس **تقسيم الاستيراد بالجملة** — Cloudflare يرفض كلَّ طلبٍ فوق 100 ميغابايت (413)،
/// والاستيراد كان يُرسل حتى 600 ميغابايت في طلبٍ واحد.
void main() {
  const mb = 1024 * 1024;
  List<int> sizesOf(List<List<int>> b) => [for (final x in b) x.fold(0, (s, v) => s + v)];

  test('لا دفعةَ تتجاوز الحدّ — والترتيب محفوظ', () {
    final files = [10 * mb, 20 * mb, 15 * mb, 5 * mb, 30 * mb, 1 * mb];
    final b = splitIntoBatches(files, (f) => f, maxBytes: 40 * mb);
    expect(b, [[10 * mb, 20 * mb], [15 * mb, 5 * mb], [30 * mb, 1 * mb]]);
    expect(sizesOf(b).every((s) => s <= 40 * mb), isTrue);
    expect(b.expand((x) => x).toList(), files, reason: 'التقرير يسرد الملفات كما اختارها المستخدم');
  });

  test('ملفٌّ أكبر من الحدّ يذهب وحده — لا يُرفض هنا ولا يُدمج بغيره', () {
    final b = splitIntoBatches([5 * mb, 48 * mb, 5 * mb], (f) => f, maxBytes: 40 * mb);
    expect(b, [[5 * mb], [48 * mb], [5 * mb]]);
  });

  test('سقف عدد الملفات في الدفعة يُحترم ولو كانت صغيرة', () {
    final b = splitIntoBatches(List.filled(120, 1024), (f) => f, maxFiles: 50);
    expect(b.map((x) => x.length).toList(), [50, 50, 20]);
  });

  test('الحدّ الافتراضيّ تحت حدّ Cloudflare بهامشٍ واضح', () {
    expect(kMaxUploadBatchBytes, lessThanOrEqualTo(50 * mb));
    expect(kMaxUploadBatchFiles, 50, reason: 'مرآةٌ لسقف الخادم في ArchiveController');
  });

  test('قائمةٌ فارغة ⇒ لا دفعات (لا طلبٌ فارغ)', () {
    expect(splitIntoBatches(<int>[], (f) => f), isEmpty);
  });

  test('دمجُ الحصائل يعطي تقريراً واحداً كأنها دفعةٌ واحدة', () {
    BulkImportRow row(String n, bool ok) => BulkImportRow.fromJson(
        {'fileName': n, 'ok': ok, 'archiveId': ok ? 1 : null, 'number': null, 'title': n, 'needsTitle': false, 'error': ok ? null : 'x'});
    final a = BulkImportResult(total: 2, created: 2, failed: 0, needTitleCount: 1, rows: [row('أ', true), row('ب', true)]);
    final b = BulkImportResult(total: 1, created: 0, failed: 1, needTitleCount: 0, rows: [row('ج', false)]);
    final m = mergeBulkResults([a, b]);
    expect([m.total, m.created, m.failed, m.needTitleCount], [3, 2, 1, 1]);
    expect(m.rows.map((r) => r.fileName).toList(), ['أ', 'ب', 'ج']);
  });
}
