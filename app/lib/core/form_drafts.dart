import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// المخزن — مزوّدٌ ليُستبدَل في الاختبارات (لا اشتقاقَ منه — ADR-042).
final formDraftStoreProvider = Provider<FormDraftStore>((ref) => FormDraftStore());

/// ─────────────────────────────────────────────────────────────────────────────
/// حماية ما يُكتب (ADR-051) — مسوّداتٌ محلّية **لها صاحبٌ وشركة**، تُحفظ تلقائياً أثناء الكتابة.
///
/// 🔴 **لماذا بُنيت من جديد؟** كانت «مسوّدات الأوفلاين» تَعِد بحمايةٍ لا تقدّمها:
/// - تُحفظ **فقط** حين يفشل «حفظ» بانقطاع — وعبر Cloudflare لا يأتي «انقطاعٌ» أبداً (502).
/// - **لا تُحفظ إن كانت الجهة جديدة** (يفشل إنشاؤها قبل بناء الحمولة).
/// - **لا حفظ أثناء الكتابة** — تحديثُ الصفحة أو الخروج يُضيع كلَّ شيء. وفي الصادر وحده.
/// - 🔐 **بلا صاحبٍ ولا شركة**: مستخدمٌ آخر على الجهاز نفسه يراها **ويرسلها باسمه**، ومَن
///   بدّل شركته تُرسَل مسوّدته إلى الشركة الجديدة.
/// - **وتُرسَل مرّتين** إن وصل الطلب وضاع ردُّه.
/// ─────────────────────────────────────────────────────────────────────────────

/// نوع النموذج الذي كُتبت فيه المسوّدة.
enum DraftKind { outgoing, incoming, task }

String draftKindLabel(DraftKind k) => switch (k) {
      DraftKind.outgoing => 'كتاب صادر',
      DraftKind.incoming => 'كتاب وارد',
      DraftKind.task => 'مهمة',
    };

/// أقصى مجموعٍ لملفات مسوّدةٍ واحدة يُحفظ على الجهاز (قرار المالك: 25 ميغابايت).
/// ما زاد يُحفظ اسمُه وحجمُه فقط، ويُطلب إرفاقُه من جديد.
const int kDraftFilesMaxBytes = 25 * 1024 * 1024;

/// فترة الحفظ التلقائيّ — يُحفظ ما تغيّر فقط.
const Duration kDraftAutosaveEvery = Duration(seconds: 3);

/// وصفُ ملفٍّ في المسوّدة — [stored] يعني أن بايتاته محفوظةٌ على الجهاز.
@immutable
class DraftFileMeta {
  final String name;
  final int size;
  final bool stored;
  const DraftFileMeta(this.name, this.size, this.stored);

  Map<String, dynamic> toJson() => {'name': name, 'size': size, 'stored': stored};
  factory DraftFileMeta.fromJson(Map<String, dynamic> j) =>
      DraftFileMeta(j['name'] as String, (j['size'] as num).toInt(), j['stored'] == true);
}

/// ملفٌّ كما في النموذج (بايتاته في الذاكرة).
@immutable
class DraftFileData {
  final String name;
  final Uint8List bytes;
  const DraftFileData(this.name, this.bytes);
}

/// مسوّدةٌ محفوظة.
@immutable
class FormDraft {
  final String id;
  final DraftKind kind;

  /// 🔐 صاحبها وشركتُها — لا يراها ولا يرسلها غيرُهما.
  final int userId;
  final int companyId;
  final String? companyName;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// ما يُعرض في القائمة (الموضوع أو العنوان).
  final String title;

  /// حقول النموذج — يملأها النموذج ويقرؤها (JSON خالص).
  final Map<String, dynamic> fields;

  final List<DraftFileMeta> files;

  /// سببُ آخر فشلٍ في الإرسال — `null` ما دامت لم تُرسَل قطّ.
  final String? lastError;

