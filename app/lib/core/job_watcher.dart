import 'dart:async';

import 'api_client.dart';

/// حالة عمليةٍ طويلة تجري في الخادم (نسخ · مرآة · استعادة · حذف شركة).
///
/// 🔴 **لماذا في الخلفية؟** خلف Cloudflare يُقطع كلُّ طلبٍ لا يردّ خلال ~100 ثانية (الخطأ 524).
/// وكانت هذه العمليات تجري **داخل الطلب** — فيرى المالك «فشلاً» والعملية ربما ما زالت تعمل،
/// فيُعيدها فتعمل مرّتين. الآن يبدأ الزرّ العملية ويعود **فوراً**، والشاشة تتابعها.
class JobInfo {
  final String id;
  final String kind;
  final String title;

  /// `Running` · `Succeeded` · `Failed`.
  final String state;
  final String? stage;

  /// نسبةٌ من 0 إلى 100، أو `null` حين لا تُعرف (يُرسم شريطٌ غير محدَّد).
  final int? percent;
  final String? message;

  /// حصيلة العملية عند نجاحها — كما أرسلها الخادم.
  final Object? result;

  const JobInfo({
    required this.id,
    required this.kind,
    required this.title,
    required this.state,
    this.stage,
    this.percent,
    this.message,
    this.result,
  });

  bool get isRunning => state == 'Running';
  bool get succeeded => state == 'Succeeded';

  factory JobInfo.fromJson(Map<String, dynamic> j) => JobInfo(
        id: j['id'].toString(),
        kind: j['kind']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        state: j['state']?.toString() ?? 'Running',
        stage: j['stage']?.toString(),
        percent: (j['percent'] as num?)?.toInt(),
        message: j['message']?.toString(),
        result: j['result'],
      );

  /// حالةٌ محلية تُعرض أثناء الصيانة — **لا تأتي من الخادم** لأنه يردّ 503 على كل شيء حينها.
  JobInfo during(String stage) => JobInfo(
      id: id, kind: kind, title: title, state: 'Running', stage: stage, percent: null);
}

/// يتابع عمليةً حتى تنتهي ويعيد حالتها الأخيرة — **نجحت أو فشلت**؛ ويرمي حين تضيع.
///
/// ⚠️ **أثناء الاستعادة يردّ الخادم 503 على كل طلب** (وضع الصيانة). فحينها تُسأل
/// `/system/status` **العامّة وحدها** حتى يعود — ولا يُسأل شيءٌ يحتاج الرمز: لو انتهت
/// صلاحيته في منتصف الاستعادة لحاول العميل تجديده، **والتجديد مرفوضٌ في الصيانة، فيُخرَج
/// المستخدم من النظام**.
///
/// ⚠️ **وانقطاعٌ عابر في الشبكة لا يُعلن الفشل** — يُعاد السؤال حتى [maxNetworkErrors] مرّة
/// متتالية، لأن العملية تجري في الخادم ولا يوقفها انقطاعُ من يتابعها.
Future<JobInfo> watchJob(
  ApiClient api,
  JobInfo start, {
  void Function(JobInfo)? onUpdate,
  Duration interval = const Duration(seconds: 2),
  int maxNetworkErrors = 30,
}) async {
  var current = start;
  var networkErrors = 0;
  while (true) {
    try {
      current = await api.job(current.id);
      networkErrors = 0;
      onUpdate?.call(current);
      if (!current.isRunning) return current;
    } on ApiException catch (e) {
      if (e.status == 503) {
        onUpdate?.call(current.during('النظام متوقّف مؤقتاً لإتمام العملية — سيعود وحده…'));
        await _waitMaintenanceOver(api, interval);
        continue;
      }
      if (e.status == 404) {
        throw ApiException(404,
            'انقطعت متابعة العملية — ربما أُعيد تشغيل الخادم أثناءها. حدّث الصفحة وتحقّق من النتيجة، ثم أعد المحاولة إن لزم.');
      }
      if (e.isNetworkError && ++networkErrors < maxNetworkErrors) {
        onUpdate?.call(current.during('انقطع الاتصال بالخادم — العملية مستمرّة هناك، وجارٍ إعادة المحاولة…'));
      } else {
        rethrow;
      }
    }
    await Future<void>.delayed(interval);
  }
}

Future<void> _waitMaintenanceOver(ApiClient api, Duration interval) async {
  while (true) {
    await Future<void>.delayed(interval);
    try {
      if (!await api.isUnderMaintenance()) return;
    } on ApiException {
      // الخادم غير متاحٍ لحظياً — نواصل الانتظار.
    }
  }
}
