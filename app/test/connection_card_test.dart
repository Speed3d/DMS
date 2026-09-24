import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/system_status.dart';

/// بطاقة الاتصال في الشريط الجانبيّ — **من حالةٍ حقيقية** (كانت تقول دائماً «جميع البيانات محدّثة»).
void main() {
  test('🔴 متصلٌ بلا مسوّدات فقط ⇒ «وصل كلُّ شيء»', () {
    final c = connectionSummary(SystemPhase.ok, 0);
    expect(c.tone, ConnectionTone.ok);
    expect(c.body, contains('وصل'));
  });

  test('🔴 متصلٌ ومسوّداتٌ تنتظر ⇒ لا يقول «وصل»', () {
    for (final n in [1, 2, 5]) {
      final c = connectionSummary(SystemPhase.ok, n);
      expect(c.tone, ConnectionTone.attention, reason: '$n');
      expect(c.body, isNot(contains('وصل')), reason: 'طمأنةٌ كاذبة — $n مسوّدة لم تُرسَل');
      expect(c.body, contains('مسوّداتي'));
    }
    expect(connectionSummary(SystemPhase.ok, 2).body, contains('مسوّدتان'));
  });

  test('لا اتصال ⇒ «يُحفظ على هذا الجهاز»', () {
    final c = connectionSummary(SystemPhase.unreachable, 0);
    expect(c.tone, ConnectionTone.down);
    expect(c.body, contains('يُحفظ على هذا الجهاز'));
  });

  test('الاستعادة والإيقاف لا يقولان «متصل»', () {
    expect(connectionSummary(SystemPhase.restoring, 0).title, isNot('متصل'));
    expect(connectionSummary(SystemPhase.lockdown, 0).title, isNot('متصل'));
    expect(connectionSummary(SystemPhase.lockdown, 3).body, contains('3 مسوّدات'));
  });
}