  /// ما أُنشئ فعلاً على الخادم في محاولةٍ سابقة — فلا يُنشأ ثانيةً.
  /// (الجهة الجديدة قبل الكتاب · والوارد قبل مرفقاته.)
  final int? createdEntityId;
  final int? createdRecordId;

  const FormDraft({
    required this.id,
    required this.kind,
    required this.userId,
    required this.companyId,
    this.companyName,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    required this.fields,
    this.files = const [],
    this.lastError,
    this.createdEntityId,
    this.createdRecordId,
  });

  /// مفتاح منع التكرار لخطوةٍ بعينها — **ثابتٌ لهذه المسوّدة** فيعيد الخادم ما أُنشئ أوّلاً.
  String idempotencyKey(String step) => '$id:$step';

  bool get failed => lastError != null;

  /// ملفاتٌ لم تُحفظ بايتاتُها (فوق الحدّ) — يلزم إرفاقُها من جديد.
  List<DraftFileMeta> get missingFiles => files.where((f) => !f.stored).toList();

  FormDraft copyWith({
    DateTime? updatedAt,
    String? title,
    Map<String, dynamic>? fields,
    List<DraftFileMeta>? files,
    String? lastError,
    bool clearError = false,
    int? createdEntityId,
    int? createdRecordId,
    String? companyName,
  }) =>
      FormDraft(
        id: id,
        kind: kind,
        userId: userId,
        companyId: companyId,
        companyName: companyName ?? this.companyName,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        title: title ?? this.title,
        fields: fields ?? this.fields,
        files: files ?? this.files,
        lastError: clearError ? null : (lastError ?? this.lastError),
        createdEntityId: createdEntityId ?? this.createdEntityId,
        createdRecordId: createdRecordId ?? this.createdRecordId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'userId': userId,
        'companyId': companyId,
        'companyName': companyName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'title': title,
        'fields': fields,
        'files': [for (final f in files) f.toJson()],
        'lastError': lastError,
        'createdEntityId': createdEntityId,
        'createdRecordId': createdRecordId,
      };

