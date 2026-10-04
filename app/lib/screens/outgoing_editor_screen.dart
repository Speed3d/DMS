import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/company_providers.dart';
import '../core/form_drafts.dart';
import '../core/local_storage.dart';
import '../core/outgoing_providers.dart';
import '../core/quill_html.dart';
import '../core/quill_toolbar.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/book_paper.dart';
import '../widgets/book_table/bt_dialogs.dart';
import '../widgets/book_table/bt_editor_hub.dart';
import '../widgets/book_table/bt_table_editor.dart';
import '../widgets/book_table/bt_table_toolbar.dart';
import '../widgets/book_table/bt_table_view.dart';
import '../widgets/custom_card.dart';
import '../widgets/draft_widgets.dart';
import '../widgets/financial_bar.dart';
import '../widgets/pdf_preview_pane.dart';

/// ما يفعله المحرّر — والشاشة واحدةٌ للثلاثة (ADR-057).
enum OutgoingEditorMode { create, editDraft, editApproved }

/// محرّر الكتاب الصادر — **شاشةٌ واحدة** للإنشاء وتعديل المسودّة والتعديل بعد الاعتماد (ADR-057).
///
/// 🔑 **كانت ثلاث شاشاتٍ نسخاً متقاربة** فتباعدت: الإنشاء وحده يحفظ المسوّدة ويسأل عند المغادرة ويتحوّل لتبويبين في
/// الضيّق، والتعديلان بلا شيءٍ من ذلك (وفيهما قنبلةٌ أُصلحت في 0.11.1). الآن ما يُصلَح يُصلَح للثلاثة.
///
/// 📄 **«الورقة»** (قرار المالك ت١٢ ب): A4 بأبعادها الحقيقية · الترويسة والتذييل والعلامة المائية من القالب · Times New
/// Roman 12 · **وبجانبها معاينة PDF الحقيقية تتحدّث وحدها** بعد توقّف الكتابة.
///
/// 📱 **الهاتف للعرض والاعتماد لا للتحرير** (قرار المالك ت١٣) — دون 700 بكسل رسالةٌ لا محرّرٌ لا يُستعمل.
class OutgoingEditorScreen extends ConsumerStatefulWidget {
  const OutgoingEditorScreen({super.key, required this.mode, this.book, this.draftId})
      : assert(mode == OutgoingEditorMode.create || book != null, 'التعديل يحتاج الكتاب');

  final OutgoingEditorMode mode;
  final OutgoingDetail? book;

  /// فتحُ مسوّدةٍ محفوظة من «مسوّداتي» (ADR-051) — للإنشاء وحده.
  final String? draftId;

  /// دون هذا العرض: «التحرير متاح على الحاسوب».
  static const double phoneWidth = 700;

  /// دون هذا العرض: تبويبان (الورقة · المعاينة) بدل ثلاثة أعمدة.
  static const double wideWidth = 1200;

  /// انتظار توقّف الكتابة قبل تحديث المعاينة وحدها — التوليد ~1.5 ثانية في الخادم فلا يُطلب مع كل حرف.
  static const previewDebounce = Duration(milliseconds: 1800);

  @override
  ConsumerState<OutgoingEditorScreen> createState() => _OutgoingEditorScreenState();
}

class _OutgoingEditorScreenState extends ConsumerState<OutgoingEditorScreen> {
  final _subject = TextEditingController();
  final _headerPhrase = TextEditingController();
  final _signatoryName = TextEditingController();
  final _signatoryTitle = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  late final quill.QuillController _quill;

  /// محرّك الجداول (الدفعة ٧) — التحديد والخلية المفتوحة خارج شجرة Quill فلا تضيع مع إعادة بنائها.
  late final BtEditorHub _tables;
  final _editorFocus = FocusNode(debugLabel: 'paper');
  final _editorScroll = ScrollController();
  final _paperScroll = ScrollController();

  bool _showFinancials = false;
  DateTime _date = DateTime.now();
  int? _entityId;
  String _entityText = '';
  int? _templateId;
  String? _currency;

  // ── ADR-057: النوع وخيارات الطباعة ──
  int? _typeId;
  bool _printEntity = true;
  bool _printSubject = true;
  bool _pageNumbers = true;
  SignaturePlacement _placement = SignaturePlacement.lastPage;

  bool _busy = false;
  String? _error;

  // ── المعاينة: تتحدّث وحدها بعد توقّف الكتابة، وتسلسلٌ يُسقط ردّاً قديماً وصل بعد أحدث منه ──
  Uint8List? _previewBytes;
  bool _previewBusy = false;
  bool _previewStale = false;
  bool _previewQueued = false;
  String? _previewError;
  Timer? _previewTimer;
  int _previewSeq = 0;

  late Future<_Refs> _refs;
  _Refs? _loaded;

  // ── حماية ما يُكتب ──
  DraftAutosaver? _drafts;         // الإنشاء (ADR-051)
  FormDraft? _offer;
  int _offerOthers = 0;
  int _formGen = 0;
  String? _baseline;               // التعديل: بصمة ما فُتح به الكتاب — تُقارَن عند المغادرة

  final _assetsCache = <int, PaperAssets>{};
  PaperAssets _assets = PaperAssets.empty;
  TextEditingController? _entityField;

