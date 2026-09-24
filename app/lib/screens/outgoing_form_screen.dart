import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../core/api_client.dart';
import '../core/quill_html.dart';
import '../core/quill_toolbar.dart';
import '../widgets/financial_bar.dart';
import '../core/session.dart';
import '../core/outgoing_providers.dart';
import '../core/company_providers.dart';
import '../core/form_drafts.dart';
import '../core/local_storage.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/draft_widgets.dart';
import '../widgets/pdf_preview_pane.dart';

/// Hint: شاشة إضافة كتاب صادر جديد مع محرر النصوص الاحترافي Quill
class OutgoingFormScreen extends ConsumerStatefulWidget {
  /// فتحُ مسوّدةٍ محفوظة من «مسوّداتي» (ADR-051).
  final String? draftId;

  const OutgoingFormScreen({super.key, this.draftId});
  @override
  ConsumerState<OutgoingFormScreen> createState() => _OutgoingFormScreenState();
}

class _OutgoingFormScreenState extends ConsumerState<OutgoingFormScreen> {
  final _subject = TextEditingController();
  final _headerPhrase = TextEditingController();
  final _signatoryName = TextEditingController();
  final _signatoryTitle = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _quillController = quill.QuillController.basic();
  bool _showFinancials = false;
  
  DateTime _date = DateTime.now();
  int? _entityId;
  String _entitySearchText = '';
  int? _templateId;
  String? _currency;
  bool _busy = false;
  String? _error;

  // ── المعاينة الجانبية (البند 5) ──
  // Hint: التحديث **عند الطلب** لا مع كل حرف. قياسٌ فعلي: توليد معاينة واحدة ~1.5 ثانية
  // في السيرفر (QuestPDF + خطوط مضمّنة + صور القالب)، فالتحديث التلقائي المستمر كان
  // سيُثقل السيرفر الداخلي (ADR-016) ويُبطئ الكتابة. يبقى الترقية لاحقاً خياراً مفتوحاً.
  Uint8List? _previewBytes;
  bool _previewBusy = false;
  /// المعاينة المعروضة لم تعد تطابق المدخلات — نُعلم المستخدم بدل أن يظنّها محدَّثة.
  bool _previewStale = false;
  String? _previewError;

  late Future<_Refs> _refs;

  // ── حماية ما يُكتب (ADR-051) ──
  /// `null` ⇒ لا مستخدمَ أو لا شركةَ فعّالة (سوبر أدمن بلا شركة) — فلا حفظ.
  DraftAutosaver? _drafts;

  /// مسوّدةٌ سابقة تُعرض للاستعادة أعلى النموذج الجديد.
  FormDraft? _offer;
  int _offerOthers = 0;

  /// يُزاد عند الاستعادة فيُعاد بناء ما يقرأ قيمته أوّل مرّة فقط (`Autocomplete` · المنسدلات).
  int _formGen = 0;

  @override
  void initState() {
    super.initState();
    _drafts = _createAutosaver();
    _refs = _loadRefs();
    // Hint: الربط من مكان واحد بدل `onChanged` موزَّع على كل حقل — أي حقل جديد يُضاف هنا
    // فقط، ولا يُنسى فيبقى المستخدم أمام معاينة قديمة يظنّها محدَّثة.
    for (final c in _previewAffectingControllers) {
      c.addListener(_markPreviewStale);
    }
    _quillController.addListener(_markPreviewStale);
  }

  /// الحقول التي يظهر أثرها في الـPDF.
  List<TextEditingController> get _previewAffectingControllers =>
      [_subject, _headerPhrase, _signatoryName, _signatoryTitle, _amount, _rate];

  @override
  void dispose() {
    // Hint: لم تكن الشاشة تُحرّر متحكّماتها أصلاً؛ صار ذلك ألزم بعد إضافة المستمعين
    // (تحرير المتحكّم يُزيل مستمعيه تلقائياً).
    _drafts?.dispose();
    for (final c in [_subject, _headerPhrase, _signatoryName, _signatoryTitle, _amount, _rate]) {
      c.dispose();
    }
    _quillController.dispose();
    super.dispose();
  }

