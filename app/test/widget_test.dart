import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dms_app/main.dart';

void main() {
  testWidgets('يقلع التطبيق ويبني الجذر', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DmsApp()));
    await tester.pump();
    expect(find.byType(DmsApp), findsOneWidget);
  });
}
