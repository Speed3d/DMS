import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/form_drafts.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/draft_widgets.dart';

/// ملف اختاره المستخدم قبل حفظ الكتاب — يُرفَع بعد الإنشاء (المرفق يحتاج `OwnerId`).
class _PendingFile {
  final String name;
  final Uint8List bytes;
  const _PendingFile(this.name, this.bytes);
  int get sizeKb => (bytes.length / 1024).ceil();
}

/// Hint: شاشة إضافة أو تعديل كتاب وارد
class IncomingFormScreen extends ConsumerStatefulWidget {
  final int? bookId;

  /// فتحُ مسوّدةٍ محفوظة من «مسوّداتي» (ADR-051) — للتسجيل الجديد وحده.
  final String? draftId;

  const IncomingFormScreen({super.key, this.bookId, this.draftId});
  @override
  ConsumerState<IncomingFormScreen> createState() => _IncomingFormScreenState();
}

class _IncomingFormScreenState extends ConsumerState<IncomingFormScreen> {
  final _subject = TextEditingController();
  final _externalNumber = TextEditingController();
  final _keywords = TextEditingController();
  final _notes = TextEditingController();

  /// قيم مالية **قديمة** بلا واجهة.
  ///
  /// Hint: أُلغي كارت التفاصيل المالية من الوارد بقرار المالك (2026-07-25) وأُزيل مصدر «وارد»
  ///       من التقرير المالي، لكن الأعمدة باقية في القاعدة فلا تُتلف بيانات مُدخَلة سابقاً.
  ///       نحمل قيم الكتاب ونُعيد إرسالها كما هي، وإلا مسحها أي تعديل لاحق بصمت —
  ///       وهو نفس عيب «الحمولة الناقصة» الذي أصلحناه في نموذج المستخدم.
  num? _legacyAmount;
  String? _legacyCurrency;
  num? _legacyRate;

  /// ملفات اختيرت قبل الحفظ — تُرفَع بعد إنشاء الكتاب.
  ///
  /// Hint: كان المرفق يتطلّب فتح الكتاب بعد حفظه ثم رفعه من شاشة التفاصيل، وهو ما وصفه
  ///       المالك بـ«خطأ ومزعج». المرفق يحتاج `OwnerId` فعلاً، فنُجمّع هنا ونرفع بعد الإنشاء.
  final List<_PendingFile> _pendingAttachments = [];

  DateTime _receivedDate = DateTime.now();
  TimeOfDay? _receivedTime = TimeOfDay.now();
  DateTime? _externalDate;

  int? _entityId;
  String _entitySearchText = '';
  
  int? _documentTypeId;
  /// Hint: القيمة تُرسل كما هي للباك-إند — يجب أن تبقى دائماً أحد مفاتيح [kReceiveMethods].
  String _receiveMethod = kDefaultReceiveMethod;

  bool _busy = false;
  String? _error;

  late Future<_Refs> _refs;

  // ── حماية ما يُكتب (ADR-051) — للتسجيل الجديد وحده، لا للتعديل ──
  DraftAutosaver? _drafts;
  FormDraft? _offer;
  int _offerOthers = 0;
  int _formGen = 0;

  /// ملفاتٌ كانت في المسوّدة ولم تُحفظ بايتاتُها (فوق 25 ميغابايت) — يُعاد إرفاقُها.
  List<DraftFileMeta> _missingFiles = const [];

  /// الكتاب سُجّل فعلاً في محاولةٍ سابقة وبقيت مرفقاتٌ لم تُرفع — فلا يُسجَّل ثانيةً.
  int? _createdIncomingId;

  @override
  void initState() {
    super.initState();
    if (widget.bookId == null) _drafts = _createAutosaver();
    _refs = _loadRefs();
  }

