import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'form_drafts.dart';
import 'page_reload.dart';
import 'session.dart';

/// رقم بناء هذه الواجهة — يُخبَز عند البناء بـ`--dart-define=APP_BUILD=<رقم>`، ويساوي
/// `--build-number` نفسه فيحمله `version.json` (ADR-050). **فارغٌ في التطوير** فلا يُقارن شيء.
const String kAppBuild = String.fromEnvironment('APP_BUILD');

/// طور النظام كما تراه الواجهة.
enum SystemPhase {
  /// يعمل.
  ok,

  /// موقوفٌ يدوياً للصيانة — السوبر أدمن وحده يتصفّح.
  lockdown,

  /// استعادة نسخة — محجوبٌ عن الجميع.
  restoring,

  /// الخادم لا يجيب (يُحدَّث · يُعاد تشغيله · لا إنترنت).
  unreachable,
}

/// حالة النظام — **لقطةٌ من آخر سؤال** للخادم.
class SystemView {
  final SystemPhase phase;
  final LockdownInfo lockdown;
  final AnnouncementInfo announcement;

  /// سبب صيانة الاستعادة (من الخادم).
  final String? restoreReason;

  const SystemView({
    this.phase = SystemPhase.ok,
    this.lockdown = LockdownInfo.off,
    this.announcement = AnnouncementInfo.hidden,
    this.restoreReason,
  });

  SystemView copyWith({SystemPhase? phase}) => SystemView(
      phase: phase ?? this.phase,
      lockdown: lockdown,
      announcement: announcement,
      restoreReason: restoreReason);
}

/// الطور من ردّ الخادم — **دالّةٌ نقيّة** تُختبر وحدها.
SystemPhase phaseOf(SystemStatusInfo s) => s.maintenance
    ? SystemPhase.restoring
    : s.lockdown.active
        ? SystemPhase.lockdown
        : SystemPhase.ok;

/// هل تُحجب الشاشة عن هذا المستخدم؟ — **دالّةٌ نقيّة** (ADR-042: لا مزوّدَ يشتقّ من مزوّد).
///
/// 🔐 **السوبر أدمن لا يُحجب أثناء الإيقاف** — هو مَن يفحص التحديث (قرار المالك). لكنه
/// يُحجب أثناء الاستعادة وعند انقطاع الخادم لأن النظام معطّلٌ فعلاً.
///
/// ⚠️ **ومَن لم يدخل بعد لا يُحجب بالإيقاف** — شاشة الدخول نفسها تعرض رسالة الإيقاف مع رابط
/// «دخول المسؤول»؛ ولو غطّتها الطبقة لما دخل السوبر أدمن أصلاً.
bool blocksUser(SystemView v, {required bool loggedIn, required bool isSuperAdmin}) => switch (v.phase) {
      SystemPhase.ok => false,
      SystemPhase.lockdown => loggedIn && !isSuperAdmin,
      SystemPhase.restoring || SystemPhase.unreachable => true,
    };

/// مفتاح الملّاح الجذريّ — لحوارات تُفتح من فوق الملّاح (الشريط في `MaterialApp.builder`
/// لا يملك ملّاحاً فوقه).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// يستطلع حالة النظام — **كل 30 ثانية** وهو سليم (قرار المالك)، و**كل 5 ثوانٍ** وهو متوقّف
/// لتختفي الطبقة سريعاً عند عودته، **وفوراً** حين يعود طلبٌ بصيانة أو انقطاع (`ping`).
class SystemStatusNotifier extends Notifier<SystemView> {
  static const healthyInterval = Duration(seconds: 30);
  static const troubledInterval = Duration(seconds: 5);

  /// فشلان متتاليان قبل إعلان «لا يجيب» — فانقطاعٌ لحظيّ لا يُغطّي الشاشة.
  static const failuresBeforeUnreachable = 2;

  Timer? _timer;
  bool _checking = false;
  int _failures = 0;

  @override
  SystemView build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(check);
    return const SystemView();
  }

  /// سؤالٌ فوريّ — يُنادى من عميل الـAPI عند 503 أو انقطاع.
  void ping() {
    if (!_checking) unawaited(check());
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    final before = state.phase;
    try {
      final s = await ref.read(apiClientProvider).systemStatus();
      _failures = 0;
      state = SystemView(
        phase: phaseOf(s),
        lockdown: s.lockdown,
        announcement: s.announcement,
        restoreReason: s.reason,
      );
    } catch (_) {
      if (++_failures >= failuresBeforeUnreachable) {
        state = state.copyWith(phase: SystemPhase.unreachable);
      } else {
        // فشلٌ أوّل — أعِد السؤال بعد قليل بدل انتظار الدورة كاملة.
        _schedule(troubledInterval);
        return;
      }
    } finally {
      _checking = false;
    }

    // عاد النظام بعد توقّف ⇒ لعلّ الواجهة نفسها تحدّثت أثناءه.
    if (before != SystemPhase.ok && state.phase == SystemPhase.ok) {
      unawaited(reloadIfNewBuild());
    }
    _schedule(state.phase == SystemPhase.ok ? healthyInterval : troubledInterval);
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, check);
  }
}

final systemStatusProvider =
    NotifierProvider<SystemStatusNotifier, SystemView>(SystemStatusNotifier.new);

/// يُعيد تحميل الصفحة **مرّةً واحدة** إن نُشر إصدارٌ أحدث من الذي يعمل (ADR-050).
///
/// 🔴 **لماذا؟** مَن ترك الصفحة مفتوحةً أثناء التحديث يبقى على الإصدار القديم يكلّم خادماً
/// جديداً — وتلك وصفةُ أعطالٍ غريبة لا تتكرّر عند أحدٍ غيره.
/// ⚠️ **ولا يحدث شيء بلا `APP_BUILD`** (التطوير) أو إن تعذّرت قراءة `version.json`.
Future<void> reloadIfNewBuild({
  String current = kAppBuild,
  Future<String?> Function() fetch = fetchDeployedBuild,
  void Function() reload = reloadPage,
}) async {
  if (!shouldReload(current, await fetch())) return;
  // 🔴 **يُفرَغ كلُّ نموذجٍ مفتوح قبل إعادة التحميل** (ADR-051) — وإلا ضاع ما كُتب منذ آخر
  //    حفظٍ تلقائيّ (حتى 3 ثوانٍ). وبعد التحميل يُنبَّه صاحبه إلى مسوّدته.
  await DraftAutosaver.flushAll();
  reload();
}

/// القرار وحده — **دالّةٌ نقيّة** تُختبر.
bool shouldReload(String current, String? deployed) =>
    current.isNotEmpty && deployed != null && deployed.isNotEmpty && deployed != current;