  // ───────────── المسوّدة (ADR-051) ─────────────

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
      final mine = splitByCompany(draftsOf(store.all(), userId), companyId)
          .here
          .where((d) => d.kind == DraftKind.outgoing)
          .toList();
      if (mine.isNotEmpty) {
        _offer = mine.first;
        _offerOthers = mine.length - 1;
      }
    }
    return saver..start();
  }

  /// ما يستحقّ الحفظ — **والتوقيع الافتراضيّ ليس «كتابة»** (يُملأ من الشركة تلقائياً).
  bool get _hasContent =>
      _subject.text.trim().isNotEmpty ||
      !_quillController.document.isEmpty() ||
      _entitySearchText.trim().isNotEmpty ||
      _amount.text.trim().isNotEmpty;

  DraftSnapshot? _captureDraft() {
    if (!_hasContent) return null;
    return DraftSnapshot(
      title: _subject.text.trim(),
      fields: {
        'entityId': _entityId,
        'entityText': _entitySearchText,
        'templateId': _templateId,
        'date': _date.toIso8601String(),
        'subject': _subject.text,
        'headerPhrase': _headerPhrase.text,
        'signatoryName': _signatoryName.text,
        'signatoryTitle': _signatoryTitle.text,
        'body': _quillController.document.toDelta().toJson(),
        'showFinancials': _showFinancials,
        'amount': _amount.text,
        'rate': _rate.text,
        'currency': _currency,
      },
    );
  }

  /// يملأ النموذج من مسوّدة. ⚠️ لا `setState` هنا — المنادي يقرّر (قبل البناء الأوّل أو بعده).
  void _applyDraft(FormDraft d, {List<EntityModel> entities = const []}) {
    final f = d.fields;
    final entityId = (f['entityId'] as num?)?.toInt() ?? d.createdEntityId;
    // ⚠️ جهةٌ حُذفت منذ الحفظ ⇒ يُبقى نصُّها فتُنشأ من جديد، لا معرّفٌ يرفضه الخادم.
    _entityId = entities.isEmpty || entities.any((e) => e.entityId == entityId) ? entityId : null;
    _entitySearchText = f['entityText'] as String? ?? '';
    _templateId = (f['templateId'] as num?)?.toInt();
    _date = DateTime.tryParse(f['date'] as String? ?? '') ?? _date;
    _subject.text = f['subject'] as String? ?? '';
    _headerPhrase.text = f['headerPhrase'] as String? ?? '';
    _signatoryName.text = f['signatoryName'] as String? ?? '';
    _signatoryTitle.text = f['signatoryTitle'] as String? ?? '';
    final body = f['body'];
    if (body is List && body.isNotEmpty) {
      _quillController.document = quill.Document.fromJson(body);
    }
    _showFinancials = f['showFinancials'] == true;
    _amount.text = f['amount'] as String? ?? '';
    _rate.text = f['rate'] as String? ?? '';
    _currency = f['currency'] as String?;
    _drafts?.adopt(d);
  }

  Future<void> _restoreOffered() async {
    final d = _offer;
    if (d == null) return;
    final refs = await _refs;
    if (!mounted) return;
    // المسوّدة الجديدة الفارغة لهذا النموذج لا تبقى — نكمل على المستعادة.
    await _drafts?.discard();
    setState(() {
      _applyDraft(d, entities: refs.entities);
      _offer = null;
      _formGen++;
    });
  }

  /// مغادرةٌ بما لم يُرسَل ⇒ احفظ · تجاهل · تابع.
  Future<void> _onPopBlocked() async {
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
  }

  /// تُستدعى من كل حقل يؤثّر في الناتج.
  void _markPreviewStale() {
    if (_previewBytes == null || _previewStale) return;
    setState(() => _previewStale = true);
  }

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(localStorageProvider);
    final session = ref.read(sessionProvider);
    try {
      final entities = await api.entities();
      final templates = await api.templates();
      Company? activeCompany;
      if (session.activeCompanyId != null) {
        final companies = await api.companies();
        activeCompany = companies.cast<Company?>().firstWhere((c) => c?.companyId == session.activeCompanyId, orElse: () => null);
      }
      final refs = _Refs(entities, templates.where((t) => t.isActive).toList(), activeCompany);
      
      // Auto-fill signatory defaults if empty
      if (activeCompany != null) {
        if (_signatoryName.text.isEmpty && activeCompany.defaultSignatoryName != null) {
          _signatoryName.text = activeCompany.defaultSignatoryName!;
        }
        if (_signatoryTitle.text.isEmpty && activeCompany.defaultSignatoryTitle != null) {
          _signatoryTitle.text = activeCompany.defaultSignatoryTitle!;
        }
      }
      
      await storage.cacheEntities(entities);
      await storage.cacheTemplates(templates);

      // فُتحت من «مسوّداتي» ⇒ تُملأ قبل البناء الأوّل (فلا حاجة لإعادة بناء المنسدلات).
      final opened = widget.draftId == null ? null : ref.read(formDraftStoreProvider).get(widget.draftId!);
      if (opened != null) _applyDraft(opened, entities: entities);
      return refs;
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        final cachedEntities = storage.getCachedEntities();
        final cachedTemplates = storage.getCachedTemplates();
        if (cachedEntities.isNotEmpty && cachedTemplates.isNotEmpty) {
          final opened = widget.draftId == null ? null : ref.read(formDraftStoreProvider).get(widget.draftId!);
          if (opened != null) _applyDraft(opened, entities: cachedEntities);
          return _Refs(cachedEntities, cachedTemplates.where((t) => t.isActive).toList(), null);
        }
      }
      rethrow;
    }
  }

  String _getHtmlFromBody() => quillDeltaToHtml(_quillController.document.toDelta().toJson());

  Map<String, dynamic>? _buildPayload() {
    if (_entityId == null) {
      setState(() => _error = 'يرجى تحديد الجهة المقصودة أولاً.');
      return null;
    }
    if (_templateId == null) {
      setState(() => _error = 'يرجى اختيار القالب.');
      return null;
    }
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'موضوع الكتاب مطلوب.');
      return null;
    }
    if (_quillController.document.isEmpty()) {
      setState(() => _error = 'نص الكتاب لا يمكن أن يكون فارغاً.');
      return null;
    }
    
    num? amount;
    num? rate;
    if (_amount.text.trim().isNotEmpty) {
      amount = num.tryParse(_amount.text.trim());
      if (amount == null) { setState(() => _error = 'صيغة المبلغ غير صالحة.'); return null; }
      if (_currency == null) { setState(() => _error = 'يرجى اختيار العملة.'); return null; }
      if (_currency == 'USD') {
        rate = num.tryParse(_rate.text.trim());
        if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف إلزامي عند اختيار الدولار.'); return null; }
      }
    }

    return {
      'entityId': _entityId,
      'templateId': _templateId,
      'date': _date.toIso8601String(),
      'headerPhrase': _headerPhrase.text.trim().isEmpty ? null : _headerPhrase.text.trim(),
      'signatoryName': _signatoryName.text.trim().isEmpty ? null : _signatoryName.text.trim(),
      'signatoryTitle': _signatoryTitle.text.trim().isEmpty ? null : _signatoryTitle.text.trim(),
      'subject': _subject.text.trim(),
      'bodyHtml': _getHtmlFromBody(),
      // Delta JSON — مصدر التحرير لاستعادة التنسيق بدقة عند التعديل لاحقاً.
      'bodyJson': jsonEncode(_quillController.document.toDelta().toJson()),
      'amount': amount,
      'currency': amount == null ? null : _currency,
      'exchangeRate': rate,
    };
  }

  /// يولّد المعاينة في السيرفر ويعرضها في اللوحة الجانبية.
  ///
  /// Hint: تُستدعى **عند الطلب** (زر التحديث) وعند التغييرات البنيوية النادرة (القالب)،
  /// لا مع كل حرف — التوليد ~1.5 ثانية فعلياً.
  Future<void> _refreshPreview() async {
    if (_entitySearchText.trim().isEmpty) {
      setState(() => _previewError = 'أدخل الجهة المستلمة أولاً لتظهر المعاينة.');
      return;
    }

    setState(() { _previewBusy = true; _previewError = null; });

    try {
      if (_entityId == null) {
        final newE = await ref.read(apiClientProvider).createEntity(_entitySearchText.trim(), 'Both');
        _entityId = newE.entityId;
      }

      final payload = _buildPayload();
      if (payload == null) {
        setState(() => _previewBusy = false);
        return;
      }

      final bytes = await ref.read(apiClientProvider).previewOutgoing(payload);
      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _previewStale = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _previewError = e.message);
    } finally {
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  /// لوحة المعاينة — ويدجت مشترك بين شاشات الصادر الثلاث.
  Widget _previewPane() => CustomCard(
        padding: EdgeInsets.zero,
        child: PdfPreviewPane(
          bytes: _previewBytes,
          busy: _previewBusy,
          stale: _previewStale,
          error: _previewError,
          onRefresh: _refreshPreview,
        ),
      );

  Future<void> _save() async {
    if (_entitySearchText.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال الجهة المستلمة.');
      return;
    }

    setState(() { _busy = true; _error = null; });

    // 🔴 **المسوّدة تُحفظ قبل أيّ طلب** (ADR-051) — كان الحفظ يقع بعد بناء الحمولة، وبناؤها
    //    بعد إنشاء الجهة، فجهةٌ جديدة مع انقطاعٍ كانت تُضيع الكتاب كلَّه.
    final drafts = _drafts;
    final draft = await drafts?.flush(force: true);

    try {
      final api = ref.read(apiClientProvider);
      if (_entityId == null) {
        // ⚠️ بمفتاح المسوّدة: انقطاعٌ بعد إنشاء الجهة ثم إعادةُ الإرسال يعيد الجهة نفسها.
        final newE = await api.createEntity(_entitySearchText.trim(), 'Both',
            idempotencyKey: draft?.idempotencyKey('entity'));
        _entityId = newE.entityId;
        await drafts?.recordProgress(entityId: newE.entityId);
      }

      final payload = _buildPayload();
      if (payload == null) {
        setState(() => _busy = false);
        return;
      }
      await api.createOutgoing(payload, idempotencyKey: draft?.idempotencyKey('outgoing'));
      await drafts?.discard();
      invalidateOutgoing(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (isDeferrableFailure(e) && drafts != null) {
        // الخادم غائب ⇒ لا يضيع شيء: المسوّدة محفوظةٌ بسببها، ويُنبَّه صاحبها عند العودة.
        await drafts.markFailed(deferralReason(e));
        if (mounted) {
          setState(() => _error = '${deferralReason(e)} — حُفظ في «مسوّداتي».');
          showDeferredSnack(context, deferralReason(e));
        }
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ⚠️ **يعترض كلَّ مغادرة** ثم يقرّر: فارغٌ ⇒ يغادر بلا سؤال · فيه كتابة ⇒ احفظ/تجاهل/تابع.
    //    (`canPop` مبنيٌّ على «فيه كتابة» كان سيتقادم بين إعادتَي بناء فيغادر بلا سؤال.)
    return PopScope(
      canPop: _drafts == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_hasContent) {
          await _drafts?.discard();
          _drafts?.dispose();
          _drafts = null;
          if (context.mounted) Navigator.of(context).pop(false);
          return;
        }
        await _onPopBlocked();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.draftId == null ? 'إنشاء كتاب صادر جديد' : 'إكمال مسوّدة — كتاب صادر'),
        centerTitle: true,
      ),
      body: Column(
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
            return Center(child: Text('حدث خطأ أثناء تحميل البيانات المرجعية: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;
          if (refs.entities.isEmpty || refs.templates.isEmpty) {
            return const Center(
              child: Text('يلزم وجود جهة واحدة وقالب مُفعّل على الأقل للبدء. أضِفهما من الإعدادات أولاً.', style: TextStyle(fontWeight: FontWeight.bold)),
            );
          }
          return Center(
            child: ConstrainedBox(
              // اتّسع السقف لثلاثة أعمدة (بيانات · محرر · معاينة) بعد إضافة اللوحة الجانبية.
              constraints: const BoxConstraints(maxWidth: 1700),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // العتبة أعلى من السابق لأن العمود الثالث يحتاج مساحة؛ دونها نتحوّل لتبويبين.
                  final isSmall = constraints.maxWidth < 1200;

                  final rightPanelContent = [
                    CustomCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: AppColors.action(context).withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: Icon(Icons.info_outline_rounded, color: AppColors.action(context)),
                              ),
                              const SizedBox(width: 12),
                              const Flexible(child: Text('معلومات الكتاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            ],
                          ),
                          const Divider(height: 32),
                          
                          // الجهة
                          LayoutBuilder(
                            builder: (context, constraints) => Autocomplete<EntityModel>(
                              displayStringForOption: (e) => e.name,
                              optionsBuilder: (textEditingValue) {
                                if (textEditingValue.text.isEmpty) return refs.entities;
                                return refs.entities.where((e) => e.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                              },
                              onSelected: (e) {
                                _entityId = e.entityId;
                                _entitySearchText = e.name;
                              },
                              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                textEditingController.addListener(() {
                                  _entitySearchText = textEditingController.text;
                                  final matching = refs.entities.where((e) => e.name == textEditingController.text.trim());
                                  if (matching.isNotEmpty) {
                                    _entityId = matching.first.entityId;
                                  } else {
                                    _entityId = null;
                                  }
                                });
                                // Set initial value if an entity is already selected
                                if (_entityId != null && textEditingController.text.isEmpty) {
                                  final selectedE = refs.entities.cast<EntityModel?>().firstWhere((e) => e?.entityId == _entityId, orElse: () => null);
                                  if (selectedE != null) {
                                    textEditingController.text = selectedE.name;
                                  }
                                }
                                // ومسوّدةٌ بجهةٍ جديدة لم تُنشأ بعد ⇒ يُستعاد نصُّها (ADR-051).
                                if (_entityId == null && textEditingController.text.isEmpty && _entitySearchText.isNotEmpty) {
                                  textEditingController.text = _entitySearchText;
                                }
                                return TextField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  decoration: _inputDecoration('الجهة المستلمة (اختر أو اكتب جهة جديدة)', Icons.business_rounded),
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 200),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (BuildContext context, int index) {
                                          final option = options.elementAt(index);
                                          return ListTile(
                                            title: Text(option.name),
                                            onTap: () => onSelected(option),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // القالب
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            // ⚠️ `safeDropdownValue`: قالبٌ في مسوّدةٍ قديمة قد يكون عُطّل منذ حفظها.
                            initialValue: safeDropdownValue(_templateId, refs.templates.map((t) => t.templateId)),
                            decoration: _inputDecoration('القالب المعتمد', Icons.style_rounded),
                            items: refs.templates.map((t) => DropdownMenuItem(value: t.templateId, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(),
                            // القالب تغيير بنيوي نادر وأثره كبير (ترويسة/تذييل/علامة مائية)
                            // ⇒ نُحدّث المعاينة تلقائياً، بخلاف الكتابة في المتن.
                            onChanged: (v) {
                              setState(() => _templateId = v);
                              if (_previewBytes != null) _refreshPreview();
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // التاريخ
                          InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: Theme.of(context).colorScheme.copyWith(
                                        primary: AppColors.action(context),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (d != null) setState(() => _date = d);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: _inputDecoration('تاريخ الكتاب', Icons.calendar_today_rounded),
                              child: Text(DateFormat('yyyy/MM/dd').format(_date), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // الموضوع
                          TextField(
                            controller: _subject,
                            decoration: _inputDecoration('موضوع الكتاب', Icons.subject_rounded),
                          ),
                          const SizedBox(height: 16),

                          // Header Phrase
                          TextField(
                            controller: _headerPhrase,
                            decoration: _inputDecoration('عبارة رأسية اختيارية (إلى، أمر إداري، إلخ)', Icons.title_rounded),
                          ),
                          const SizedBox(height: 16),
                          
                          // Signatory Name
                          TextField(
                            controller: _signatoryName,
                            decoration: _inputDecoration('اسم الموقّع (اختياري)', Icons.person_rounded),
                          ),
                          const SizedBox(height: 16),

                          // Signatory Title
                          TextField(
                            controller: _signatoryTitle,
                            decoration: _inputDecoration('المنصب (اختياري)', Icons.badge_rounded),
                          ),
                        ],
                      ),
                    ),
                    
                  ];

                  // ═══ الشريط الماليّ — **فوق الأعمدة الثلاثة** (بلاغ المالك 2026-09-21) ═══
                  //
                  // 🔴 **كان بطاقةً في أسفل عمود البيانات** فلا تُرى إلا بتمرير، ومَن لا
                  //    يرى الحقل لا يملؤه. والشريط يجعله **أوّل ما تقع عليه العين**.
                  // 🔑 **وودجةٌ واحدة تخدم الشاشات الثلاث** — فلا تتباعد ثلاثُ نسخ.
                  final financialBar = FinancialBar(
                    enabled: _showFinancials,
                    onEnabledChanged: (v) => setState(() => _showFinancials = v),
                    amount: _amount,
                    rate: _rate,
                    currency: _currency,
                    onCurrencyChanged: (v) => setState(() => _currency = v),
                  );

                  final editorSection = CustomCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_document, color: AppColors.action(context)),
                            const SizedBox(width: 12),
                            const Flexible(child: Text('محتوى الكتاب (المحرر)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const Spacer(),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const Divider(height: 24),
                        
                        // Hint: شريط أدوات Quill Editor
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: quill.QuillSimpleToolbar(
                            controller: _quillController,
                            config: kQuillToolbarConfig,
                          ),
                        ),
                        
                        // Hint: مساحة العمل للكتابة
                        if (isSmall)
                          Container(
                            height: 400,
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: theme.dividerColor),
                                right: BorderSide(color: theme.dividerColor),
                                bottom: BorderSide(color: theme.dividerColor),
                              ),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: quill.QuillEditor.basic(
                              controller: _quillController,
                            ),
                          )
                        else
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: theme.dividerColor),
                                  right: BorderSide(color: theme.dividerColor),
                                  bottom: BorderSide(color: theme.dividerColor),
                                ),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: quill.QuillEditor.basic(
                                controller: _quillController,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );

                  // Hint: زر «معاينة» المنفصل أُزيل — المعاينة صارت لوحة دائمة بجانب المحرر
                  // (شاشة عريضة) أو تبويباً (شاشة ضيقة)، بزر تحديث في ترويستها.
                  final actionButtons = Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.action(context),
                              foregroundColor: AppColors.onAction(context),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 8,
                              shadowColor: AppColors.action(context).withValues(alpha: 0.5),
                            ),
                            icon: _busy 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                            label: Text(
                              _busy ? 'جارٍ العمل...' : 'حفظ كمسودة نهائية',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

                  // شاشة ضيقة: تبويبان — قسمةُ العرض هنا تخنق المحرر (قرار المالك).
                  if (isSmall) {
                    return DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            labelColor: AppColors.action(context),
                            indicatorColor: AppColors.gold,
                            tabs: [
                              const Tab(icon: Icon(Icons.edit_rounded), text: 'التحرير'),
                              Tab(
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                // شارة على التبويب تُغني عن فتحه للتحقق.
                                text: _previewStale ? 'المعاينة •' : 'المعاينة',
                              ),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                                  children: [
                                    // ⚠️ **وفي الضيّقة يتصدّر التبويب** — الموضع نفسه بالمعنى:
                                    //    أوّلُ ما يُرى، لا آخرُ ما يُبلَغ بالتمرير.
                                    financialBar,
                                    const SizedBox(height: 20),
                                    ...rightPanelContent,
                                    const SizedBox(height: 24),
                                    editorSection,
                                    const SizedBox(height: 24),
                                    actionButtons,
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _previewPane(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 🔴 **الشريط يمتدّ فوق الأعمدة الثلاثة** لا داخل أحدها.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: financialBar,
                      ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          // القسم الأيمن (البيانات الأساسية)
                          Expanded(
                            flex: 4,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                              children: rightPanelContent,
                            ),
                          ),
                      
                          // القسم الأوسط (المحرر والنص)
                          Expanded(
                            flex: 6,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 24, top: 32, bottom: 32),
                              child: Column(
                                children: [
                                  Expanded(child: editorSection),
                                  const SizedBox(height: 24),
                                  actionButtons,
                                ],
                              ),
                            ),
                          ),

                          // القسم الأيسر: المعاينة **بجانب نص الكتاب** كما طلب المالك.
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 24, top: 32, bottom: 32),
                              child: _previewPane(),
                            ),
                          ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              ),
            ),
          );
        },
      ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
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

class _Refs {
  final List<EntityModel> entities;
  final List<TemplateModel> templates;
  final Company? activeCompany;
  _Refs(this.entities, this.templates, this.activeCompany);
}
