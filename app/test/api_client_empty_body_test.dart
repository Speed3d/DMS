import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';

/// اختبار تكامل حقيقي لـ[ApiClient] أمام خادم يردّ **204 No Content** — وهو ما يفعله
/// ASP.NET Core عند `Ok(null)`.
///
/// ⚠️ **سبب وجوده:** أبلغ المالك (2026-08-04) أن فتح أول شهر في نظامٍ بلا كشوف يُسقط
/// الشاشة بـ`type 'String' is not a subtype of type 'Map<String, dynamic>'` — لأن الجسم
/// الفارغ يصل من Dio **نصّاً `''` لا `null`**، فيمرّ من فحص `data == null` ثم ينهار
/// التحويل **قبل أن يظهر زرّ «توليد كشف الشهر»** الذي يصحّح الحال.
///
/// اختبار الوحدة على الحارس وحده لا يكفي هنا: العطب كان في **سلوك Dio أمام 204**،
/// وهو ما لا يظهر إلا بخادمٍ حقيقي يردّ 204 فعلاً.
void main() {
  late HttpServer server;
  late ApiClient api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;

      // الشهر 1 غير منشأ، والهوية 000 غير موجودة ⇒ 204 بجسم فارغ (سلوك Ok(null)).
      if (path.endsWith('/payroll/periods/2026/1') || req.uri.query.contains('000')) {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      // الشهر 2 منشأ ⇒ كشف حقيقي.
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'periodId': 7, 'year': 2026, 'month': 2, 'monthName': 'شباط',
          'status': 'Draft', 'exchangeRate': 1310, 'workingDaysMode': 'Fixed',
          'workingDays': 30, 'rowVersion': [9, 9], 'totalIqd': 1200000,
          'entries': const <dynamic>[],
        }));
      await req.response.close();
    });

    api = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api',
      token: () => 'test-token',
      companyId: () => 1,
    );
  });

  tearDown(() async => server.close(force: true));

  test('شهر غير منشأ (204): يعود null ولا يرمي — فيظهر زرّ التوليد', () async {
    final period = await api.payrollPeriod(2026, 1);
    expect(period, isNull);
  });

  test('شهر منشأ: يُحوَّل كاملاً', () async {
    final period = await api.payrollPeriod(2026, 2);
    expect(period, isNotNull);
    expect(period!.year, 2026);
    expect(period.month, 2);
    expect(period.workingDays, 30);
    expect(period.rowVersion, [9, 9]);
  });

  test('بحث بهوية غير موجودة (204): يعود null ولا يرمي', () async {
    final hint = await api.lookupEmployee('000');
    expect(hint, isNull);
  });
}