  factory FormDraft.fromJson(Map<String, dynamic> j) => FormDraft(
        id: j['id'] as String,
        kind: DraftKind.values.byName(j['kind'] as String),
        userId: (j['userId'] as num).toInt(),
        companyId: (j['companyId'] as num).toInt(),
        companyName: j['companyName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        title: j['title'] as String? ?? '',
        fields: Map<String, dynamic>.from(j['fields'] as Map? ?? const {}),
        files: [
          for (final f in (j['files'] as List? ?? const []))
            DraftFileMeta.fromJson(Map<String, dynamic>.from(f as Map))
        ],
        lastError: j['lastError'] as String?,
        createdEntityId: (j['createdEntityId'] as num?)?.toInt(),
        createdRecordId: (j['createdRecordId'] as num?)?.toInt(),
      );
}

// ───────────────────────────── قواعد نقيّة ─────────────────────────────

/// 🔐 مسوّدات هذا المستخدم وحده، الأحدث أوّلاً.
List<FormDraft> draftsOf(Iterable<FormDraft> all, int userId) =>
    all.where((d) => d.userId == userId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

/// تقسيمُ مسوّدات المستخدم: ما في الشركة الفعّالة (تُفتح وتُرسل)، وما في غيرها (**بالعدد**
/// واسم الشركة — لا تُفتح هنا لأن إرسالها يقع في الشركة الفعّالة).
({List<FormDraft> here, Map<int, ({String? name, int count})> elsewhere}) splitByCompany(
    List<FormDraft> mine, int? activeCompanyId) {
  final here = <FormDraft>[];
  final elsewhere = <int, ({String? name, int count})>{};
  for (final d in mine) {
    if (d.companyId == activeCompanyId) {
      here.add(d);
    } else {
      final prev = elsewhere[d.companyId];
      elsewhere[d.companyId] = (name: d.companyName ?? prev?.name, count: (prev?.count ?? 0) + 1);
    }
  }
  return (here: here, elsewhere: elsewhere);
}

/// أيُّ الملفات تُحفظ بايتاتُها — **بالترتيب** ما دام المجموع ≤ [maxBytes].
/// ⚠️ **لا قفزَ فوق ملفٍّ كبير لحفظ صغيرٍ بعده**: ترتيبُ الصفحات الممسوحة معنى، ومسوّدةٌ
/// فيها الصفحة ٣ بلا ٢ أسوأ من مسوّدةٍ تطلب إعادة الإرفاق من ٢ فصاعداً.
List<bool> planFileStorage(List<int> sizes, {int maxBytes = kDraftFilesMaxBytes}) {
  final plan = <bool>[];
  var total = 0;
  var open = true;
  for (final s in sizes) {
    open = open && total + s <= maxBytes;
    if (open) total += s;
    plan.add(open);
  }
  return plan;
}

/// نصّ التنبيه — بصيغة العدد العربية.
String draftsNoticeText(int n) => switch (n) {
      1 => 'لديك مسوّدةٌ لم تُرسَل — راجعها ثم أرسلها.',
      2 => 'لديك مسوّدتان لم تُرسَلا — راجعهما ثم أرسلهما.',
      >= 3 && <= 10 => 'لديك $n مسوّدات لم تُرسَل — راجعها ثم أرسلها.',
      _ => 'لديك $n مسوّدة لم تُرسَل — راجعها ثم أرسلها.',
    };

/// معرّفٌ عشوائيّ (UUID v4 نصاً) — يصلح مفتاحاً لمنع التكرار على الخادم (`[A-Za-z0-9-]`).
String newDraftId([Random? rnd]) {
  final r = rnd ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${[0, 1, 2, 3].map(h).join()}-${[4, 5].map(h).join()}-${[6, 7].map(h).join()}-'
      '${[8, 9].map(h).join()}-${[10, 11, 12, 13, 14, 15].map(h).join()}';
}

// ───────────────────────────── التخزين ─────────────────────────────

/// المخزن — صندوقان في Hive (IndexedDB على الويب):
/// - [metaBox] الوصفُ والحقول (صغيرة، تُحمَّل كلُّها).
/// - [filesBox] بايتات الملفات — **`LazyBox`** لا يُحمَّل إلى الذاكرة إلا عند الطلب، وإلا
///   حُمِّلت 25 ميغابايت لكل مسوّدة مع كل فتحٍ للتطبيق.
class FormDraftStore {
  static const metaBox = 'dms_form_drafts';
  static const filesBox = 'dms_form_draft_files';

  /// الصندوق القديم (مسوّدات الأوفلاين بلا صاحب) — يُحذف عند الإقلاع.
  static const legacyBox = 'dms_offline_drafts';

  static Future<void> open() async {
    // ⚠️ فشلُ فتح التخزين (تصفّحٌ خاصّ · مساحةٌ ممتلئة) **لا يمنع إقلاع التطبيق** — يعمل
    //    بلا مسوّدات، و`isOpen` يحرس كلَّ قراءةٍ وكتابة.
    try {
      await Hive.openBox<String>(metaBox);
      await Hive.openLazyBox<Uint8List>(filesBox);
    } catch (e) {
      debugPrint('تعذّر فتح مخزن المسوّدات: $e');
    }
    // ⚠️ **يُمحى لا يُرحَّل**: لا صاحبَ لمحتواه ولا شركة، فترحيلُه يعني نسبتَه لأيٍّ من
    //    يدخل أوّلاً — وهو بالضبط العيب الذي يُعالَج. (ولم يبدأ الإنتاج، فمحتواه بياناتُ تجربة.)
    try {
      await Hive.deleteBoxFromDisk(legacyBox);
    } catch (_) {}
  }

  Box<String> get _meta => Hive.box<String>(metaBox);
  LazyBox<Uint8List> get _files => Hive.lazyBox<Uint8List>(filesBox);

  /// ⚠️ **صندوقٌ غير مفتوح ليس عطلاً يُسقط الواجهة** — الشريط الجانبيّ يقرأ المخزن في كل
  ///    شاشة، فرميُ `HiveError` هنا كان يُسقطها كلَّها (في الاختبارات، وفي أيّ فشلٍ لفتح
  ///    IndexedDB — تصفّحٌ خاصّ مثلاً). بلا صندوقٍ ⇒ بلا مسوّدات، والتطبيق يعمل.
  bool get isOpen => Hive.isBoxOpen(metaBox);

  static final ValueNotifier<int> _closed = ValueNotifier(0);

  /// يُستمع إليه لتحديث القائمة والشارة.
  ValueListenable<Object?> listenable() => isOpen ? _meta.listenable() : _closed;

  List<FormDraft> all() {
    if (!isOpen) return const [];
    final out = <FormDraft>[];
    for (final raw in _meta.values) {
      try {
        out.add(FormDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // سجلٌّ تالف لا يُسقط القائمة كلَّها.
      }
    }
    return out;
  }

  FormDraft? get(String id) {
    if (!isOpen) return null;
    final raw = _meta.get(id);
    if (raw == null) return null;
    try {
      return FormDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// يحفظ المسوّدة. [files] إن مُرّر يستبدل ملفاتها كلَّها (وُصفاً وبايتات).
  Future<FormDraft> put(FormDraft d, {List<DraftFileData>? files}) async {
    if (!isOpen) return d;
    var draft = d;
    if (files != null) {
      final plan = planFileStorage([for (final f in files) f.bytes.length]);
      await _deleteFiles(d.id);
      for (var i = 0; i < files.length; i++) {
        if (plan[i]) await _files.put(_fileKey(d.id, i), files[i].bytes);
      }
      draft = d.copyWith(files: [
        for (var i = 0; i < files.length; i++) DraftFileMeta(files[i].name, files[i].bytes.length, plan[i])
      ]);
    }
    await _meta.put(draft.id, jsonEncode(draft.toJson()));
    return draft;
  }

  /// الملفات المحفوظة بايتاتُها — بترتيبها.
  Future<List<DraftFileData>> loadFiles(FormDraft d) async {
    if (!Hive.isBoxOpen(filesBox)) return const [];
    final out = <DraftFileData>[];
    for (var i = 0; i < d.files.length; i++) {
      if (!d.files[i].stored) continue;
      final bytes = await _files.get(_fileKey(d.id, i));
      if (bytes != null) out.add(DraftFileData(d.files[i].name, bytes));
    }
    return out;
  }

  Future<void> delete(String id) async {
    if (!isOpen) return;
    await _meta.delete(id);
    await _deleteFiles(id);
  }

  Future<void> _deleteFiles(String id) async {
    final prefix = '$id/';
    final keys = _files.keys.where((k) => k is String && k.startsWith(prefix)).toList();
    await _files.deleteAll(keys);
  }

  static String _fileKey(String id, int i) => '$id/$i';
}

// ───────────────────────────── الحفظ التلقائيّ ─────────────────────────────

/// لقطةٌ من النموذج — `null` من [DraftAutosaver.capture] تعني «فارغ، لا شيء يستحقّ الحفظ».
@immutable
class DraftSnapshot {
  final String title;
  final Map<String, dynamic> fields;

  /// `null` ⇒ النموذج بلا ملفات أصلاً (الصادر والمهمة).
  final List<DraftFileData>? files;

  const DraftSnapshot({required this.title, required this.fields, this.files});
}

/// يحفظ النموذج على الجهاز **كل [kDraftAutosaveEvery] إن تغيّر**، ويُفرَغ قبل تحديث الصفحة.
///
/// 🔑 **دوريٌّ بمقارنة لا مستمعٌ لكل حقل**: ربطُ كل حقلٍ ومنسدلةٍ وتاريخ بمستمع يعني أن حقلاً
/// يُضاف لاحقاً وينسى صاحبُه ربطَه **يضيع صامتاً**. واللقطةُ تلتقط كلَّ ما يعرفه النموذج.
class DraftAutosaver {
  DraftAutosaver({
    required this.store,
    required this.kind,
    required this.userId,
    required this.companyId,
    required this.capture,
    this.companyName,
    String? id,
  }) : id = id ?? newDraftId();

  final FormDraftStore store;
  final DraftKind kind;
  final int userId;
  final int companyId;
  final String? companyName;
  final DraftSnapshot? Function() capture;

  /// معرّف المسوّدة — يتغيّر إن اعتُمدت مسوّدةٌ قائمة ([adopt]).
  String id;

  Timer? _timer;
  String? _lastFieldsJson;
  String? _lastFilesSig;
  bool _disposed = false;

  static final Set<DraftAutosaver> _active = {};

  /// يُفرغ كلَّ النماذج المفتوحة — **قبل إعادة تحميل الصفحة** (تحديث الواجهة).
  static Future<void> flushAll() async {
    for (final a in _active.toList()) {
      await a.flush();
    }
  }

  void start() {
    _active.add(this);
    _timer ??= Timer.periodic(kDraftAutosaveEvery, (_) => flush());
  }

  /// المسوّدة المحفوظة الآن لهذا النموذج (إن وُجدت).
  FormDraft? get current => store.get(id);

  /// يعتمد مسوّدةً قائمة — فيكمل الحفظ عليها بدل إنشاء أخرى.
  void adopt(FormDraft d) {
    id = d.id;
    _lastFieldsJson = jsonEncode(d.fields);
    _lastFilesSig = null;
  }

  /// يحفظ إن تغيّر شيء. ويحذف المسوّدة إن أُفرغ النموذج كلُّه.
  Future<FormDraft?> flush({bool force = false}) async {
    if (_disposed) return null;
    final snap = capture();
    final existing = store.get(id);
    if (snap == null) {
      // أفرغ المستخدم النموذج — لا تبقى «مسوّدةٌ» فارغة في القائمة.
      // ⚠️ إلا إن كان شيءٌ قد أُنشئ على الخادم منها: تلك تبقى لتُكمَل.
      if (existing != null && existing.createdEntityId == null && existing.createdRecordId == null) {
        await store.delete(id);
      }
      _lastFieldsJson = null;
      return null;
    }
    final fieldsJson = jsonEncode(snap.fields);
    final filesSig = snap.files?.map((f) => '${f.name}:${f.bytes.length}').join('|');
    final changed = force || existing == null || fieldsJson != _lastFieldsJson || filesSig != _lastFilesSig;
    if (!changed) return existing;

    final now = DateTime.now();
    final base = existing ??
        FormDraft(
          id: id,
          kind: kind,
          userId: userId,
          companyId: companyId,
          companyName: companyName,
          createdAt: now,
          updatedAt: now,
          title: snap.title,
          fields: snap.fields,
        );
    final saved = await store.put(
      base.copyWith(updatedAt: now, title: snap.title, fields: snap.fields, companyName: companyName),
      files: filesSig != _lastFilesSig || existing == null ? snap.files : null,
    );
    _lastFieldsJson = fieldsJson;
    _lastFilesSig = filesSig;
    return saved;
  }

  /// فشل الإرسال — تُحفظ المسوّدة (بآخر ما كُتب) مع السبب.
  Future<void> markFailed(String message) async {
    await flush(force: true);
    final d = store.get(id);
    if (d != null) await store.put(d.copyWith(lastError: message));
  }

  /// ما أُنشئ على الخادم — ليُكمَل لا ليُعاد.
  Future<void> recordProgress({int? entityId, int? recordId}) async {
    await flush(force: true);
    final d = store.get(id);
    if (d != null) await store.put(d.copyWith(createdEntityId: entityId, createdRecordId: recordId));
  }

  /// أُرسلت بنجاح أو تجاهلها صاحبها.
  Future<void> discard() async {
    await store.delete(id);
    _lastFieldsJson = null;
    _lastFilesSig = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _active.remove(this);
  }
}