  @override
  void dispose() {
    _drafts?.dispose();
    for (final c in [_subject, _externalNumber, _keywords, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────── المسوّدة (ADR-051) ─────────────

  DraftAutosaver? _createAutosaver() {
    final s = ref.read(sessionProvider);
    final userId = s.auth?.userId;
    final companyId = s.effectiveCompanyId;
    if (userId == null || companyId == null) return null;
    final store = ref.read(formDraftStoreProvider);
    if (widget.draftId == null) {
      final mine = splitByCompany(draftsOf(store.all(), userId), companyId)
          .here
          .where((d) => d.kind == DraftKind.incoming)
          .toList();
      if (mine.isNotEmpty) {
        _offer = mine.first;
        _offerOthers = mine.length - 1;
      }
    }
    return DraftAutosaver(
      store: store,
      kind: DraftKind.incoming,
      userId: userId,
      companyId: companyId,
      id: widget.draftId,
      capture: _captureDraft,
    )..start();
  }

  bool get _hasContent =>
      _subject.text.trim().isNotEmpty ||
      _entitySearchText.trim().isNotEmpty ||
      _externalNumber.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _pendingAttachments.isNotEmpty;

  DraftSnapshot? _captureDraft() {
    if (!_hasContent && _createdIncomingId == null) return null;
    return DraftSnapshot(
      title: _subject.text.trim(),
      fields: {
        'entityId': _entityId,
        'entityText': _entitySearchText,
        'subject': _subject.text,
        'externalNumber': _externalNumber.text,
        'externalDate': _externalDate?.toIso8601String(),
        'receivedDate': _receivedDate.toIso8601String(),
        'receivedTime': _receivedTime == null ? null : '${_receivedTime!.hour}:${_receivedTime!.minute}',
        'documentTypeId': _documentTypeId,
        'receiveMethod': _receiveMethod,
        'keywords': _keywords.text,
        'notes': _notes.text,
      },
      // ⚠️ الملفاتُ بترتيبها — والمخزن يحفظ بايتاتها حتى 25 ميغابايت (قرار المالك).
      files: [for (final f in _pendingAttachments) DraftFileData(f.name, f.bytes)],
    );
  }

  /// يملأ النموذج من مسوّدة — **بلا `setState`** (المنادي يقرّر).
  Future<void> _applyDraft(FormDraft d, _Refs refs) async {
    final f = d.fields;
    final entityId = (f['entityId'] as num?)?.toInt() ?? d.createdEntityId;
    _entityId = refs.entities.any((e) => e.entityId == entityId) ? entityId : null;
    _entitySearchText = f['entityText'] as String? ?? '';
    _subject.text = f['subject'] as String? ?? '';
    _externalNumber.text = f['externalNumber'] as String? ?? '';
    _externalDate = DateTime.tryParse(f['externalDate'] as String? ?? '');
    _receivedDate = DateTime.tryParse(f['receivedDate'] as String? ?? '') ?? _receivedDate;
    final t = (f['receivedTime'] as String?)?.split(':');
    _receivedTime = t == null || t.length < 2
        ? null
        : TimeOfDay(hour: int.tryParse(t[0]) ?? 0, minute: int.tryParse(t[1]) ?? 0);
    // ⚠️ نوعٌ حُذف منذ الحفظ ⇒ «غير محدد» لا منسدلةٌ تسقط (درس `safeDropdownValue`).
    _documentTypeId = safeDropdownValue((f['documentTypeId'] as num?)?.toInt(),
        refs.docTypes.map((x) => x.documentTypeId));
    final method = f['receiveMethod'] as String?;
    _receiveMethod = kReceiveMethods.containsKey(method) ? method! : kDefaultReceiveMethod;
    _keywords.text = f['keywords'] as String? ?? '';
    _notes.text = f['notes'] as String? ?? '';

    final files = await ref.read(formDraftStoreProvider).loadFiles(d);
    _pendingAttachments
      ..clear()
      ..addAll([for (final x in files) _PendingFile(x.name, x.bytes)]);
    _missingFiles = d.missingFiles;
    _createdIncomingId = d.createdRecordId;
    _drafts?.adopt(d);
  }

  Future<void> _restoreOffered() async {
    final d = _offer;
    if (d == null) return;
    final refs = await _refs;
    await _drafts?.discard();
    await _applyDraft(d, refs);
    if (!mounted) return;
    setState(() {
      _offer = null;
      _formGen++;
    });
  }

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

  Future<_Refs> _loadRefs() async {
    final api = ref.read(apiClientProvider);
    try {
      final entities = await api.entities();
      final docTypes = await api.documentTypes();
      
      if (widget.bookId != null) {
        final d = await api.incomingGet(widget.bookId!);
        _subject.text = d.subject;
        _externalNumber.text = d.externalNumber ?? '';
        _keywords.text = d.keywords ?? '';
        _notes.text = d.notes ?? '';
        _receivedDate = d.receivedDate;
        
        if (d.receivedTime != null) {
          final parts = d.receivedTime!.split(':');
          if (parts.length >= 2) {
            _receivedTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
          }
        } else {
          _receivedTime = null;
        }

        _externalDate = d.externalDate;
        _entityId = d.entityId;
        _entitySearchText = d.entityName;
        _documentTypeId = d.documentTypeId;
        // Hint: حماية من قيمة غير معروفة (بيانات قديمة) — الـ Dropdown يتطلب قيمة ضمن عناصره وإلا تحطّمت الشاشة.
        _receiveMethod = kReceiveMethods.containsKey(d.receiveMethod) ? d.receiveMethod : kDefaultReceiveMethod;
        
        // تُحمَل لتُعاد كما هي (لا واجهة لها) — انظر تعليق الحقول أعلاه.
        _legacyAmount = d.amount;
        _legacyCurrency = d.currency;
        _legacyRate = d.exchangeRate;
      }

      final refs = _Refs(entities, docTypes);
      // فُتحت من «مسوّداتي» ⇒ تُملأ قبل البناء الأوّل.
      final opened = widget.draftId == null ? null : ref.read(formDraftStoreProvider).get(widget.draftId!);
      if (opened != null) await _applyDraft(opened, refs);
      return refs;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic>? _buildPayload() {
    if (_entityId == null) {
      setState(() => _error = 'يرجى تحديد الجهة المرسلة (مصدر الكتاب).');
      return null;
    }
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'موضوع الكتاب مطلوب.');
      return null;
    }
    
    String? timeStr;
    if (_receivedTime != null) {
      final h = _receivedTime!.hour.toString().padLeft(2, '0');
      final m = _receivedTime!.minute.toString().padLeft(2, '0');
      timeStr = '$h:$m:00';
    }

    return {
      'receivedDate': _receivedDate.toIso8601String(),
      'receivedTime': timeStr,
      'externalNumber': _externalNumber.text.trim().isEmpty ? null : _externalNumber.text.trim(),
      'externalDate': _externalDate?.toIso8601String(),
      'entityId': _entityId,
      'documentTypeId': _documentTypeId,
      'receiveMethod': _receiveMethod,
      'subject': _subject.text.trim(),
      // أُلغي `folderName` مع تعدّد الأقسام (ADR-018) — الوجهة صارت إسناداً حقيقياً لقسم.
      'keywords': _keywords.text.trim().isEmpty ? null : _keywords.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      // تُعاد كما وردت — لا واجهة لها بعد إلغاء الكارت، وإسقاطها يمسح مبالغ الكتب القديمة.
      'amount': _legacyAmount,
      'currency': _legacyAmount == null ? null : _legacyCurrency,
      'exchangeRate': _legacyRate,
    };
  }

  static const _kMaxAttachmentMb = 50; // مرآة لحدّ AttachmentService في الباك-إند

  Future<void> _pickAttachments() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx', 'zip', 'dwg'],
      withData: true,
      allowMultiple: true,
    );
    if (res == null) return;

    final tooBig = <String>[];
    setState(() {
      for (final f in res.files) {
        if (f.bytes == null) continue;
        if (f.bytes!.length > _kMaxAttachmentMb * 1024 * 1024) {
          tooBig.add(f.name);
          continue;
        }
        _pendingAttachments.add(_PendingFile(f.name, f.bytes!));
      }
    });
    // نرفض المتجاوز **هنا** بدل انتظار رفض الخادم بعد الحفظ، حتى لا يُسجَّل الكتاب
    // ثم يُفاجأ المستخدم بفشل المرفق.
    if (tooBig.isNotEmpty && mounted) {
      setState(() => _error = 'تجاوز الحد ($_kMaxAttachmentMb م.ب): ${tooBig.join('، ')}');
    }
  }

  Future<void> _save() async {
    if (_entitySearchText.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال الجهة المرسلة.');
      return;
    }

    setState(() { _busy = true; _error = null; });

    // 🔴 **المسوّدة تُحفظ قبل أيّ طلب** (ADR-051) — بملفاتها.
    final drafts = _drafts;
    final draft = await drafts?.flush(force: true);

    try {
      final api = ref.read(apiClientProvider);
      if (_entityId == null && _createdIncomingId == null) {
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

      if (widget.bookId == null) {
        // ⚠️ **سُجّل في محاولةٍ سابقة؟** فلا يُسجَّل ثانيةً — تُكمَل مرفقاتُه وحدها.
        final incomingId = _createdIncomingId ??
            (await api.createIncoming(payload, idempotencyKey: draft?.idempotencyKey('incoming'))).incomingId;
        if (_createdIncomingId == null) {
          _createdIncomingId = incomingId;
          await drafts?.recordProgress(recordId: incomingId);
        }
        // المرفق يحتاج كتاباً محفوظاً (OwnerId)، فتُجمَّع الملفات في النموذج وتُرفَع بعد
        // الإنشاء. فشلُ رفع مرفق **لا يُبطل تسجيل الكتاب** — الكتاب سجل رسمي منذ لحظته،
        // والمرفق مُلحق به؛ نُبلّغ المستخدم ليعيد الرفع من شاشة التفاصيل.
        // 🔴 **وكلُّ ملفٍّ يُرفع يخرج من المسوّدة فوراً** — فانقطاعٌ بعد الثاني من خمسة لا يُكرّر
        //    الأوّلين عند الإكمال (لا مفتاحَ لمنع تكرار المرفقات، فالترتيبُ هو الحارس).
        final failed = <String>[];
        for (final f in List.of(_pendingAttachments)) {
          try {
            await api.uploadIncomingAttachment(incomingId, f.bytes, f.name);
            _pendingAttachments.remove(f);
            await drafts?.flush(force: true);
          } on ApiException catch (e) {
            if (isDeferrableFailure(e)) rethrow;   // الخادم غاب ⇒ تبقى البقيّة للإكمال
            failed.add(f.name);
          }
        }
        await drafts?.discard();
        if (mounted && failed.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('سُجّل الكتاب، لكن تعذّر رفع: ${failed.join('، ')}. أعِد رفعها من شاشة التفاصيل.'),
            duration: const Duration(seconds: 6),
          ));
        }
      } else {
        await api.updateIncoming(widget.bookId!, payload);
      }

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (isDeferrableFailure(e) && drafts != null) {
        final reason = _createdIncomingId == null
            ? deferralReason(e)
            : '${deferralReason(e)} — سُجّل الكتاب وبقيت ${_pendingAttachments.length} مرفقات لم تُرفع';
        await drafts.markFailed(reason);
        if (mounted) {
          setState(() => _error = '$reason — حُفظ في «مسوّداتي».');
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
    // ⚠️ **يعترض كلَّ مغادرة** في التسجيل الجديد (انظر نظيره في نموذج الصادر).
    return PopScope(
      canPop: _drafts == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_hasContent && _createdIncomingId == null) {
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
        title: Text(widget.bookId != null
            ? 'تعديل الكتاب الوارد'
            : widget.draftId != null
                ? 'إكمال مسوّدة — كتاب وارد'
                : 'تسجيل كتاب وارد جديد'),
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
            return Center(child: Text('حدث خطأ أثناء تحميل البيانات: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final refs = snap.data!;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // ⚠️ سُجّل في محاولةٍ سابقة ⇒ يُقال صراحةً إن الحقول لن تُرسَل ثانيةً.
                  if (_createdIncomingId != null)
                    Container(
                      key: const Key('incoming-already-created'),
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.success),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'سُجّل هذا الكتاب في النظام من قبل — بقي رفع المرفقات أدناه وحدها. '
                              'تعديلُ الحقول هنا لا يُرسَل؛ عدّله من شاشة تفاصيل الكتاب.',
                              style: TextStyle(fontWeight: FontWeight.bold, height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),

                  CustomCard(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('البيانات الأساسية للوارد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Divider(height: 32),
                        
                        // الجهة
                        Autocomplete<EntityModel>(
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
                            if (_entityId != null && textEditingController.text.isEmpty) {
                              final selectedE = refs.entities.cast<EntityModel?>().firstWhere((e) => e?.entityId == _entityId, orElse: () => null);
                              if (selectedE != null) textEditingController.text = selectedE.name;
                            }
                            // ومسوّدةٌ بجهةٍ جديدة لم تُنشأ بعد ⇒ يُستعاد نصُّها (ADR-051).
                            if (_entityId == null && textEditingController.text.isEmpty && _entitySearchText.isNotEmpty) {
                              textEditingController.text = _entitySearchText;
                            }
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: _inputDecoration('الجهة المُرسلة (المصدر)', Icons.business_rounded),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // الموضوع
                        TextField(
                          controller: _subject,
                          decoration: _inputDecoration('موضوع الكتاب', Icons.subject_rounded),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context, initialDate: _receivedDate,
                                    firstDate: DateTime(2000), lastDate: DateTime(2100),
                                  );
                                  if (d != null) setState(() => _receivedDate = d);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('تاريخ الاستلام', Icons.calendar_month_rounded),
                                  child: Text(DateFormat('yyyy/MM/dd').format(_receivedDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _receivedTime ?? TimeOfDay.now(),
                                  );
                                  setState(() => _receivedTime = t);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('وقت الاستلام', Icons.access_time_rounded),
                                  child: Text(_receivedTime?.format(context) ?? 'غير محدد', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _externalNumber,
                                decoration: _inputDecoration('رقم الكتاب الخارجي', Icons.tag_rounded),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context, initialDate: _externalDate ?? DateTime.now(),
                                    firstDate: DateTime(2000), lastDate: DateTime(2100),
                                  );
                                  if (d != null) setState(() => _externalDate = d);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration('تاريخ الكتاب الخارجي', Icons.event_note_rounded),
                                  child: Text(_externalDate == null ? 'غير محدد' : DateFormat('yyyy/MM/dd').format(_externalDate!), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _receiveMethod,
                                decoration: _inputDecoration('طريقة الاستلام', Icons.inbox_rounded),
                                // Hint: تُبنى من الثوابت المشتركة لضمان تطابقها مع الباك-إند
                                items: kReceiveMethods.entries
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: (v) => setState(() => _receiveMethod = v!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                isExpanded: true,
                                initialValue: _documentTypeId,
                                decoration: _inputDecoration('نوع المستند (اختياري)', Icons.category_rounded),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('غير محدد')),
                                  ...refs.docTypes.map((t) => DropdownMenuItem(value: t.documentTypeId, child: Text(t.name))),
                                ],
                                onChanged: (v) => setState(() => _documentTypeId = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Hint: القسم لم يعُد يُكتب هنا — يُسنَد بإجراء «إحالة لقسم» من شاشة التفاصيل،
                        //       فتظهر الكتب المُحالة تلقائياً لموظفي القسم.
                        TextField(
                          controller: _keywords,
                          decoration: _inputDecoration('الكلمات المفتاحية (مفصولة بفاصلة)', Icons.key_rounded),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _notes,
                          maxLines: 2,
                          decoration: _inputDecoration('ملاحظات إضافية', Icons.note_rounded),
                        ),
                      ],
                    ),
                  ),

                  // المرفقات — عند التسجيل الأول فقط. في التعديل تُدار من شاشة التفاصيل
                  // (حيث تُعرض المرفقات الموجودة وتُحذف).
                  if (widget.bookId == null) ...[
                    const SizedBox(height: 24),
                    _attachmentsCard(),
                  ],

                  const SizedBox(height: 32),

                  SizedBox(
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
                        _busy
                            ? 'جارٍ الحفظ...'
                            : _createdIncomingId != null
                                ? 'رفع المرفقات المتبقية'
                                : 'حفظ الكتاب الوارد',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
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

  Widget _attachmentsCard() {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_rounded, color: AppColors.action(context)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('المرفقات (اختياري)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _pickAttachments,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة ملفات'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ⚠️ ملفاتٌ تجاوزت حدّ المسوّدة (25 ميغابايت) — حُفظ اسمُها فقط، فيُطلب إرفاقُها ثانيةً.
          if (_missingFiles.isNotEmpty)
            Container(
              key: const Key('incoming-missing-files'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'أعِد إرفاق هذه الملفات — كانت أكبر من أن تُحفظ مع المسوّدة: '
                '${_missingFiles.map((f) => f.name).join('، ')}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          if (_pendingAttachments.isEmpty)
            const Text(
              'اختر صور الكتاب الممسوحة أو ملفاته الآن — تُرفَع تلقائياً بعد الحفظ.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            ..._pendingAttachments.map((f) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconFor(f.name), color: AppColors.action(context)),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${f.sizeKb} ك.ب', style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                    tooltip: 'إزالة',
                    onPressed: _busy ? null : () => setState(() => _pendingAttachments.remove(f)),
                  ),
                )),
        ],
      ),
    );
  }

  IconData _iconFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'jpg' || 'jpeg' || 'png' => Icons.image_rounded,
      'docx' => Icons.description_rounded,
      'xlsx' => Icons.table_chart_rounded,
      'zip' => Icons.folder_zip_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
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
  final List<DocumentTypeModel> docTypes;
  _Refs(this.entities, this.docTypes);
}
