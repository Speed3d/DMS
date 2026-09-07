import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'session.dart';

/// مزوّدات الإشعارات (ADR-038).
///
/// ⚠️ **بلا حارس قسم** — الإشعارات **عابرةٌ للأقسام**: قد يصل الموظفَ إشعارٌ عن مهمة وآخرُ
/// عن كتابٍ وارد. والحارس الوحيد أن الخادم يشتقّ المستلِم من الجلسة.

/// عدد غير المقروء — **شارة الجرس**.
///
/// 🔴 **استقصاءٌ كل 60 ثانية لا SignalR** (قرار مُعلَّل): لا SignalR في المشروع، وإدخالُه
/// لأجل شارةٍ يعني **طبقةَ نقلٍ جديدة** على سيرفرٍ داخليّ يديره غيرُ مختصّ. والاستقصاء
/// **يتوقّف عند تسجيل الخروج** فلا يطرق الخادم بلا جلسة.
///
/// ⚠️ **و`ref.onDispose` يُلغي المؤقّت** — بدونه يبقى `Timer` حيّاً بعد تلاشي المزوّد
/// فيطلب إلى الأبد، وهو تسريبٌ صامت لا يظهر إلا في سجلّ الخادم.
final unreadNotificationsProvider = StreamProvider.autoDispose<int>((ref) {
  final session = ref.watch(sessionProvider);
  if (session.auth == null) return Stream.value(0);

  final api = ref.read(apiClientProvider);
  final controller = StreamController<int>();

  Future<void> tick() async {
    try {
      controller.add(await api.unreadNotificationCount());
    } catch (_) {
      // ⚠️ **يُبتلع الخطأ عمداً**: شارةٌ لا تُحدَّث أهون من رسالة خطأٍ تظهر كل دقيقة
      //    لمستخدمٍ لم يطلب شيئاً. والفشل الحقيقي يظهر عند فتح الشاشة نفسها.
    }
  }

  tick();
  final timer = Timer.periodic(const Duration(seconds: 60), (_) => tick());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

/// صفحةٌ من إشعاراتي.
final notificationsProvider =
    FutureProvider.autoDispose.family<NotificationPage, bool>((ref, unreadOnly) async {
  final session = ref.watch(sessionProvider);
  if (session.auth == null) return NotificationPage.empty;
  return ref.read(apiClientProvider).notifications(unreadOnly: unreadOnly);
});

/// يُبطل الإشعارات كلها بعد وسمٍ بالمقروء.
void invalidateNotifications(WidgetRef ref) {
  ref.invalidate(notificationsProvider);
  ref.invalidate(unreadNotificationsProvider);
}
