import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// تغطية النسخ الاحتياطي — **للسوبر أدمن وحده** (طلب المالك 2026-09-09).
///
/// 🔴 **لماذا مزوّدٌ عامّ لا حالةٌ داخل شاشة النسخ؟** لأن التنبيه صار يظهر **خارجها**:
/// شارةً في القائمة الجانبية وأيقونةً في الشريط العلوي. وحالةٌ محبوسةٌ في شاشةٍ لا يراها
/// إلا من فتحها — **والتذكير الذي لا يُرى ليس تذكيراً**.
///
/// 🔐 **ولا يُطلب إلا للسوبر أدمن**: النقطة `/backup/coverage` مقصورةٌ عليه، وطلبٌ نعلم
/// أنه سيُردّ بـ403 ضجيجٌ في السجلّ وخطأٌ يراه المستخدم بلا سبب.
///
/// ⚠️ **ويُراقَب المصدر المتزامن (الجلسة) وحده** — لا مزوّدَ غير متزامنٍ آخر. مزوّدٌ غير
/// متزامن يراقب نظيره يُبطل نفسه، ولو وقع ذلك أثناء استئناف اشتراكٍ موقوف في طور البناء
/// **سقط الرسم** (العلّة المعالجة في `profile_providers.dart`، وحارسُها في
/// `test/provider_resume_test.dart`).
final backupCoverageProvider =
    FutureProvider.autoDispose<BackupCoverage?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.auth?.isSuperAdmin != true) return null;
  return ref.read(apiClientProvider).backupCoverage();
});

/// هل تأخّرت النسخة الكاملة؟ — **مشتقٌّ متزامن** يقرؤه الشريط الجانبي والعلوي.
///
/// ⚠️ **`Ok` و«لم تصل بعد» كلاهما «لا تنبيه»** — فلا تُومض الشارة أثناء التحميل ثم تختفي.
/// و**الدرجات الثلاث تُنقَل كما هي** (`Soon`/`Urgent`/`Overdue`) لأن اللون يتصاعد معها:
/// تنبيهٌ بلونٍ واحد لا يفرّق بين «اقترب الموعد» و«مضى شهران».
final backupAlertProvider = Provider.autoDispose<BackupCoverage?>((ref) {
  final c = ref.watch(backupCoverageProvider).asData?.value;
  if (c == null || c.isOk) return null;
  return c;
});
