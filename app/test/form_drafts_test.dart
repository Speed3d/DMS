import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/form_drafts.dart';
import 'package:dms_app/core/incoming_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/core/task_providers.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/my_drafts_screen.dart';
import 'package:dms_app/screens/task_form_screen.dart';

/// حرّاس حماية ما يُكتب (ADR-051).
///
/// 🔴 **أهمُّها العزل**: المسوّدة محفوظةٌ على الجهاز، والجهاز قد يتشاركه موظفان — فلا يرى
/// أحدٌ مسوّدة غيره ولا يرسلها باسمه، ولا تُرسَل مسوّدةُ شركةٍ إلى شركةٍ أخرى.
void main() {
  FormDraft draft({
    String? id,
    int userId = 1,
    int companyId = 10,
    DraftKind kind = DraftKind.outgoing,
    String title = 'كتاب',
    DateTime? at,
    String? error,
    Map<String, dynamic>? fields,
  }) {
    final t = at ?? DateTime(2026, 9, 24, 10);
    return FormDraft(
      id: id ?? newDraftId(),
      kind: kind,
      userId: userId,
      companyId: companyId,
      createdAt: t,
      updatedAt: t,
      title: title,
      fields: fields ?? const {},
      lastError: error,
    );
  }

  group('القواعد النقيّة', () {
    test('🔐 مسوّدات المستخدم وحده — الأحدث أوّلاً', () {
      final all = [
        draft(userId: 1, title: 'قديم', at: DateTime(2026, 9, 1)),
        draft(userId: 2, title: 'لغيري'),
        draft(userId: 1, title: 'حديث', at: DateTime(2026, 9, 20)),
      ];
      final mine = draftsOf(all, 1);
      expect(mine.map((d) => d.title), ['حديث', 'قديم']);
    });

    test('🔐 شركاتٌ أخرى بالعدد والاسم فقط — لا تُفتح هنا', () {
      final mine = [
        draft(companyId: 10),
        draft(companyId: 20),
        draft(companyId: 20),
      ];
      final s = splitByCompany(mine, 10);
      expect(s.here, hasLength(1));
      expect(s.elsewhere.keys, [20]);
      expect(s.elsewhere[20]!.count, 2);
    });

    test('بلا شركةٍ فعّالة ⇒ لا شيء «هنا»', () {
      expect(splitByCompany([draft(companyId: 10)], null).here, isEmpty);
    });

    test('الملفات تُحفظ بالترتيب حتى الحدّ — ولا قفزَ فوق ملفٍّ كبير', () {
      expect(planFileStorage([10, 10, 10], maxBytes: 25), [true, true, false]);
      // الصفحة ٢ كبيرة ⇒ لا تُحفظ ٣ الصغيرةُ بعدها (ترتيبُ الصفحات معنى).
      expect(planFileStorage([5, 30, 1], maxBytes: 25), [true, false, false]);
      expect(planFileStorage([25], maxBytes: 25), [true]);
      expect(planFileStorage(const [], maxBytes: 25), isEmpty);
    });

    test('حدُّ المسوّدة 25 ميغابايت (قرار المالك)', () {
      expect(kDraftFilesMaxBytes, 25 * 1024 * 1024);
    });

    test('🔴 معرّف المسوّدة يصلح مفتاحاً على الخادم (`[A-Za-z0-9:_-]`، ≤ 80)', () {
      final server = RegExp(r'^[A-Za-z0-9:_-]+$');
      for (var i = 0; i < 50; i++) {
        final key = draft().idempotencyKey('outgoing');
        expect(server.hasMatch(key), isTrue, reason: key);
        expect(key.length, lessThanOrEqualTo(80));
      }
      expect(newDraftId(), isNot(newDraftId()));
    });

    test('المفتاح ثابتٌ للمسوّدة ويختلف بين خطواتها', () {
      final d = draft(id: 'abc');
      expect(d.idempotencyKey('entity'), 'abc:entity');
      expect(d.idempotencyKey('entity'), d.idempotencyKey('entity'));
      expect(d.idempotencyKey('entity'), isNot(d.idempotencyKey('outgoing')));
    });

    test('نصّ التنبيه بصيغة العدد العربية', () {
      expect(draftsNoticeText(1), contains('مسوّدةٌ لم تُرسَل'));
      expect(draftsNoticeText(2), contains('مسوّدتان'));
      expect(draftsNoticeText(5), contains('5 مسوّدات'));
      expect(draftsNoticeText(12), contains('12 مسوّدة'));
    });

    test('JSON ذهاباً وإياباً بلا فقد', () {
      final d = draft(error: 'تعذّر الوصول إلى الخادم', fields: {'subject': 'س', 'body': [{'insert': 'نص\n'}]})
          .copyWith(files: const [DraftFileMeta('a.pdf', 10, true), DraftFileMeta('b.pdf', 99, false)],
              createdEntityId: 7, createdRecordId: 9);
      final back = FormDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(back.missingFiles.map((f) => f.name), ['b.pdf']);
      expect(back.failed, isTrue);
    });
  });

  // ─────────────────────────── المخزن الحقيقيّ (Hive) ───────────────────────────
  group('المخزن والحفظ التلقائيّ', () {
    late Directory dir;
    final store = FormDraftStore();

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('dms_drafts_test');
      Hive.init(dir.path);
      await FormDraftStore.open();
    });
    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    setUp(() async {
      for (final d in store.all()) {
        await store.delete(d.id);
      }
    });

    test('يُحفظ ويُقرأ ويُحذف — والملفات تُحذف معه', () async {
      final files = [
        DraftFileData('1.pdf', Uint8List.fromList([1, 2, 3])),
        DraftFileData('2.jpg', Uint8List.fromList([4, 5])),
      ];
      final saved = await store.put(draft(id: 'x'), files: files);
      expect(saved.files.every((f) => f.stored), isTrue);
      expect(store.get('x')!.files.map((f) => f.name), ['1.pdf', '2.jpg']);
      final back = await store.loadFiles(store.get('x')!);
      expect(back.map((f) => f.bytes.toList()), [
        [1, 2, 3],
        [4, 5]
      ]);

      await store.delete('x');
      expect(store.get('x'), isNull);
      expect(Hive.lazyBox<Uint8List>(FormDraftStore.filesBox).keys, isEmpty);
    });

    test('🔴 الصندوق القديم بلا صاحب يُمحى عند الفتح', () async {
      expect(await Hive.boxExists(FormDraftStore.legacyBox), isFalse);
    });

    DraftAutosaver saver(DraftSnapshot? Function() capture, {String? id}) => DraftAutosaver(
          store: store,
          kind: DraftKind.outgoing,
          userId: 1,
          companyId: 10,
          capture: capture,
          id: id,
        );

    test('يُحفظ ما تغيّر — ولا يُحفظ نموذجٌ فارغ', () async {
      DraftSnapshot? snap;
      final s = saver(() => snap);
      expect(await s.flush(), isNull);
      expect(store.all(), isEmpty, reason: 'النموذج الفارغ لا يصنع «مسوّدة»');

      snap = const DraftSnapshot(title: 'أ', fields: {'subject': 'أ'});
      final first = await s.flush();
      expect(first!.title, 'أ');
      final again = await s.flush();
      expect(again!.updatedAt, first.updatedAt, reason: 'لم يتغيّر شيء ⇒ لا كتابة');

      snap = const DraftSnapshot(title: 'ب', fields: {'subject': 'ب'});
      expect((await s.flush())!.title, 'ب');
      s.dispose();
    });

    test('إفراغ النموذج يحذف مسوّدته — إلا إن أُنشئ منها شيءٌ على الخادم', () async {
      DraftSnapshot? snap = const DraftSnapshot(title: 'أ', fields: {'a': 1});
      final s = saver(() => snap);
      await s.flush();
      snap = null;
      await s.flush();
      expect(store.all(), isEmpty);

      snap = const DraftSnapshot(title: 'ب', fields: {'a': 2});
      await s.recordProgress(recordId: 55);
      snap = null;
      await s.flush();
      expect(store.get(s.id)!.createdRecordId, 55, reason: 'وارِدٌ سُجّل وبقيت مرفقاته — لا يُمحى');
      s.dispose();
    });

    test('الفشل يُحفظ بسببه، والتقدّم يبقى بعد تعديلٍ لاحق', () async {
      final s = saver(() => const DraftSnapshot(title: 'أ', fields: {'a': 1}));
      await s.recordProgress(entityId: 7);
      await s.markFailed('تعذّر الوصول إلى الخادم');
      final d = store.get(s.id)!;
      expect(d.lastError, 'تعذّر الوصول إلى الخادم');
      expect(d.createdEntityId, 7);
      await s.flush(force: true);
      expect(store.get(s.id)!.createdEntityId, 7, reason: 'الحفظ التلقائيّ لا يمحو ما أُنشئ');
      s.dispose();
    });

    test('flushAll يُفرغ كلَّ نموذجٍ مفتوح (قبل تحديث الصفحة)', () async {
      final a = saver(() => const DraftSnapshot(title: 'أ', fields: {'a': 1}))..start();
      final b = saver(() => const DraftSnapshot(title: 'ب', fields: {'b': 1}))..start();
      await DraftAutosaver.flushAll();
      expect(store.all().map((d) => d.title).toSet(), {'أ', 'ب'});
      a.dispose();
      b.dispose();
    });

    test('ملفاتٌ فوق الحدّ تُحفظ أسماؤها وحدها', () async {
      // ⚠️ الحدّ الحقيقيّ 25 ميغابايت — ملفٌّ 26 يكفي لإثبات السلوك بلا خطّةٍ مصطنعة.
      final big = Uint8List(26 * 1024 * 1024);
      final saved = await store.put(draft(id: 'big'),
          files: [DraftFileData('small.pdf', Uint8List(10)), DraftFileData('huge.pdf', big)]);
      expect(saved.files.map((f) => f.stored), [true, false]);
      expect(saved.missingFiles.single.name, 'huge.pdf');
      expect((await store.loadFiles(saved)).map((f) => f.name), ['small.pdf']);
    });
  });

  // ─────────────────────────── الشاشات ───────────────────────────
  group('مسوّداتي ونموذج المهمة', () {
    SessionState session({int userId = 1, int companyId = 10, String role = 'Employee', List<String>? modules}) =>
        SessionState(
          loaded: true,
          activeCompanyId: companyId,
          auth: AuthResult(
            accessToken: 't',
            accessExpires: DateTime.now().add(const Duration(hours: 1)),
            refreshToken: 'r',
            userId: userId,
            fullName: 'مستخدم',
            username: 'u',
            role: role,
            companyIds: [companyId],
            mustChangePassword: false,
            companies: [CompanyAccess(companyId: companyId, modules: modules ?? const ['Outgoing', 'Incoming', 'Tasks'])],
          ),
        );

    Future<void> pump(WidgetTester tester, Widget child, _MemoryStore store, SessionState s) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formDraftStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(_FakeApi()),
          sessionProvider.overrideWith(() => _FixedSession(s)),
          departmentsListProvider.overrideWith((ref) async => const <DepartmentModel>[]),
          assignableUsersProvider.overrideWith((ref) async => const <AssignableUser>[]),
        ],
        child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child))),
      ));
      await tester.pump();
    }

    testWidgets('🔐 مسوّداتي: مسوّداتي في هذه الشركة وحدها، والأخرى بالعدد', (tester) async {
      final store = _MemoryStore([
        draft(userId: 1, companyId: 10, title: 'مسوّدتي هنا'),
        draft(userId: 1, companyId: 20, title: 'مسوّدتي هناك'),
        draft(userId: 2, companyId: 10, title: 'مسوّدة زميلي'),
      ]);
      await pump(tester, const MyDraftsScreen(), store, session());
      expect(find.text('مسوّدتي هنا'), findsOneWidget);
      expect(find.text('مسوّدتي هناك'), findsNothing);
      expect(find.text('مسوّدة زميلي'), findsNothing, reason: 'الجهاز مشترك — ولا يرى أحدٌ مسوّدة غيره');
      expect(find.byKey(const Key('drafts-other-companies')), findsOneWidget);
    });

    testWidgets('مسوّداتي: الفاشلة تُظهر سببها', (tester) async {
      final store = _MemoryStore([draft(title: 'صادرٌ معلّق', error: 'تعذّر الوصول إلى الخادم')]);
      await pump(tester, const MyDraftsScreen(), store, session());
      expect(find.textContaining('لم يُرسَل — تعذّر الوصول إلى الخادم'), findsOneWidget);
    });

    testWidgets('🔐 مسوّدةُ قسمٍ لم يعُد يملكه ⇒ «فتح» معطَّل', (tester) async {
      final d = draft(kind: DraftKind.outgoing, title: 'صادر');
      await pump(tester, const MyDraftsScreen(), _MemoryStore([d]), session(modules: const ['Incoming']));
      final btn = tester.widget<FilledButton>(find.byKey(Key('open-draft-${d.id}')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('المهمة: فتحُ مسوّدة يملأ النموذج', (tester) async {
      final d = draft(kind: DraftKind.task, title: 'مراجعة العقد', fields: {
        'title': 'مراجعة العقد',
        'description': 'قراءة البنود',
        'notes': '',
        'taskType': 'Individual',
        'priority': 'High',
        'dueDate': null,
        'isRecurring': false,
        'recurrencePattern': 'Weekly',
        'recurrenceInterval': '1',
      });
      await pump(tester, TaskFormScreen(draftId: d.id), _MemoryStore([d]), session());
      expect(find.text('مراجعة العقد'), findsOneWidget);
      expect(find.text('قراءة البنود'), findsOneWidget);
      expect(find.text('إكمال مسوّدة — مهمة'), findsOneWidget);
    });

    testWidgets('المهمة: نموذجٌ جديد يعرض آخر مسوّدة للاستعادة — و«استعادة» تملؤه', (tester) async {
      final d = draft(kind: DraftKind.task, title: 'مهمة سابقة', fields: {'title': 'مهمة سابقة', 'priority': 'Normal'});
      await pump(tester, const TaskFormScreen(), _MemoryStore([d]), session());
      expect(find.byKey(const Key('draft-restore-banner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('draft-restore')));
      await tester.pump();
      expect(find.byKey(const Key('draft-restore-banner')), findsNothing);
      expect(find.widgetWithText(TextFormField, 'مهمة سابقة'), findsOneWidget);
    });

    testWidgets('🔐 لا يُعرض للاستعادة ما كتبه غيري أو ما في شركةٍ أخرى', (tester) async {
      final store = _MemoryStore([
        draft(kind: DraftKind.task, userId: 2, title: 'لزميلي'),
        draft(kind: DraftKind.task, companyId: 20, title: 'في شركةٍ أخرى'),
        draft(kind: DraftKind.outgoing, title: 'صادرٌ لا مهمة'),
      ]);
      await pump(tester, const TaskFormScreen(), store, session());
      expect(find.byKey(const Key('draft-restore-banner')), findsNothing);
    });

    testWidgets('🔴 المغادرة بما كُتب تسأل — و«احفظه» يُبقيه في مسوّداتي', (tester) async {
      final store = _MemoryStore([]);
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formDraftStoreProvider.overrideWithValue(store),
          sessionProvider.overrideWith(() => _FixedSession(session())),
          departmentsListProvider.overrideWith((ref) async => const <DepartmentModel>[]),
          assignableUsersProvider.overrideWith((ref) async => const <AssignableUser>[]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const TaskFormScreen())),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'مهمة لم تُرسَل');
      await tester.pump();

      // «إلغاء» ⇒ `maybePop` ⇒ يعترضه `PopScope` (كان `pop` فيتخطّاه).
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('لم يُرسَل بعد'), findsOneWidget);

      await tester.tap(find.byKey(const Key('draft-exit-keep')));
      await tester.pumpAndSettle();
      expect(find.text('افتح'), findsOneWidget, reason: 'غادر النموذج');
      expect(store.all().single.title, 'مهمة لم تُرسَل');
    });

    testWidgets('نموذجٌ فارغ يغادر بلا سؤال ولا يترك مسوّدة', (tester) async {
      final store = _MemoryStore([]);
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formDraftStoreProvider.overrideWithValue(store),
          sessionProvider.overrideWith(() => _FixedSession(session())),
          departmentsListProvider.overrideWith((ref) async => const <DepartmentModel>[]),
          assignableUsersProvider.overrideWith((ref) async => const <AssignableUser>[]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const TaskFormScreen())),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('لم يُرسَل بعد'), findsNothing);
      expect(find.text('افتح'), findsOneWidget);
      expect(store.all(), isEmpty);
    });
  });
}

/// مخزنٌ في الذاكرة — للودجات (Hive يحتاج قرصاً وانتظاراً حقيقياً).
class _MemoryStore extends FormDraftStore {
  _MemoryStore(List<FormDraft> seed) {
    for (final d in seed) {
      _items[d.id] = d;
    }
  }
  final Map<String, FormDraft> _items = {};
  final ValueNotifier<int> _tick = ValueNotifier(0);

  @override
  bool get isOpen => true;
  @override
  ValueListenable<Object?> listenable() => _tick;
  @override
  List<FormDraft> all() => _items.values.toList();
  @override
  FormDraft? get(String id) => _items[id];
  @override
  Future<FormDraft> put(FormDraft d, {List<DraftFileData>? files}) async {
    _items[d.id] = d;
    _tick.value++;
    return d;
  }

  @override
  Future<List<DraftFileData>> loadFiles(FormDraft d) async => const [];
  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _tick.value++;
  }
}

/// عميلٌ لا يلمس الشبكة — أسماءُ الشركات لبطاقة «شركاتٍ أخرى».
class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0', token: (() => null), companyId: (() => null));
  @override
  Future<List<Company>> companies({bool includeInactive = false}) async => const [];
}

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}
