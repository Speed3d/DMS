/// رقم إصدار الواجهة (ADR-054) — يُخبَز عند البناء من ملف `VERSION` في جذر المستودع:
/// `--dart-define=APP_VERSION=<الرقم>` و`--dart-define=APP_COMMIT=<commit>` و`--build-name=<الرقم>`.
///
/// 🔑 **مصدرٌ واحد**: الخادم يقرأ الملف نفسه عند البناء، وحارسٌ (`version_sync_test`) يطابق
/// `pubspec.yaml` به. **فارغٌ في التطوير** (`flutter run` بلا الوسوم) ويُعرض «نسخة تطوير».
const String kAppVersion = String.fromEnvironment('APP_VERSION');

/// رمز الـcommit المختصر لهذه الواجهة — فارغٌ في التطوير.
const String kAppCommit = String.fromEnvironment('APP_COMMIT');

/// ما يُعرض للمستخدم — «الإصدار 0.9.0» أو «نسخة تطوير».
String appVersionLabel([String version = kAppVersion]) =>
    version.isEmpty ? 'نسخة تطوير' : 'الإصدار $version';

/// هل الواجهة والخادم من إصدارين مختلفين؟ — **دالّةٌ نقيّة** (ADR-042).
///
/// 🔴 **اختلافُهما علامةُ تحديثٍ ناقص**: نُشر الخادم ولم تُنشر الواجهة (أو العكس)، أو بقيت صفحةٌ
/// قديمة مفتوحة. ⚠️ **ولا حكمَ بلا الطرفين** — واجهة تطوير بلا رقم، أو خادمٌ لم يُسأل بعد.
bool versionsDiffer(String ui, String? server) =>
    ui.isNotEmpty && server != null && server.isNotEmpty && ui.trim() != server.trim();
