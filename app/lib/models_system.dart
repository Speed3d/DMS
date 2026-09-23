// نماذج إيقاف النظام وشريط الإعلان (ADR-050).
// يُعاد تصديرها من `models.dart` فيصل إليها كل من يستورده كالمعتاد.

// استيرادٌ عكسيّ مقصود (سابقة `models_tasks.dart`): `parseInstant` من مصدرها الواحد.
import 'models.dart' show parseInstant;

/// نوع الشريط — يحدّد لونه فقط.
enum AnnouncementKind { info, warning }

AnnouncementKind _kindFrom(Object? raw) =>
    raw?.toString() == 'Warning' ? AnnouncementKind.warning : AnnouncementKind.info;

String announcementKindWire(AnnouncementKind k) => k == AnnouncementKind.warning ? 'Warning' : 'Info';

/// حالة الإيقاف. [byName] يصل للسوبر أدمن وحده.
class LockdownInfo {
  final bool active;
  final String? message;
  final DateTime? since;
  final String? byName;

  const LockdownInfo({required this.active, this.message, this.since, this.byName});

  static const off = LockdownInfo(active: false);

  factory LockdownInfo.fromJson(Map<String, dynamic>? j) => j == null
      ? off
      : LockdownInfo(
          active: j['active'] == true,
          message: j['message']?.toString(),
          since: j['since'] == null ? null : parseInstant(j['since'].toString()),
          byName: j['byName']?.toString(),
        );
}

/// شريط الإعلان.
class AnnouncementInfo {
  final bool visible;
  final String? text;
  final AnnouncementKind kind;
  final DateTime? updatedAt;

  const AnnouncementInfo({required this.visible, this.text, this.kind = AnnouncementKind.info, this.updatedAt});

  static const hidden = AnnouncementInfo(visible: false);

  factory AnnouncementInfo.fromJson(Map<String, dynamic>? j) => j == null
      ? hidden
      : AnnouncementInfo(
          visible: j['visible'] == true,
          text: j['text']?.toString(),
          kind: _kindFrom(j['kind']),
          updatedAt: j['updatedAt'] == null ? null : parseInstant(j['updatedAt'].toString()),
        );

  /// يظهر فعلاً؟ — مرئيٌّ **وله نصّ**.
  bool get shows => visible && (text?.trim().isNotEmpty ?? false);
}

/// ردّ `GET /system/status` — عامٌّ بلا رمز.
class SystemStatusInfo {
  /// صيانة الاستعادة — تحجب الجميع.
  final bool maintenance;
  final String? reason;
  final LockdownInfo lockdown;

  /// `null` لغير المصادَق.
  final AnnouncementInfo announcement;

  const SystemStatusInfo({
    required this.maintenance,
    this.reason,
    this.lockdown = LockdownInfo.off,
    this.announcement = AnnouncementInfo.hidden,
  });

  factory SystemStatusInfo.fromJson(Map<String, dynamic> j) => SystemStatusInfo(
        maintenance: j['maintenance'] == true,
        reason: j['reason']?.toString(),
        lockdown: LockdownInfo.fromJson(j['lockdown'] as Map<String, dynamic>?),
        announcement: AnnouncementInfo.fromJson(j['announcement'] as Map<String, dynamic>?),
      );
}

/// لوحة التحكّم للسوبر أدمن (`GET /system/control`).
class SystemControlInfo {
  final LockdownInfo lockdown;
  final AnnouncementInfo announcement;
  final List<String> savedLockdownTexts;
  final List<String> savedAnnouncementTexts;

  const SystemControlInfo({
    required this.lockdown,
    required this.announcement,
    this.savedLockdownTexts = const [],
    this.savedAnnouncementTexts = const [],
  });

  factory SystemControlInfo.fromJson(Map<String, dynamic> j) => SystemControlInfo(
        lockdown: LockdownInfo.fromJson(j['lockdown'] as Map<String, dynamic>?),
        announcement: AnnouncementInfo.fromJson(j['announcement'] as Map<String, dynamic>?),
        savedLockdownTexts: [for (final t in (j['savedLockdownTexts'] as List? ?? const [])) t.toString()],
        savedAnnouncementTexts: [for (final t in (j['savedAnnouncementTexts'] as List? ?? const [])) t.toString()],
      );
}
