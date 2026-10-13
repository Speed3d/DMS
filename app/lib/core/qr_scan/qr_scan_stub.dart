import 'package:flutter/widgets.dart';

import 'qr_scan_types.dart';

/// خارج المتصفّح لا كاميرا — والشاشة تُخفي خيارها وتُبقي اللصق.
bool get qrCameraSupported => false;

/// لا يُستدعى خارج المتصفّح (الشاشة لا تعرض الزرّ) — وإن استُدعي أعلن عدم الدعم.
Future<String?> decodeQrFromPhoto({required bool capture}) async => throw const QrScanError(QrScanFailure.unsupported);

class QrCameraView extends StatelessWidget {
  const QrCameraView({super.key, required this.onDetected, required this.onError, this.onCameras, this.front = false});
  final ValueChanged<String> onDetected;
  final ValueChanged<QrScanError> onError;

  /// عدد كاميرات الجهاز (يظهر زرّ التبديل حين يزيد على واحدة).
  final ValueChanged<int>? onCameras;

  /// الكاميرا الأمامية بدل الخلفية.
  final bool front;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
