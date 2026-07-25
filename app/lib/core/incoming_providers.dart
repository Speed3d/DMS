import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

class StringNotifier extends Notifier<String> {
  @override String build() => '';
  @override set state(String value) => super.state = value;
}
final incomingSearchQueryProvider = NotifierProvider<StringNotifier, String>(StringNotifier.new);

class StringNullableNotifier extends Notifier<String?> {
  @override String? build() => null;
  @override set state(String? value) => super.state = value;
}
final incomingStatusFilterProvider = NotifierProvider<StringNullableNotifier, String?>(StringNullableNotifier.new);

class IntNullableNotifier extends Notifier<int?> {
  @override int? build() => null;
  @override set state(int? value) => super.state = value;
}
final incomingEntityFilterProvider = NotifierProvider<IntNullableNotifier, int?>(IntNullableNotifier.new);
final incomingDocTypeFilterProvider = NotifierProvider<IntNullableNotifier, int?>(IntNullableNotifier.new);
final incomingReceiveMethodFilterProvider = NotifierProvider<IntNullableNotifier, int?>(IntNullableNotifier.new);
final incomingDepartmentFilterProvider = NotifierProvider<IntNullableNotifier, int?>(IntNullableNotifier.new);

class DateTimeNullableNotifier extends Notifier<DateTime?> {
  @override DateTime? build() => null;
  @override set state(DateTime? value) => super.state = value;
}
final incomingDateFromFilterProvider = NotifierProvider<DateTimeNullableNotifier, DateTime?>(DateTimeNullableNotifier.new);
final incomingDateToFilterProvider = NotifierProvider<DateTimeNullableNotifier, DateTime?>(DateTimeNullableNotifier.new);

// ----------------- الأقسام (لفلاتر الوارد وإحالته) -----------------
final departmentsListProvider = FutureProvider.autoDispose<List<DepartmentModel>>((ref) async {
  final auth = ref.watch(sessionProvider).auth;
  if (auth == null) return <DepartmentModel>[];
  return ref.read(apiClientProvider).departments();
});

// ----------------- قائمة الكتب الواردة -----------------
final incomingListProvider = FutureProvider.autoDispose<List<IncomingListItem>>((ref) async {
  final auth = ref.watch(sessionProvider).auth;
  if (auth == null || !auth.hasModule('Incoming')) return <IncomingListItem>[];
  
  final api = ref.watch(apiClientProvider);
  final search = ref.watch(incomingSearchQueryProvider);
  final status = ref.watch(incomingStatusFilterProvider);
  final entityId = ref.watch(incomingEntityFilterProvider);
  final from = ref.watch(incomingDateFromFilterProvider);
  final to = ref.watch(incomingDateToFilterProvider);
  final docType = ref.watch(incomingDocTypeFilterProvider);
  final departmentId = ref.watch(incomingDepartmentFilterProvider);
  final receiveMethod = ref.watch(incomingReceiveMethodFilterProvider);

  return api.incomingList(
    search: search, status: status, entityId: entityId,
    from: from, to: to, documentTypeId: docType,
    departmentId: departmentId, receiveMethod: receiveMethod
  );
});

// ----------------- إشعارات الوارد -----------------
final pendingIncomingProvider = FutureProvider.autoDispose<List<IncomingListItem>>((ref) async {
  final auth = ref.watch(sessionProvider).auth;
  if (auth == null || !auth.hasModule('Incoming')) return <IncomingListItem>[];
  
  final items = await ref.read(apiClientProvider).incomingList();
  return items.where((e) => e.status == 'New' || e.status == 'InReview').toList();
});

final incomingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final list = await ref.watch(pendingIncomingProvider.future);
  return list.length;
});

void invalidateIncoming(WidgetRef ref) {
  ref.invalidate(incomingListProvider);
  ref.invalidate(pendingIncomingProvider);
  ref.invalidate(incomingCountProvider);
}

// ----------------- تفاصيل كتاب وارد -----------------
final incomingDetailProvider = FutureProvider.autoDispose.family<IncomingDetail, int>((ref, id) async {
  final api = ref.read(apiClientProvider);
  return await api.incomingGet(id);
});

// ----------------- المرفقات -----------------
final incomingAttachmentsProvider = FutureProvider.autoDispose.family<List<AttachmentModel>, int>((ref, id) async {
  final api = ref.read(apiClientProvider);
  return await api.incomingAttachments(id);
});

// ----------------- سجل الحركة -----------------
final incomingMovementsProvider = FutureProvider.autoDispose.family<List<MovementLogItem>, int>((ref, id) async {
  final api = ref.read(apiClientProvider);
  return await api.incomingMovements(id);
});
