import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'session.dart';

/// مزوّدات وحدة المهام (ADR-037) — في ملف محايد لتفادي دورات الاستيراد،
/// على نمط `hr_providers.dart` و`outgoing_providers.dart`.

/// فلاتر قائمة المهام — حالةٌ واحدة تقرؤها القائمة ويكتبها شريط الفلترة.
class TaskFilterState {
  final String? status;
  final String? priority;
  final int? departmentId;
  final bool mineOnly;
  final bool? isOverdue;
  final String search;
  final int page;

  const TaskFilterState({
    this.status,
    this.priority,
    this.departmentId,
    this.mineOnly = false,
    this.isOverdue,
    this.search = '',
    this.page = 1,
  });

  /// ⚠️ **`clearX` صريحة لكل حقلٍ اختياري**: `copyWith(status: null)` لا يفرّق بين «لا
  /// تغيير» و«امسح» — وهو ما يجعل زرّ «كل الحالات» لا يعمل أبداً.
  TaskFilterState copyWith({
    String? status,
    bool clearStatus = false,
    String? priority,
    bool clearPriority = false,
    int? departmentId,
    bool clearDepartment = false,
    bool? mineOnly,
    bool? isOverdue,
    bool clearOverdue = false,
    String? search,
    int? page,
  }) =>
      TaskFilterState(
        status: clearStatus ? null : (status ?? this.status),
        priority: clearPriority ? null : (priority ?? this.priority),
        departmentId: clearDepartment ? null : (departmentId ?? this.departmentId),
        mineOnly: mineOnly ?? this.mineOnly,
        isOverdue: clearOverdue ? null : (isOverdue ?? this.isOverdue),
        search: search ?? this.search,
        // 🔴 **أي تغييرٍ في الفلتر يعيد الصفحة إلى ١**: البقاء على الصفحة الثالثة بعد تضييق
        //    الفلتر يُظهر قائمةً فارغة، فيبدو الفلتر معطوباً وهو سليم.
        page: page ?? ((status != null || clearStatus ||
                        priority != null || clearPriority ||
                        departmentId != null || clearDepartment ||
                        mineOnly != null || isOverdue != null || clearOverdue ||
                        search != null)
            ? 1
            : this.page),
      );

  bool get hasAnyFilter =>
      status != null || priority != null || departmentId != null ||
      mineOnly || isOverdue != null || search.isNotEmpty;
}

class TaskFilterNotifier extends Notifier<TaskFilterState> {
  @override
  TaskFilterState build() => const TaskFilterState();

  void update(TaskFilterState next) => state = next;
  void reset() => state = const TaskFilterState();
}

/// ⚠️ `Notifier` لا `StateProvider` — الأخيرة أُزيلت في Riverpod 3 (سابقة `session.dart`).
final taskFilterProvider =
    NotifierProvider<TaskFilterNotifier, TaskFilterState>(TaskFilterNotifier.new);

/// صفحةُ المهام بحسب الفلاتر الحالية.
final tasksPageProvider = FutureProvider.autoDispose<TaskPage>((ref) async {
  final session = ref.watch(sessionProvider);

  // ⚠️ **الحدّان معاً** (القسم **والدور**) — مرآةٌ لـ`[RequireGrantedModule]`؛ الطلب بلا
  //    أحدهما يردّ 403، وإظهارُ خطأٍ لمن لا يملك الوحدة أسوأ من قائمةٍ فارغة.
  if (!session.canSeeTasks) return TaskPage.empty;

  final f = ref.watch(taskFilterProvider);
  return ref.read(apiClientProvider).tasks(
        status: f.status,
        priority: f.priority,
        departmentId: f.departmentId,
        mineOnly: f.mineOnly,
        isOverdue: f.isOverdue,
        search: f.search,
        page: f.page,
      );
});

/// مهمةٌ بعينها.
final taskDetailProvider =
    FutureProvider.autoDispose.family<TaskModel, int>((ref, id) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks) throw StateError('لا تملك صلاحية الوصول لقسم المهام.');
  return ref.read(apiClientProvider).task(id);
});

/// سجلّ مهمةٍ بعينها.
final taskUpdatesProvider =
    FutureProvider.autoDispose.family<List<TaskUpdateModel>, int>((ref, id) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks) return const <TaskUpdateModel>[];
  return ref.read(apiClientProvider).taskUpdates(id);
});

/// مشاركو مهمةٍ بعينها — **مَن يراها غير مسؤولها**.
final taskParticipantsProvider =
    FutureProvider.autoDispose.family<List<TaskParticipant>, int>((ref, id) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks) return const <TaskParticipant>[];
  return ref.read(apiClientProvider).taskParticipants(id);
});

/// مرفقات مهمةٍ بعينها.
final taskAttachmentsProvider =
    FutureProvider.autoDispose.family<List<AttachmentModel>, int>((ref, id) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks) return const <AttachmentModel>[];
  return ref.read(apiClientProvider).taskAttachments(id);
});

/// ملخّص المهام (لوحة التحكم والشارة).
final taskSummaryProvider = FutureProvider.autoDispose<TaskSummaryModel>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks) return TaskSummaryModel.zero;
  return ref.read(apiClientProvider).taskSummary();
});

/// عدد المهام المتأخّرة — شارة الشريط الجانبي.
///
/// ⚠️ **مشتقٌّ من `AsyncValue` مباشرةً لا بـ`await ref.watch(x.future)`** — انتظارُ
/// `.future` يُنشئ `ProxyProviderListenable` يُبطل نفسه أثناء طور البناء فيرمي
/// «setState() called during build». (الدرس نفسه في `hr_providers.dart` و`outgoing_providers.dart`.)
final overdueTasksCountProvider = Provider.autoDispose<AsyncValue<int>>(
    (ref) => ref.watch(taskSummaryProvider).whenData((s) => s.overdue));

/// مَن يصلح مسؤولاً — للنموذج، ومقصورٌ على صاحب `CanManageTasks`.
///
/// ⚠️ **يُفحص العلَم قبل الطلب**: النقطة تردّ 403 لغيره، وطلبٌ نعلم أنه سيُرفض ضجيجٌ في
/// السجلّ وخطأٌ يراه المستخدم بلا سبب.
final assignableUsersProvider = FutureProvider.autoDispose<List<AssignableUser>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.canSeeTasks || !session.canManageTasks) return const <AssignableUser>[];
  return ref.read(apiClientProvider).assignableUsers();
});

/// يُبطل مزوّدات المهام كلها بعد أي عملية كتابة أو تبديل شركة.
///
/// ⚠️ **مركزيّ عمداً**: نسيانُ إبطال أحدها يُبقي القائمة تعرض حالةً قديمة بعد تغييرها،
/// فيبدو الزرّ بلا أثر ويُعاد الضغط.
void invalidateTasks(WidgetRef ref) {
  ref.invalidate(tasksPageProvider);
  ref.invalidate(taskSummaryProvider);
  ref.invalidate(taskDetailProvider);
  ref.invalidate(taskUpdatesProvider);
  ref.invalidate(taskAttachmentsProvider);
  ref.invalidate(taskParticipantsProvider);
}
