import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dms_app/core/system_status.dart';
import 'package:dms_app/main.dart';

/// حالة نظامٍ ساكنة — **لا تستطلع الخادم** (الاختبار بلا شبكة، ومؤقّتُ طلبٍ معلّق يُسقطه).
class _QuietStatus extends SystemStatusNotifier {
  @override
  SystemView build() => const SystemView();
}

void main() {
  testWidgets('يقلع التطبيق ويبني الجذر', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [systemStatusProvider.overrideWith(_QuietStatus.new)],
      child: const DmsApp(),
    ));
    await tester.pump();
    expect(find.byType(DmsApp), findsOneWidget);
  });
}
