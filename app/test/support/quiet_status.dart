import 'package:dms_app/core/system_status.dart';

/// حالة نظامٍ ساكنة — **لا تستطلع الخادم**. كلُّ اختبارٍ يبني الشريط الجانبيّ أو `DmsApp`
/// يحتاجها (ADR-050/G19): بطاقة الاتصال تقرأ `systemStatusProvider`، وبلا هذا يبقى مؤقّتُ
/// طلبِ الاستطلاع معلّقاً فيسقط الاختبار **بلا عيبٍ في الشاشة**.
class QuietSystemStatus extends SystemStatusNotifier {
  QuietSystemStatus([this._view = const SystemView()]);
  final SystemView _view;

  @override
  SystemView build() => _view;
}

final quietSystemStatus = systemStatusProvider.overrideWith(QuietSystemStatus.new);
