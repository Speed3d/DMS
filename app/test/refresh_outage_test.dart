import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';

/// 🔴 **فشلُ التجديد لأن الخادم غائب لا يُخرج المستخدم** (ADR-050) — أمام خادمٍ حقيقيّ.
///
/// ⚠️ **في ملفٍّ مستقلّ بلا `testWidgets`**: ربطُ اختبارات الودجات يستبدل `HttpClient` بمحاكٍ
/// يردّ 400 على كل شيء، فلو اجتمعا في ملفٍّ واحد لاختُبر المحاكي لا الشبكة.
void main() {
  // ───────────────────────── تكاملٌ أمام خادمٍ حقيقي ─────────────────────────
  // ⚠️ **خادمٌ حقيقيّ لا محاكاة**: العيب في سلوك الاعتراض أمام ردودٍ فعلية (سابقة
  //    `api_client_empty_body_test`) — وإلا صادق الاختبارُ افتراضي لا الشبكة.
  group('التجديد أمام خادمٍ متوقّف', () {
    late HttpServer server;
    late int refreshStatus;
    late String refreshBody;
    late int dataStatus;
    late String dataBody;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final isRefresh = req.uri.path.endsWith('/auth/refresh');
        req.response.statusCode = isRefresh ? refreshStatus : dataStatus;
        req.response.headers.contentType =
            (isRefresh ? refreshBody : dataBody).startsWith('{') ? ContentType.json : ContentType.html;
        req.response.write(isRefresh ? refreshBody : dataBody);
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<({ApiException err, int logouts, int signals})> call() async {
      var logouts = 0, signals = 0;
      final api = ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}/api',
        token: () => 'expired',
        companyId: () => 1,
        refreshToken: () => 'r',
        onRefreshFailed: () async => logouts++,
        onSystemSignal: () => signals++,
      );
      try {
        await api.entities();
        fail('كان يجب أن يفشل');
      } on ApiException catch (e) {
        return (err: e, logouts: logouts, signals: signals);
      }
    }

    test('🔴 التجديد يُردّ 503 صيانةً ⇒ لا خروج، والخطأ صيانة', () async {
      dataStatus = 401;
      dataBody = '';
      refreshStatus = 503;
      refreshBody = '{"error":"النظام متوقّف للتحديث","maintenance":true,"lockdown":true}';
      final r = await call();
      expect(r.logouts, 0, reason: 'الجلسة سليمة — الخادم هو المتوقّف');
      expect(r.err.isMaintenance, isTrue);
      expect(r.err.message, 'النظام متوقّف للتحديث');
      expect(r.signals, greaterThan(0), reason: 'طبقة الحالة تُسأل فوراً');
    });

    test('🔴 التجديد يُردّ 502 من Cloudflare ⇒ لا خروج، والخطأ انقطاع', () async {
      dataStatus = 401;
      dataBody = '';
      refreshStatus = 502;
      refreshBody = '<html>Bad gateway</html>';
      final r = await call();
      expect(r.logouts, 0);
      expect(r.err.isNetworkError, isTrue);
    });

    test('التجديد يُرفض 403 ⇒ خروجٌ فعلاً (الحارس يفرّق لا يمنع الخروج كلّه)', () async {
      dataStatus = 401;
      dataBody = '';
      refreshStatus = 403;
      refreshBody = '{"error":"جلسة منتهية. سجّل الدخول مجدداً."}';
      final r = await call();
      expect(r.logouts, 1);
    });

    test('503 إيقافٌ مباشر على طلبٍ عاديّ ⇒ صيانة لا خطأ', () async {
      dataStatus = 503;
      dataBody = '{"error":"متوقّف","maintenance":true,"lockdown":true}';
      final r = await call();
      expect(r.err.isMaintenance, isTrue);
      expect(r.err.isNetworkError, isFalse);
      expect(r.logouts, 0);
    });
  });
}
