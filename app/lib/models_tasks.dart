// نماذج وحدة المهام (ADR-037).
// يُعاد تصديرها من `models.dart` فيصل إليها كل من يستورده كالمعتاد.

// 🔴 **استيرادٌ عكسيّ مقصود** (سابقة `models_hr.dart`): `models.dart` يُعيد تصدير هذا الملف،
//    وهذا يستورد منه `parseInstant` وحدها. ودورةُ المكتبات مشروعةٌ في Dart، والبديل — نسخُ
//    الدالّة — هو بالضبط ما جعل `models_hr.dart` يفوت إصلاحَ ADR-032 كلَّه فبقيت ستّة حقول
//    متأخّرة ثلاث ساعات حتى G18.
import 'models.dart' show parseInstant;

/// يقرأ **تاريخاً تقويمياً** (يوماً) لا لحظة.
///
/// 🔴 **ولا يُستعمل [parseInstant] هنا إطلاقاً**: `dueDate` و`startDate` و`completedDate`
/// **أيامٌ لا لحظات**، وتحويلُها بالمنطقة الزمنية **يُنقص يوماً** عند إزاحةٍ سالبة — وهو
/// العطل المعكوس المسجَّل في ADR-032 وG18.
///
/// ⚠️ والخادم صار يرسلها **بلا `Z`** بعد إصلاح `LocalClock` (الدفعة ٣)، لكن الحارس هنا
/// يبقى: `DateTime.parse` على نصٍّ بلا منطقة يقرؤه محلياً، ونحن **نريد اليوم كما هو**.
DateTime parseCalendarDate(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now();
  final parsed = DateTime.tryParse(raw) ?? DateTime.now();
  // نأخذ مركّبات اليوم كما وردت — بلا `toLocal()` ولا `toUtc()`.
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? parseCalendarDateOrNull(String? raw) =>
    (raw == null || raw.isEmpty) ? null : parseCalendarDate(raw);

/// صفٌّ في قائمة المهام.
class TaskListItem {
  final int taskId;
  final String? taskNumber;
  final String title;
  final String taskType;
  final String priority;
  final String priorityLabel;
  final String status;
  final String statusLabel;
  final int progressPercent;
  final DateTime dueDate;
  final bool isOverdue;
  final int daysOverdue;
  final int daysRemaining;
  final int? departmentId;
  final String? departmentName;
  final int? assignedToUserId;
  final String? assignedToUserName;
  final int attachmentCount;

  TaskListItem({
    required this.taskId, this.taskNumber, required this.title,
    required this.taskType, required this.priority, required this.priorityLabel,
    required this.status, required this.statusLabel,
    required this.progressPercent, required this.dueDate,
    required this.isOverdue, required this.daysOverdue, required this.daysRemaining,
    this.departmentId, this.departmentName,
    this.assignedToUserId, this.assignedToUserName,
    required this.attachmentCount,
  });

  bool get isDepartmentTask => taskType == 'Department';

  factory TaskListItem.fromJson(Map<String, dynamic> j) => TaskListItem(
        taskId: j['taskId'],
        taskNumber: j['taskNumber'],
        title: j['title'] ?? '',
        taskType: j['taskType'] ?? 'Individual',
        priority: j['priority'] ?? 'Normal',
        priorityLabel: j['priorityLabel'] ?? '',
        status: j['status'] ?? 'New',
        statusLabel: j['statusLabel'] ?? '',
        progressPercent: j['progressPercent'] ?? 0,
        dueDate: parseCalendarDate(j['dueDate']),
        isOverdue: j['isOverdue'] ?? false,
        daysOverdue: j['daysOverdue'] ?? 0,
        daysRemaining: j['daysRemaining'] ?? 0,
        departmentId: j['departmentId'],
        departmentName: j['departmentName'],
        assignedToUserId: j['assignedToUserId'],
        assignedToUserName: j['assignedToUserName'],
        attachmentCount: j['attachmentCount'] ?? 0,
      );
}

/// صفحةٌ من قائمة المهام.
class TaskPage {
  final List<TaskListItem> items;
  final int total;
  final int page;
  final int pageSize;

  TaskPage({required this.items, required this.total, required this.page, required this.pageSize});

  factory TaskPage.fromJson(Map<String, dynamic> j) => TaskPage(
        items: ((j['items'] ?? []) as List).map((e) => TaskListItem.fromJson(e)).toList(),
        total: j['total'] ?? 0,
        page: j['page'] ?? 1,
        pageSize: j['pageSize'] ?? 25,
      );

  static TaskPage get empty => TaskPage(items: const [], total: 0, page: 1, pageSize: 25);
}

/// مهمة كاملة.
class TaskModel {
  final int taskId;
  final String? taskNumber;
  final String title;
  final String? description;
  final String taskType;
  final String taskTypeLabel;
  final String priority;
  final String priorityLabel;
  final String status;
  final String statusLabel;
  final int progressPercent;
  final DateTime dueDate;
  final DateTime? startDate;
  final DateTime? completedDate;
  final bool isOverdue;
  final int daysOverdue;
  final int daysRemaining;
  final int? departmentId;
  final String? departmentName;
  final int? assignedToUserId;
  final String? assignedToUserName;
  final int createdByUserId;
  final String createdByUserName;
  final int? relatedIncomingId;
  final String? relatedIncomingNumber;
  final int? relatedOutgoingId;
  final String? relatedOutgoingNumber;
  final bool isRecurring;
  final String? recurrencePattern;
  final int? recurrenceInterval;
  final DateTime? recurrenceEndDate;
  final int? parentRecurringTaskId;
  final String? notes;

  /// لحظاتٌ حقيقية — تُقرأ بـ[parseInstant] وتُعرض بـ`toLocal()`.
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// ⚠️ **نصٌّ مبهم يُقرأ ويُعاد كما هو** — `byte[]` يصل base64 لا مصفوفةَ أرقام.
  final String rowVersion;

  /// الحالات المسموح الانتقال إليها — **من مصفوفة المجال** لا من تخمين الواجهة.
  final List<String> nextStatuses;

  /// هل يملك الطالبُ تعديلَ هذه المهمة؟ — فلا تُعرض أزرارٌ تردّ 403.
  final bool canEdit;

  TaskModel({
    required this.taskId, this.taskNumber, required this.title, this.description,
    required this.taskType, required this.taskTypeLabel,
    required this.priority, required this.priorityLabel,
    required this.status, required this.statusLabel,
    required this.progressPercent, required this.dueDate, this.startDate, this.completedDate,
    required this.isOverdue, required this.daysOverdue, required this.daysRemaining,
    this.departmentId, this.departmentName,
    this.assignedToUserId, this.assignedToUserName,
    required this.createdByUserId, required this.createdByUserName,
    this.relatedIncomingId, this.relatedIncomingNumber,
    this.relatedOutgoingId, this.relatedOutgoingNumber,
    required this.isRecurring, this.recurrencePattern, this.recurrenceInterval,
    this.recurrenceEndDate, this.parentRecurringTaskId, this.notes,
    required this.createdAt, this.updatedAt,
    required this.rowVersion, required this.nextStatuses, required this.canEdit,
  });

  bool get isDepartmentTask => taskType == 'Department';
  bool get isActive => const ['New', 'InProgress', 'OnHold', 'Reopened'].contains(status);
  bool get isCompleted => status == 'Completed';

  factory TaskModel.fromJson(Map<String, dynamic> j) => TaskModel(
        taskId: j['taskId'],
        taskNumber: j['taskNumber'],
        title: j['title'] ?? '',
        description: j['description'],
        taskType: j['taskType'] ?? 'Individual',
        taskTypeLabel: j['taskTypeLabel'] ?? '',
        priority: j['priority'] ?? 'Normal',
        priorityLabel: j['priorityLabel'] ?? '',
        status: j['status'] ?? 'New',
        statusLabel: j['statusLabel'] ?? '',
        progressPercent: j['progressPercent'] ?? 0,
        dueDate: parseCalendarDate(j['dueDate']),
        startDate: parseCalendarDateOrNull(j['startDate']),
        completedDate: parseCalendarDateOrNull(j['completedDate']),
        isOverdue: j['isOverdue'] ?? false,
        daysOverdue: j['daysOverdue'] ?? 0,
        daysRemaining: j['daysRemaining'] ?? 0,
        departmentId: j['departmentId'],
        departmentName: j['departmentName'],
        assignedToUserId: j['assignedToUserId'],
        assignedToUserName: j['assignedToUserName'],
        createdByUserId: j['createdByUserId'] ?? 0,
        createdByUserName: j['createdByUserName'] ?? '—',
        relatedIncomingId: j['relatedIncomingId'],
        relatedIncomingNumber: j['relatedIncomingNumber'],
        relatedOutgoingId: j['relatedOutgoingId'],
        relatedOutgoingNumber: j['relatedOutgoingNumber'],
        isRecurring: j['isRecurring'] ?? false,
        recurrencePattern: j['recurrencePattern'],
        recurrenceInterval: j['recurrenceInterval'],
        recurrenceEndDate: parseCalendarDateOrNull(j['recurrenceEndDate']),
        parentRecurringTaskId: j['parentRecurringTaskId'],
        notes: j['notes'],
        // ⚠️ **لحظات** لا تواريخ تقويمية — `parseInstant` هنا صحيحةٌ وواجبة.
        createdAt: parseInstant(j['createdAt']),
        updatedAt: j['updatedAt'] == null ? null : parseInstant(j['updatedAt']),
        rowVersion: j['rowVersion'] ?? '',
        nextStatuses: ((j['nextStatuses'] ?? []) as List).map((e) => e.toString()).toList(),
        canEdit: j['canEdit'] ?? false,
      );
}

/// قيدٌ في سجلّ المهمة الشاهد.
class TaskUpdateModel {
  final int updateId;
  final String updateType;
  final String description;
  final String? oldValue;
  final String? newValue;
  final String? comment;
  final int updatedByUserId;
  final String updatedByUserName;

  /// **لحظة** — تُقرأ بـ[parseInstant].
  final DateTime updatedAt;

  TaskUpdateModel({
    required this.updateId, required this.updateType, required this.description,
    this.oldValue, this.newValue, this.comment,
    required this.updatedByUserId, required this.updatedByUserName, required this.updatedAt,
  });

  factory TaskUpdateModel.fromJson(Map<String, dynamic> j) => TaskUpdateModel(
        updateId: j['updateId'],
        updateType: j['updateType'] ?? '',
        description: j['description'] ?? '',
        oldValue: j['oldValue'],
        newValue: j['newValue'],
        comment: j['comment'],
        updatedByUserId: j['updatedByUserId'] ?? 0,
        updatedByUserName: j['updatedByUserName'] ?? '—',
        updatedAt: parseInstant(j['updatedAt']),
      );
}

/// مشاركٌ في مهمة — **شخصٌ أو قسم** يرى المهمة ويعمل عليها بلا أن يكون مسؤولها (ADR-037).
class TaskParticipant {
  final int participantId;
  final int? userId;
  final String? userName;
  final int? departmentId;
  final String? departmentName;

  /// اسمٌ واحدٌ **جاهزٌ من الخادم** — فلا يركّبه كلُّ عميلٍ بطريقته.
  final String displayName;

  final String? note;
  final int addedByUserId;
  final String addedByUserName;
  final DateTime addedAt;

  /// أُزيل — **فلا يرى المهمة بعدها**، ويبقى سطرُه شاهداً على مشاركةٍ وقعت.
  final bool isRemoved;
  final DateTime? removedAt;

  TaskParticipant({
    required this.participantId, this.userId, this.userName,
    this.departmentId, this.departmentName, required this.displayName,
    this.note, required this.addedByUserId, required this.addedByUserName,
    required this.addedAt, required this.isRemoved, this.removedAt,
  });

  bool get isDepartment => departmentId != null;

  factory TaskParticipant.fromJson(Map<String, dynamic> j) => TaskParticipant(
        participantId: j['participantId'],
        userId: j['userId'],
        userName: j['userName'],
        departmentId: j['departmentId'],
        departmentName: j['departmentName'],
        displayName: j['displayName'] ?? '—',
        note: j['note'],
        addedByUserId: j['addedByUserId'] ?? 0,
        addedByUserName: j['addedByUserName'] ?? '—',
        // **لحظة** لا تاريخٌ تقويميّ.
        addedAt: parseInstant(j['addedAt']),
        isRemoved: j['isRemoved'] ?? false,
        removedAt: j['removedAt'] == null ? null : parseInstant(j['removedAt']),
      );
}

/// ملخّص المهام للوحة التحكم.
class TaskSummaryModel {
  final int total;
  final int active;
  final int overdue;
  final int dueToday;
  final int completedThisMonth;
  final int mineActive;

  TaskSummaryModel({
    required this.total, required this.active, required this.overdue,
    required this.dueToday, required this.completedThisMonth, required this.mineActive,
  });

  factory TaskSummaryModel.fromJson(Map<String, dynamic> j) => TaskSummaryModel(
        total: j['total'] ?? 0,
        active: j['active'] ?? 0,
        overdue: j['overdue'] ?? 0,
        dueToday: j['dueToday'] ?? 0,
        completedThisMonth: j['completedThisMonth'] ?? 0,
        mineActive: j['mineActive'] ?? 0,
      );

  static TaskSummaryModel get zero =>
      TaskSummaryModel(total: 0, active: 0, overdue: 0, dueToday: 0, completedThisMonth: 0, mineActive: 0);
}

/// مستخدمٌ يصلح مسؤولاً عن مهمة.
class AssignableUser {
  final int userId;
  final String fullName;
  final String username;
  final String role;

  AssignableUser({
    required this.userId, required this.fullName,
    required this.username, required this.role,
  });

  factory AssignableUser.fromJson(Map<String, dynamic> j) => AssignableUser(
        userId: j['userId'],
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? '',
      );
}

/// تسميات عربية — **مرآةٌ لـ`TaskWorkflow.ArabicName`**، وتُستعمل حيث لا يرسل الخادم التسمية.
///
/// ⚠️ الخادم يرسل `statusLabel` و`priorityLabel` جاهزَين، وهذه للحالات التي نبنيها محلياً
/// (أزرار الانتقال من `nextStatuses` مثلاً). **ولو تعارضا فالخادم هو المرجع.**
const Map<String, String> kTaskStatusLabels = {
  'New': 'جديدة',
  'InProgress': 'قيد التنفيذ',
  'OnHold': 'معلّقة',
  'Completed': 'مكتملة',
  'Cancelled': 'ملغاة',
  'Reopened': 'أُعيد فتحها',
};

const Map<String, String> kTaskPriorityLabels = {
  'Low': 'منخفضة',
  'Normal': 'عادية',
  'High': 'عالية',
  'Urgent': 'عاجلة',
};

const Map<String, String> kTaskTypeLabels = {
  'Individual': 'فردية',
  'Department': 'قسم',
};

const Map<String, String> kRecurrenceLabels = {
  'Daily': 'يومي',
  'Weekly': 'أسبوعي',
  'Monthly': 'شهري',
};


// ═══════════════════════ الإشعارات (ADR-038) ═══════════════════════

/// إشعارٌ واحد — **بلا مستلِم**: كلُّ ما يصل العميلَ هو إشعاراتُه هو.
class NotificationModel {
  final int notificationId;
  final String title;
  final String body;
  final String category;
  final String? entityType;
  final int? entityId;
  final String priority;
  final bool isRead;
  final DateTime? readAt;

  /// **لحظة** — تُقرأ بـ`parseInstant` وتُعرض بـ`toLocal()`.
  final DateTime createdAt;

  NotificationModel({
    required this.notificationId, required this.title, required this.body,
    required this.category, this.entityType, this.entityId,
    required this.priority, required this.isRead, this.readAt,
    required this.createdAt,
  });

  bool get isHigh => priority == 'High';
  bool get isTask => category == 'Task';

  factory NotificationModel.fromJson(Map<String, dynamic> j) => NotificationModel(
        notificationId: j['notificationId'],
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        category: j['category'] ?? '',
        entityType: j['entityType'],
        entityId: j['entityId'],
        priority: j['priority'] ?? 'Normal',
        isRead: j['isRead'] ?? false,
        readAt: j['readAt'] == null ? null : parseInstant(j['readAt']),
        createdAt: parseInstant(j['createdAt']),
      );
}

class NotificationPage {
  final List<NotificationModel> items;
  final int total;
  final int page;
  final int pageSize;

  NotificationPage({
    required this.items, required this.total,
    required this.page, required this.pageSize,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        items: ((j['items'] ?? []) as List)
            .map((e) => NotificationModel.fromJson(e)).toList(),
        total: j['total'] ?? 0,
        page: j['page'] ?? 1,
        pageSize: j['pageSize'] ?? 25,
      );

  static NotificationPage get empty =>
      NotificationPage(items: const [], total: 0, page: 1, pageSize: 25);
}