  bool get _isCreate => widget.mode == OutgoingEditorMode.create;
  bool get _isApproved => widget.mode == OutgoingEditorMode.editApproved;

  List<TextEditingController> get _watched => [_subject, _headerPhrase, _signatoryName, _signatoryTitle, _amount, _rate];

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _tables = BtEditorHub(
      fetchWords: (value, currency) => ref.read(apiClientProvider).numberWords(value, currency),
      onMessage: _say,
      askPasteAsTable: (rows, cols) => showBtPasteAsTableDialog(context, rows, cols),
      focusMain: (offset) {
        final max = _quill.document.length - 1;
        _quill.updateSelection(TextSelection.collapsed(offset: offset.clamp(0, max < 0 ? 0 : max)), quill.ChangeSource.local);
        _editorFocus.requestFocus();
      },
    );
    _quill = b == null ? quill.QuillController.basic(config: _quillConfig) : _controllerFrom(b);
    _tables.attach(_quill);
    // نقرةٌ في المتن تُغادر الجدول (وتحفظ الخلية المفتوحة)
    _editorFocus.addListener(() => _tables.onMainFocus(_editorFocus.hasPrimaryFocus));
    // الكتابة في خليةٍ لم تُغادَر بعد تغيّر الناتج: المعاينة تُعلَّم قديمةً وتُجدوَل
    _tables.contentTick.addListener(_changed);
    if (b != null) {
      _subject.text = b.subject;
      _headerPhrase.text = b.headerPhrase ?? '';
      _signatoryName.text = b.signatoryName ?? '';
      _signatoryTitle.text = b.signatoryTitle ?? '';
      _amount.text = b.amount?.toString() ?? '';
      _rate.text = b.exchangeRate?.toString() ?? '';
      _showFinancials = b.amount != null;
      _date = b.date;
      _entityId = b.entityId;
      _entityText = b.entityName;
      _templateId = b.templateId;
      _currency = b.currency;
      _typeId = b.bookTypeId;
      _printEntity = b.printEntity;
      _printSubject = b.printSubject;
      _pageNumbers = b.pageNumbers;
      _placement = b.signaturePlacement;
    }
    if (_isCreate) _drafts = _createAutosaver();
    _refs = _loadRefs();
    for (final c in _watched) {
      c.addListener(_changed);
    }
    _quill.addListener(_changed);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _drafts?.dispose();
    for (final c in [..._watched, _note]) {
      c.dispose();
    }
    _tables.dispose();
    _quill.dispose();
    _editorFocus.dispose();
    _editorScroll.dispose();
    _paperScroll.dispose();
    super.dispose();
  }

  /// لصقُ جدولٍ منسوخ في المتن يُعرض «إدراجه جدولاً؟» (الجداول — ADR-057).
  /// ⚠️ `onClipboardPaste` «تجريبيّ» في flutter_quill — لا بديل عنه، والإصدار مثبَّت وحارسه في `outgoing_table_editor_test.dart`.
  quill.QuillControllerConfig get _quillConfig => quill.QuillControllerConfig(
        // ignore: experimental_member_use
        clipboardConfig: quill.QuillClipboardConfig(onClipboardPaste: _tables.onMainPaste),
      );

  /// محرّرٌ من Delta المخزّن (تنسيقٌ كامل وجداول)، أو من نصٍّ خامّ لكتبٍ قديمة بلا Delta.
  quill.QuillController _controllerFrom(OutgoingDetail b) {
    if (b.bodyJson != null && b.bodyJson!.isNotEmpty) {
      try {
        final doc = quill.Document.fromJson(jsonDecode(b.bodyJson!) as List);
        return quill.QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0), config: _quillConfig);
      } catch (_) {
        // Delta تالف ⟵ النصّ الخامّ أدناه
      }
    }
    return quill.QuillController(
      document: quill.Document()..insert(0, '${b.bodyHtml.replaceAll(RegExp(r'<[^>]*>'), '')}\n'),
      selection: const TextSelection.collapsed(offset: 0),
      config: _quillConfig,
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
  }

  /// «إدراج جدول» — عند المؤشّر في المتن.
  Future<void> _insertTable() async {
    _tables.exit();
    final t = await showBtInsertDialog(context);
    if (t != null && mounted) _tables.insertTable(t);
  }

  // ─────────────────────────── التغيّر والمعاينة ───────────────────────────

  /// كلُّ ما يغيّر الناتج يمرّ هنا: المعاينة تُعلَّم قديمةً وتُجدوَل.
  void _changed() {
    if (_previewBytes != null && !_previewStale && mounted) setState(() => _previewStale = true);
    _schedulePreview();
  }

  void _setOption(VoidCallback fn) {
    setState(fn);
    _changed();
  }

  void _schedulePreview() {
    if (_loaded == null) return;
    _previewTimer?.cancel();
    _previewTimer = Timer(OutgoingEditorScreen.previewDebounce, () => _refreshPreview(auto: true));
  }

  /// يولّد المعاينة في الخادم. **التلقائيّة لا تُنشئ جهةً جديدة** (أثرٌ في القاعدة بلا قصد) ولا تُظهر أخطاء التحقّق
  /// باللون الأحمر — زرّ «تحديث» وحده يفعل الاثنين.
  Future<void> _refreshPreview({bool auto = false}) async {
    if (!mounted) return;
    if (_previewBusy) {
      _previewQueued = true;
      return;
    }
    if (_entityText.trim().isEmpty) {
      setState(() => _previewError = 'أدخل الجهة المستلمة لتظهر المعاينة.');
      return;
    }
    final api = ref.read(apiClientProvider);
    if (_entityId == null) {
      if (auto) {
        setState(() => _previewError = 'جهةٌ جديدة: اضغط «تحديث» لإنشائها ومعاينة الكتاب — أو اخترها من القائمة.');
        return;
      }
      try {
        final e = await api.createEntity(_entityText.trim(), 'Both');
        _entityId = e.entityId;
      } on ApiException catch (e) {
        if (mounted) setState(() => _previewError = e.message);
        return;
      }
    }
    final (payload, problem) = _payload(report: !auto);
    if (payload == null) {
      if (auto && mounted) setState(() => _previewError = problem);
      return;
    }
    final seq = ++_previewSeq;
    setState(() {
      _previewBusy = true;
      _previewError = null;
    });
    try {
      final bytes = await api.previewOutgoing(payload);
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _previewBytes = bytes;
        _previewStale = false;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _previewSeq) setState(() => _previewError = e.message);
    } finally {
      if (mounted) setState(() => _previewBusy = false);
      if (_previewQueued) {
        _previewQueued = false;
        _schedulePreview();
      }
    }
  }

  // ─────────────────────────── المسوّدة (الإنشاء — ADR-051) ───────────────────────────

  DraftAutosaver? _createAutosaver() {
    final s = ref.read(sessionProvider);
    final userId = s.auth?.userId;
    final companyId = s.effectiveCompanyId;
    if (userId == null || companyId == null) return null;
    final store = ref.read(formDraftStoreProvider);
    final saver = DraftAutosaver(
      store: store,
      kind: DraftKind.outgoing,
      userId: userId,
      companyId: companyId,
      companyName: ref.read(activeCompanyProvider).value?.name,
      id: widget.draftId,
      capture: _captureDraft,
    );
    if (widget.draftId == null) {
      final mine = splitByCompany(draftsOf(store.all(), userId), companyId).here.where((d) => d.kind == DraftKind.outgoing).toList();
      if (mine.isNotEmpty) {
        _offer = mine.first;
        _offerOthers = mine.length - 1;
      }
    }
    return saver..start();
  }

  /// ما يستحقّ الحفظ — **والتوقيع الافتراضيّ ليس «كتابة»** (يُملأ من الشركة تلقائياً).
  bool get _hasContent =>
      _subject.text.trim().isNotEmpty || !_quill.document.isEmpty() || _entityText.trim().isNotEmpty || _amount.text.trim().isNotEmpty;

  Map<String, dynamic> _fields() => {
        'entityId': _entityId,
        'entityText': _entityText,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'subject': _subject.text,
        'headerPhrase': _headerPhrase.text,
        'signatoryName': _signatoryName.text,
        'signatoryTitle': _signatoryTitle.text,
        'body': _tables.bodyDelta(),   // بالخلية المفتوحة — فلا يضيع ما كُتب ولم يُغادَر
        'showFinancials': _showFinancials,
        'amount': _amount.text,
        'rate': _rate.text,
        'currency': _currency,
        // ADR-057
        'typeId': _typeId,
        'printEntity': _printEntity,
        'printSubject': _printSubject,
        'pageNumbers': _pageNumbers,
        'placement': _placement.wire,
      };

  DraftSnapshot? _captureDraft() => _hasContent ? DraftSnapshot(title: _subject.text.trim(), fields: _fields()) : null;

  /// يملأ النموذج من مسوّدة. ⚠️ لا `setState` هنا — المنادي يقرّر (قبل البناء الأوّل أو بعده).
  void _applyDraft(FormDraft d, {List<EntityModel> entities = const []}) {
    final f = d.fields;
    final entityId = (f['entityId'] as num?)?.toInt() ?? d.createdEntityId;
    // ⚠️ جهةٌ حُذفت منذ الحفظ ⇒ يُبقى نصُّها فتُنشأ من جديد، لا معرّفٌ يرفضه الخادم.
    _entityId = entities.isEmpty || entities.any((e) => e.entityId == entityId) ? entityId : null;
    _entityText = f['entityText'] as String? ?? '';
    _templateId = (f['templateId'] as num?)?.toInt();
    _date = DateTime.tryParse(f['date'] as String? ?? '') ?? _date;
    _subject.text = f['subject'] as String? ?? '';
    _headerPhrase.text = f['headerPhrase'] as String? ?? '';
    _signatoryName.text = f['signatoryName'] as String? ?? '';
    _signatoryTitle.text = f['signatoryTitle'] as String? ?? '';
    final body = f['body'];
    if (body is List && body.isNotEmpty) _quill.document = quill.Document.fromJson(body);
    _showFinancials = f['showFinancials'] == true;
    _amount.text = f['amount'] as String? ?? '';
    _rate.text = f['rate'] as String? ?? '';
    _currency = f['currency'] as String?;
    _typeId = (f['typeId'] as num?)?.toInt() ?? _typeId;
    _printEntity = f['printEntity'] as bool? ?? true;
    _printSubject = f['printSubject'] as bool? ?? true;
    _pageNumbers = f['pageNumbers'] as bool? ?? true;
    _placement = SignaturePlacement.parse(f['placement'] as String?);
    _drafts?.adopt(d);
  }

  Future<void> _restoreOffered() async {
    final d = _offer;
    if (d == null) return;
    final refs = await _refs;
    if (!mounted) return;
    await _drafts?.discard();
    setState(() {
      _applyDraft(d, entities: refs.entities);
      _offer = null;
      _entityField = null;   // حقل الجهة يُبنى من جديد بنصّ المسوّدة
      _formGen++;
    });
    _changed();
  }

  // ─────────────────────────── التحميل ───────────────────────────

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(localStorageProvider);
    final session = ref.read(sessionProvider);
    _Refs refs;
    try {
      final entities = await api.entities();
      final templates = await api.templates();
      final types = await _types(api);
      if (_isCreate && session.activeCompanyId != null) {
        final companies = await api.companies();
        final active = companies.cast<Company?>().firstWhere((c) => c?.companyId == session.activeCompanyId, orElse: () => null);
        if (active != null) {
          if (_signatoryName.text.isEmpty && active.defaultSignatoryName != null) _signatoryName.text = active.defaultSignatoryName!;
          if (_signatoryTitle.text.isEmpty && active.defaultSignatoryTitle != null) _signatoryTitle.text = active.defaultSignatoryTitle!;
        }
      }
      // 🐛 النسخة المحلّية لدون اتصال **تحسينٌ لا شرط**: تخزينٌ معطَّل (تصفّحٌ خاصّ · مساحةٌ ممتلئة) كان يُسقط
      //    التحميل كلَّه فلا يُفتح المحرّر — كشفه حارس الشاشة (درسٌ مسجّل: فشلُ التخزين المحلّي يُلتقط في الكود).
      try {
        await storage.cacheEntities(entities);
        await storage.cacheTemplates(templates);
      } catch (_) {}
      refs = _Refs(entities, templates.where((t) => t.isActive).toList(), types);
      final opened = widget.draftId == null ? null : ref.read(formDraftStoreProvider).get(widget.draftId!);
      if (opened != null) _applyDraft(opened, entities: entities);
    } on ApiException catch (e, st) {
      if (!e.isNetworkError) rethrow;
      List<EntityModel> cachedEntities;
      List<TemplateModel> cachedTemplates;
      try {
        cachedEntities = storage.getCachedEntities();
        cachedTemplates = storage.getCachedTemplates();
      } catch (_) {
        // لا نسخة محلّية ⟵ **خطأ الشبكة الأصليّ** هو ما يُعرض (لا خطأ التخزين — `rethrow` هنا كان سيرمي ذاك)
        Error.throwWithStackTrace(e, st);
      }
      if (cachedEntities.isEmpty || cachedTemplates.isEmpty) rethrow;
      refs = _Refs(cachedEntities, cachedTemplates.where((t) => t.isActive).toList(), const []);
      final opened = widget.draftId == null ? null : ref.read(formDraftStoreProvider).get(widget.draftId!);
      if (opened != null) _applyDraft(opened, entities: cachedEntities);
    }

    // جهةٌ حُذفت أو قالبٌ عُطِّل منذ الحفظ ⇒ بلا قيمةٍ مختارة (وإلا سقطت المنسدلة لأن قيمتها ليست في عناصرها)
    // — ويُطلب الاختيار عند الحفظ بدل إرسال معرّفٍ يرفضه الخادم. (الدرس 0.11.1، صار للثلاثة.)
    if (!_isCreate) _entityId = safeDropdownValue(_entityId, refs.entities.map((e) => e.entityId));
    _templateId = safeDropdownValue(_templateId, refs.templates.map((t) => t.templateId));
    _typeId = safeDropdownValue(_typeId, refs.types.map((t) => t.outgoingBookTypeId));
    // الكتاب الجديد يبدأ بالنوع الأوّل — «كتاب رسمي» (قرار المالك)
    if (_isCreate && _typeId == null && refs.types.isNotEmpty) _typeId = refs.types.first.outgoingBookTypeId;

    _loaded = refs;
    if (!_isCreate) _baseline = _fingerprint();
    unawaited(_loadAssets(_templateId));
    // كتابٌ يُفتح للتعديل أو مسوّدةٌ تُكمَل: المعاينة تظهر وحدها — لا تنتظر أوّل حرفٍ يُكتب.
    if (_entityId != null && _subject.text.trim().isNotEmpty) _schedulePreview();
    return refs;
  }

  /// الأنواع — وخادمٌ أقدم بلا النقطة لا يُسقط المحرّر (قائمةٌ فارغة ⟵ يُخفى الحقل).
  Future<List<OutgoingBookTypeModel>> _types(ApiClient api) async {
    try {
      return await api.outgoingBookTypes();
    } on ApiException {
      return const [];
    }
  }

  /// صور القالب للورقة — تُحمَّل مرّةً لكل قالب، وفشلُها لا يمنع الكتابة (تظهر الأشرطة بلا صور).
  Future<void> _loadAssets(int? templateId) async {
    if (templateId == null) {
      if (mounted) setState(() => _assets = PaperAssets.empty);
      return;
    }
    final cached = _assetsCache[templateId];
    if (cached != null) {
      if (mounted) setState(() => _assets = cached);
      return;
    }
    final api = ref.read(apiClientProvider);
    Future<Uint8List?> img(String kind) async {
      try {
        return await api.getTemplateImage(templateId, kind);
      } catch (_) {
        return null;
      }
    }

    final images = await Future.wait([img('header'), img('footer'), img('watermark')]);
    final opacity = _loaded?.templates.where((t) => t.templateId == templateId).map((t) => t.watermarkOpacity).firstOrNull ?? 10;
    final assets = PaperAssets(header: images[0], footer: images[1], watermark: images[2], watermarkOpacity: opacity);
    _assetsCache[templateId] = assets;
    if (mounted && _templateId == templateId) setState(() => _assets = assets);
  }

  /// بصمة ما في النموذج — للتعديل: هل تغيّر شيءٌ منذ الفتح؟
  String _fingerprint() => jsonEncode(_fields());

  bool get _isDirty => _baseline != null && _fingerprint() != _baseline;

  // ─────────────────────────── الحمولة والحفظ ───────────────────────────

  /// حمولة الطلب — أو سبب امتناعها. [report]: يُعرض السبب باللون الأحمر (الحفظ وزرّ التحديث) لا في التلقائيّ.
  (Map<String, dynamic>?, String?) _payload({required bool report}) {
    String? problem;
    if (_entityId == null) {
      problem = _isCreate ? 'يرجى تحديد الجهة المقصودة أولاً.' : 'اختر الجهة المستلمة.';
    } else if (_templateId == null) {
      problem = _isCreate ? 'يرجى اختيار القالب.' : 'اختر القالب — القالب السابق لم يعُد فعّالاً.';
    } else if (_subject.text.trim().isEmpty) {
      problem = 'موضوع الكتاب مطلوب.';
    } else if (_quill.document.isEmpty()) {
      problem = 'نص الكتاب لا يمكن أن يكون فارغاً.';
    }
    num? amount;
    num? rate;
    if (problem == null && _amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) {
        problem = 'صيغة المبلغ غير صالحة.';
      } else if (_currency == null) {
        problem = 'يرجى اختيار العملة.';
      } else if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) problem = 'سعر الصرف إلزامي عند اختيار الدولار.';
      }
    }
    if (problem != null) {
      if (report) setState(() => _error = problem);
      return (null, problem);
    }
    final delta = _tables.bodyDelta();   // بالخلية المفتوحة
    return (
      {
        'entityId': _entityId,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'headerPhrase': _headerPhrase.text.trim().isEmpty ? null : _headerPhrase.text.trim(),
        'signatoryName': _signatoryName.text.trim().isEmpty ? null : _signatoryName.text.trim(),
        'signatoryTitle': _signatoryTitle.text.trim().isEmpty ? null : _signatoryTitle.text.trim(),
        'subject': _subject.text.trim(),
        'bodyHtml': quillDeltaToHtml(delta),
        'bodyJson': jsonEncode(delta),
        'amount': amount,
        'currency': amount == null ? null : _currency,
        'exchangeRate': rate,
        // ADR-057: النوع وخيارات الطباعة
        'outgoingBookTypeId': _typeId,
        'printEntity': _printEntity,
        'printSubject': _printSubject,
        'pageNumbers': _pageNumbers,
        'signaturePlacement': _placement.wire,
      },
      null
    );
  }

  Future<void> _save() async {
    if (_entityText.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال الجهة المستلمة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // 🔴 **المسوّدة تُحفظ قبل أيّ طلب** (ADR-051) — فانقطاعٌ بعد إنشاء الجهة لا يُضيع الكتاب.
    final drafts = _drafts;
    final draft = await drafts?.flush(force: true);
    try {
      final api = ref.read(apiClientProvider);
      if (_entityId == null) {
        final e = await api.createEntity(_entityText.trim(), 'Both', idempotencyKey: draft?.idempotencyKey('entity'));
        _entityId = e.entityId;
        await drafts?.recordProgress(entityId: e.entityId);
      }
      final (payload, _) = _payload(report: true);
      if (payload == null) return;
      switch (widget.mode) {
        case OutgoingEditorMode.create:
          await api.createOutgoing(payload, idempotencyKey: draft?.idempotencyKey('outgoing'));
          await drafts?.discard();
        case OutgoingEditorMode.editDraft:
          await api.updateOutgoing(widget.book!.outgoingId, payload);
        case OutgoingEditorMode.editApproved:
          await api.editApproved(widget.book!.outgoingId, {
            ...payload,
            'rowVersion': widget.book!.rowVersion,
            'changeNote': _note.text.trim().isEmpty ? null : _note.text.trim(),
          });
      }
      invalidateOutgoing(ref);
      _drafts?.dispose();
      _drafts = null;
      if (mounted) Navigator.of(context).pop(true);   // ⚠️ `pop` يتخطّى PopScope عمداً — حُفظ فلا سؤال
    } on ApiException catch (e) {
      if (_isCreate && isDeferrableFailure(e) && drafts != null) {
        await drafts.markFailed(deferralReason(e));
        if (mounted) {
          setState(() => _error = '${deferralReason(e)} — حُفظ في «مسوّداتي».');
          showDeferredSnack(context, deferralReason(e));
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── المغادرة ───────────────────────────

  Future<void> _onPop() async {
    if (_isCreate) {
      if (!_hasContent) {
        await _drafts?.discard();
        _drafts?.dispose();
        _drafts = null;
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      final choice = await showDraftExitDialog(context);
      if (!mounted) return;
      switch (choice) {
        case DraftExitChoice.keep:
          await _drafts?.flush(force: true);
        case DraftExitChoice.discard:
          await _drafts?.discard();
        case DraftExitChoice.stay:
          return;
      }
      _drafts?.dispose();
      _drafts = null;
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    // التعديل: جدولٌ طويل لا يضيع بزرّ رجوع (لا مسوّدة محلّية للتعديل — فالسؤال هو الحارس)
    if (!_isDirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تعديلاتٌ لم تُحفظ'),
        content: const Text('غيّرتَ في الكتاب ولم تحفظ. هل تريد تجاهل التعديلات والخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('متابعة التحرير')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تجاهل التعديلات'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  // ─────────────────────────── البناء ───────────────────────────

  String get _title => switch (widget.mode) {
        OutgoingEditorMode.create => widget.draftId == null ? 'إنشاء كتاب صادر جديد' : 'إكمال مسوّدة — كتاب صادر',
        OutgoingEditorMode.editDraft => 'تعديل مسودة',
        OutgoingEditorMode.editApproved => 'تعديل كتاب معتمد (إصدار جديد)',
      };

  String get _saveLabel => switch (widget.mode) {
        OutgoingEditorMode.create => 'حفظ كمسودة نهائية',
        OutgoingEditorMode.editDraft => 'حفظ التعديلات',
        OutgoingEditorMode.editApproved => 'حفظ كإصدار جديد',
      };

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < OutgoingEditorScreen.phoneWidth;
    return PopScope(
      // ⚠️ يعترض كلَّ مغادرة ثم يقرّر (فارغٌ/لم يتغيّر ⟵ يغادر بلا سؤال) — والهاتف لا تحرير فيه فلا اعتراض.
      canPop: phone || (_isCreate && _drafts == null),
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onPop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_title), centerTitle: true),
        body: phone ? const _PhoneNotice() : _body(),
      ),
    );
  }

  Widget _body() => Column(
        children: [
          if (_offer != null)
            DraftRestoreBanner(
              draft: _offer!,
              othersCount: _offerOthers,
              onRestore: _restoreOffered,
              onDismiss: () => setState(() => _offer = null),
            ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_formGen),
              child: FutureBuilder<_Refs>(
                future: _refs,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }
                  if (snap.hasError) {
                    return Center(
                        child: Text('حدث خطأ أثناء تحميل البيانات المرجعية: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
                  }
                  final refs = snap.data!;
                  if (refs.templates.isEmpty || (_isCreate && refs.entities.isEmpty)) {
                    return const Center(
                      child: Text('يلزم وجود جهة واحدة وقالب مُفعّل على الأقل للبدء. أضِفهما من الإعدادات أولاً.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, c) => c.maxWidth < OutgoingEditorScreen.wideWidth ? _narrow(refs) : _wide(refs),
                  );
                },
              ),
            ),
          ),
        ],
      );

  Widget _wide(_Refs refs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الشريط الماليّ فوق الأعمدة كلّها — أوّلُ ما تقع عليه العين (بلاغ المالك 2026-09-21)
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: _financialBar()),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 340,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 20, 24), children: _panel(refs)),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _toolbar(),
                        _paperCaption(),
                        Expanded(
                          child: Container(
                            color: _desk(context),
                            child: SingleChildScrollView(
                              controller: _paperScroll,
                              padding: const EdgeInsets.all(16),
                              child: _paper(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _errorAndSave(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 12, 16), child: _previewPane()),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _narrow(_Refs refs) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: AppColors.action(context),
              indicatorColor: AppColors.gold,
              tabs: [
                const Tab(icon: Icon(Icons.description_rounded), text: 'الورقة'),
                Tab(icon: const Icon(Icons.picture_as_pdf_rounded), text: _previewStale ? 'المعاينة •' : 'المعاينة'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    children: [
                      _financialBar(),
                      const SizedBox(height: 16),
                      ..._panel(refs),
                      const SizedBox(height: 16),
                      _toolbar(),
                      _paperCaption(),
                      Container(color: _desk(context), padding: const EdgeInsets.all(12), child: _paper()),
                      const SizedBox(height: 16),
                      _errorAndSave(),
                    ],
                  ),
                  Padding(padding: const EdgeInsets.all(16), child: _previewPane()),
                ],
              ),
            ),
          ],
        ),
      );

  Color _desk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2D33) : const Color(0xFFE6E8EC);

  Widget _financialBar() => FinancialBar(
        enabled: _showFinancials,
        onEnabledChanged: (v) => _setOption(() => _showFinancials = v),
        amount: _amount,
        rate: _rate,
        currency: _currency,
        onCurrencyChanged: (v) => _setOption(() => _currency = v),
      );

  Widget _toolbar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.all(8),
      // الشريط ينتقل إلى الخلية المفتوحة (تنسيقٌ مختلط داخلها) — وتحته شريط الجدول ما دام جدولٌ نشطاً
      child: ListenableBuilder(
        listenable: _tables,
        builder: (context, _) {
          final cell = _tables.cell;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: quill.QuillSimpleToolbar(
                      key: ObjectKey(cell ?? _quill),
                      controller: cell ?? _quill,
                      config: cell != null ? kQuillCellToolbarConfig : kQuillToolbarConfig,
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    key: const Key('insert-table'),
                    onPressed: _insertTable,
                    icon: const Icon(Icons.table_chart_outlined, size: 16),
                    label: const Text('جدول'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  ),
                ],
              ),
              if (_tables.active) BtTableToolbar(hub: _tables),
            ],
          );
        },
      ),
    );
  }

  Widget _paperCaption() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          'الورقة متّصلة بلا فواصل صفحات — أين تنقسم الصفحات وأين يقع التوقيع والختم تُريه المعاينة.',
          style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor),
        ),
      );

  /// الورقة — والرأس يُعاد رسمه مع الكتابة في حقوله، **ومحرّر المتن لا يُعاد بناؤه** (يُمرَّر ابناً ثابتاً).
  Widget _paper() {
    final editor = quill.QuillEditor(
      controller: _quill,
      focusNode: _editorFocus,
      scrollController: _editorScroll,
      config: quill.QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        placeholder: 'اكتب نصّ الكتاب هنا…',
        embedBuilders: [BtEmbedBuilder(hub: _tables)],
        customStyles: quill.DefaultStyles(
          paragraph: quill.DefaultTextBlockStyle(
            kPaperBase.copyWith(height: 1.6),
            const quill.HorizontalSpacing(0, 0),
            const quill.VerticalSpacing(0, 0),
            const quill.VerticalSpacing(0, 0),
            null,
          ),
          placeHolder: quill.DefaultTextBlockStyle(
            kPaperBase.copyWith(height: 1.6, color: const Color(0xFF9E9E9E)),
            const quill.HorizontalSpacing(0, 0),
            const quill.VerticalSpacing(0, 0),
            const quill.VerticalSpacing(0, 0),
            null,
          ),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([_subject, _headerPhrase, _signatoryName, _signatoryTitle]),
      child: editor,
      builder: (context, child) => BookPaper(
        assets: _assets,
        numberText: widget.book?.number ?? 'يُولَّد عند الاعتماد',
        dateText: DateFormat('yyyy-MM-dd').format(_date),
        headerPhrase: _headerPhrase.text,
        entityLine: _printEntity && _entityText.trim().isNotEmpty ? _entityText.trim() : null,
        subjectLine: _printSubject && _subject.text.trim().isNotEmpty ? _subject.text.trim() : null,
        signatoryName: _signatoryName.text,
        signatoryTitle: _signatoryTitle.text,
        placement: _placement,
        body: child!,
      ),
    );
  }

  Widget _previewPane() => CustomCard(
        padding: EdgeInsets.zero,
        child: PdfPreviewPane(
          bytes: _previewBytes,
          busy: _previewBusy,
          stale: _previewStale,
          error: _previewError,
          onRefresh: () => _refreshPreview(),
        ),
      );

  Widget _errorAndSave() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Container(
              key: const Key('editor-error'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
            ),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _isApproved ? AppColors.warn : AppColors.action(context),
                foregroundColor: _isApproved ? Colors.black : AppColors.onAction(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(_busy ? 'جارٍ الحفظ...' : _saveLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );

  // ─────────────────────────── اللوحة الجانبية ───────────────────────────

  List<Widget> _panel(_Refs refs) => [
        if (_isApproved) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warn.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warn.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warn),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'هذا الكتاب معتمد. الحفظ يُنشئ إصداراً جديداً ويعيد توليد الـPDF والختم — ورقم الكتاب لا يتغيّر.',
                    style: TextStyle(height: 1.5, fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // سبب التعديل — يُكتب في سجلّ الإصدارات وسجلّ الحركة.
          TextField(
            key: const Key('change-note'),
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: _dec('سبب التعديل (اختياري — يظهر في سجلّ الحركة)', Icons.edit_note_rounded),
          ),
          const SizedBox(height: 8),
        ],
        CustomCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(Icons.info_outline_rounded, 'معلومات الكتاب'),
              const SizedBox(height: 14),
              if (refs.types.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  key: const Key('book-type'),
                  isExpanded: true,
                  initialValue: safeDropdownValue(_typeId, refs.types.map((t) => t.outgoingBookTypeId)),
                  decoration: _dec('نوع الكتاب', Icons.category_rounded),
                  items: [
                    for (final t in refs.types)
                      DropdownMenuItem(value: t.outgoingBookTypeId, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => _setOption(() => _typeId = v),
                ),
                const SizedBox(height: 12),
              ],
              _entityInput(refs),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: safeDropdownValue(_templateId, refs.templates.map((t) => t.templateId)),
                decoration: _dec('القالب المعتمد', Icons.style_rounded),
                items: [
                  for (final t in refs.templates) DropdownMenuItem(value: t.templateId, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  _setOption(() => _templateId = v);
                  unawaited(_loadAssets(v));
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) _setOption(() => _date = d);
                },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: _dec('تاريخ الكتاب', Icons.calendar_today_rounded),
                  child: Text(DateFormat('yyyy/MM/dd').format(_date), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _subject, decoration: _dec('موضوع الكتاب', Icons.subject_rounded)),
              const SizedBox(height: 12),
              TextField(controller: _headerPhrase, decoration: _dec('عبارة رأسية اختيارية (إلى، أمر إداري…)', Icons.title_rounded)),
              const SizedBox(height: 12),
              TextField(controller: _signatoryName, decoration: _dec('اسم الموقّع (اختياري)', Icons.person_rounded)),
              const SizedBox(height: 12),
              TextField(controller: _signatoryTitle, decoration: _dec('المنصب (اختياري)', Icons.badge_rounded)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CustomCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(Icons.print_rounded, 'خيارات الطباعة'),
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('print-entity'),
                contentPadding: EdgeInsets.zero,
                title: const Text('طباعة سطر الجهة'),
                subtitle: const Text('الجهة تبقى مسجّلة في النظام دائماً', style: TextStyle(fontSize: 11.5)),
                value: _printEntity,
                onChanged: (v) => _setOption(() => _printEntity = v),
              ),
              SwitchListTile(
                key: const Key('print-subject'),
                contentPadding: EdgeInsets.zero,
                title: const Text('طباعة سطر «الموضوع /»'),
                value: _printSubject,
                onChanged: (v) => _setOption(() => _printSubject = v),
              ),
              SwitchListTile(
                key: const Key('page-numbers'),
                contentPadding: EdgeInsets.zero,
                title: const Text('ترقيم الصفحات'),
                subtitle: const Text('«صفحة 1 من 5» — ولا ترقيم في الكتاب ذي الصفحة الواحدة', style: TextStyle(fontSize: 11.5)),
                value: _pageNumbers,
                onChanged: (v) => _setOption(() => _pageNumbers = v),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<SignaturePlacement>(
                key: const Key('signature-placement'),
                isExpanded: true,
                initialValue: _placement,
                decoration: _dec('التوقيع والختم', Icons.verified_rounded),
                items: [
                  for (final p in SignaturePlacement.values)
                    DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) _setOption(() => _placement = v);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ];

  Widget _entityInput(_Refs refs) => LayoutBuilder(
        builder: (context, constraints) => Autocomplete<EntityModel>(
          displayStringForOption: (e) => e.name,
          optionsBuilder: (v) => v.text.isEmpty
              ? refs.entities
              : refs.entities.where((e) => e.name.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (e) => _setOption(() {
            _entityId = e.entityId;
            _entityText = e.name;
          }),
          fieldViewBuilder: (context, tc, focusNode, onSubmitted) {
            // 🐛 كان المستمع يُضاف **مع كل إعادة بناء** فتتراكم المستمعات — الآن مرّةً لكل متحكّم.
            //    والنصّ الأوّل يُضبط **قبل** المستمع، فلا يُستدعى `setState` أثناء البناء.
            if (!identical(_entityField, tc)) {
              _entityField = tc;
              if (tc.text.isEmpty && _entityText.isNotEmpty) tc.text = _entityText;
              tc.addListener(() => _onEntityTyped(tc.text, refs));
            }
            return TextField(
              key: const Key('entity-field'),
              controller: tc,
              focusNode: focusNode,
              decoration: _dec('الجهة المستلمة (اختر أو اكتب جهة جديدة)', Icons.business_rounded),
            );
          },
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 220),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final o = options.elementAt(i);
                    return ListTile(title: Text(o.name), onTap: () => onSelected(o));
                  },
                ),
              ),
            ),
          ),
        ),
      );

  void _onEntityTyped(String text, _Refs refs) {
    if (text == _entityText || !mounted) return;
    final match = refs.entities.where((e) => e.name == text.trim());
    setState(() {
      _entityText = text;
      _entityId = match.isEmpty ? null : match.first.entityId;
    });
    _changed();
  }

  Widget _heading(IconData icon, String text) => Row(
        children: [
          Icon(icon, color: AppColors.action(context), size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      );

  InputDecoration _dec(String label, IconData icon) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.action(context), width: 1.5)),
    );
  }
}

/// الهاتف للعرض والاعتماد (قرار المالك ت١٣) — لا محرّرَ ضيّقاً لا يُستعمل.
class _PhoneNotice extends StatelessWidget {
  const _PhoneNotice();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.desktop_windows_rounded, size: 56, color: AppColors.action(context)),
              const SizedBox(height: 16),
              const Text('التحرير متاح على الحاسوب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                'كتابة الكتب الصادرة وجداولها تحتاج شاشةً أوسع. من الهاتف تستطيع عرض الكتب واعتمادها.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('phone-back'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('رجوع'),
              ),
            ],
          ),
        ),
      );
}

class _Refs {
  _Refs(this.entities, this.templates, this.types);
  final List<EntityModel> entities;
  final List<TemplateModel> templates;
  final List<OutgoingBookTypeModel> types;
}
