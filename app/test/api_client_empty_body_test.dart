import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';

/// ⚠️ **استجابة حقيقية مُلتقَطة من الخادم حرفياً** (`GET /api/payroll/periods/2026/9`)،
/// لا نصّاً كتبتُه من فهمي للعقد.
///
/// سببُ الإصرار على ذلك: أول نسخة من هذا الاختبار كانت تصنع الجسم يدوياً بـ
/// `'rowVersion': [9, 9]` — فصادقت **افتراضي** لا **الخادم**، ومرّت خضراء بينما
/// التطبيق ينهار عند المالك بـ
/// `type 'String' is not a subtype of type 'Iterable<dynamic>'`،
/// لأن `byte[]` في ASP.NET Core يُسلسَل **نصّاً بـbase64** لا مصفوفةَ أرقام.
/// **العيّنة تأتي من الخادم أو لا تأتي.**
const String kRealPeriodJson = '''
{"periodId":9,"year":2026,"month":9,"monthName":"أيلول","status":"Draft",
"exchangeRate":null,"workingDaysMode":"Fixed","workingDays":30,"paidAt":null,
"outgoingBookId":null,"manualBookNumber":null,"notes":null,
"rowVersion":"AAAAAAAApBE=","totalIqd":1200000.00,
"entries":[{"entryId":17,"employeeCompanyId":1,"employeeId":1,"displayOrder":1,
"name":"سنان الجبوري","position":"مهندس","currency":"IQD","baseSalary":1200000.00,
"eligibleDays":30,"absenceDays":0,"bonusAmount":null,"deductionAmount":null,
"absenceDeduction":0.00,"absenceDeductionIsManual":false,"endOfServiceAmount":null,
"netSalary":1200000.00,"netSalaryIqd":1200000.00,"paymentStatus":"Unpaid",
"paidByCompanyId":null,"paidByCompanyName":null,"isNewHire":false,
"isTerminated":false,"notes":null},
{"entryId":18,"employeeCompanyId":2,"employeeId":2,"displayOrder":2,
"name":"جون سميث","position":"سائق","currency":"USD","baseSalary":700.00,
"eligibleDays":30,"absenceDays":0,"bonusAmount":null,"deductionAmount":null,
"absenceDeduction":0.00,"absenceDeductionIsManual":false,"endOfServiceAmount":null,
"netSalary":700.00,"netSalaryIqd":0.00,"paymentStatus":"Unpaid",
"paidByCompanyId":null,"paidByCompanyName":null,"isNewHire":false,
"isTerminated":false,"notes":null}]}
''';

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

      // الشهر 2 منشأ ⇒ **الاستجابة الحقيقية المُلتقَطة من الخادم حرفياً** (لا مصنوعة يدوياً).
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(kRealPeriodJson);
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

  test('استجابة الخادم الحقيقية تُحوَّل كاملةً بلا خسارة', () async {
    final p = await api.payrollPeriod(2026, 2);
    expect(p, isNotNull);
    expect(p!.year, 2026);
    expect(p.month, 9);
    expect(p.workingDays, 30);
    expect(p.entries.length, 2);
    expect(p.totalIqd, 1200000);

    // 🔴 الحقل الذي أسقط الشاشة: `byte[]` يصل **نصّاً بـbase64** لا مصفوفةَ أرقام.
    expect(p.rowVersion, 'AAAAAAAApBE=');
    expect(p.rowVersion, isA<String>());

    // وسطرٌ بالدولار بلا سعر صرف: الصافي بعملته صحيح والمعادل صفرٌ مؤقّت.
    final usd = p.entries.firstWhere((e) => e.isUsd);
    expect(usd.netSalary, 700);
    expect(usd.netSalaryIqd, 0);
    expect(p.needsExchangeRate, isTrue);
  });

  test('بحث بهوية غير موجودة (204): يعود null ولا يرمي', () async {
    final hint = await api.lookupEmployee('000');
    expect(hint, isNull);
  });
}
