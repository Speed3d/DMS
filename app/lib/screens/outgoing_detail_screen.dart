import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/local_archive.dart';
import '../core/case_file_providers.dart';
import '../core/incoming_providers.dart';
import '../core/outgoing_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/outgoing_movements.dart';
import '../widgets/hidden_replies_note.dart';
import '../widgets/custom_card.dart';
import '../widgets/related_books_card.dart';
import '../widgets/status_pill.dart';
import 'incoming_detail_screen.dart';
import 'case_files_screen.dart';
import 'relate_book_screen.dart';
import 'outgoing_edit_approved_screen.dart';
import 'outgoing_edit_draft_screen.dart';
import 'task_form_screen.dart';

/// إظهار زرّ «تصدير Word» في شاشة تفاصيل الصادر.
///
/// 🔒 **مخفيّ بطلب المالك (2026-07-27)** — الميزة **مكتملة ومختبَرة** (النقطة تُرجِع ملف
/// OpenXML صالحاً، والمتن يُحوَّل من HTML إلى فقرات Word حقيقية بتنسيقها)، وإنما أُخفي
/// المدخل مؤقتاً بانتظار إشارة المالك.
///
/// **للإظهار: اجعل القيمة `true` — لا شيء آخر يلزم.** أُبقيت الشيفرة كاملة عمداً
/// (الدالة `_exportWord` ونقطة الـAPI ومحوّل HTML) حتى لا يُعاد بناؤها.
const bool _showWordExport = false;

/// Hint: شاشة تفاصيل الصادر بتصميم أنيق يعتمد على البطاقات
class OutgoingDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const OutgoingDetailScreen({super.key, required this.id});
  @override
  ConsumerState<OutgoingDetailScreen> createState() => _OutgoingDetailScreenState();
}

class _OutgoingDetailScreenState extends ConsumerState<OutgoingDetailScreen> {
  late Future<OutgoingDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).outgoingGet(widget.id);
    // 📜 السجلّ يتبع الكتاب — كلُّ ما يُعيد تحميله (تعديل · اعتماد · ربط) أضاف حركة (ADR-056).
    ref.invalidate(outgoingMovementsProvider(widget.id));
    setState(() {});
  }

  /// اعتماد الصادر — ويسأل أوّلاً **هل يردّ على كتبٍ واردة؟** (ADR-045).
  ///
  /// 🔴 **المدخل هنا لا في نموذج المسودّة**: الربط يشترط صادراً معتمداً، فلو وُضع الاختيار
  /// في النموذج لَلَزِم حفظُه في مكانٍ ما بانتظار الاعتماد — أو ضاع عند إغلاق الشاشة.
  /// ووضعُه على بوّابة الاعتماد يجعل **لحظة الاختيار هي لحظة التنفيذ**، بلا حالةٍ معلّقة.
  ///
  /// ⚠️ **واختياريّ بالكامل**: المضيّ بلا اختيارٍ يعتمد الكتاب كما كان يفعل دائماً.

  /// «يخصّ كتاباً سابقاً» — يفتح شاشة الاختيار ثم يربط (ADR-045).
  ///
  /// 🔑 **والنظام يقرّر ما يفعل**: يُنشئ معاملةً أو يضمّ إلى قائمة أو **يدمج** — والمستخدم
  /// لا يرى إلا «هذا الكتاب يخصّ ذاك».
  Future<void> _relateToPreviousBook(CaseMemberKind selfKind, int selfId,
      String suggestedTitle, bool hasCase) async {
    final choice = await Navigator.of(context).push<RelateChoice>(MaterialPageRoute(
        builder: (_) => RelateBookScreen(
              selfKind: selfKind,
              selfBookId: selfId,
              suggestedTitle: suggestedTitle,
              hasCaseAlready: hasCase,
            )));
    if (choice == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).caseFileRelate(
            kind: selfKind,
            bookId: selfId,
            otherKind: choice.kind,
            otherBookId: choice.bookId,
            title: choice.title.isEmpty ? null : choice.title,
          );
      invalidateCaseFiles(ref);
      invalidateIncoming(ref);
      invalidateOutgoing(ref);
      _snack('تم الربط — الكتابان الآن في معاملةٍ واحدة.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final picked = await Navigator.of(context).push<List<int>>(MaterialPageRoute(
        builder: (_) => const _ReplyTargetsScreen(), fullscreenDialog: true));
    // `null` = تراجَع عن الاعتماد كلّه؛ والقائمة الفارغة = اعتمِد بلا ربط.
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).approve(widget.id,
          replyToIncomingIds: picked.isEmpty ? null : picked);
      invalidateOutgoing(ref); // تحديث اللوحة/الإشعارات فوراً (يظهر المبلغ المعتمد)

      // نسخة محلية تلقائية على جهاز المستخدم بعد الاعتماد.
      // Hint: نسخة اطلاع لا سجل رسمي — الأصل في السيرفر. فشلها لا يُبطل الاعتماد.
      final saved = await _saveLocalCopyAfterApproval();
      _snack(saved == null
          ? 'تم الاعتماد وتوليد الرقم والـ PDF بنجاح.'
          : 'تم الاعتماد بنجاح. حُفظت نسخة على جهازك:\n$saved');

      _reload();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ينزّل PDF الكتاب المعتمد ويحفظ نسخة محلية. يعيد المسار (سطح المكتب) أو null.
  Future<String?> _saveLocalCopyAfterApproval() async {
    try {
      final api = ref.read(apiClientProvider);
      final detail = await api.outgoingGet(widget.id);
      if (!detail.hasPdf) return null;
      final bytes = await api.outgoingPdf(widget.id);
      // اسم الملف برقم الكتاب الرسمي ليسهل إيجاده لاحقاً.
      final name = '${detail.number ?? 'book-${widget.id}'}.pdf';
      return await saveLocalCopy(bytes, name, 'الصادر');
    } catch (_) {
      return null; // لا نُزعج المستخدم بخطأ في نسخة اختيارية
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).outgoingPdf(widget.id);
      await downloadBytes(bytes, 'book-${widget.id}.pdf', 'application/pdf');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تصدير الكتاب إلى Word — متاح للمسودّة والمعتمد معاً.
  ///
  /// Hint: النقطة `GET /outgoing/{id}/word` كانت موجودة وتعمل منذ Phase 0، لكن **لم تكن
  /// موصولة بأي شاشة** — فبقي معيار القبول «تصدير PDF و Word» مستوفىً في الباك-إند وحده
  /// بينما لا يجد المستخدم زرّاً (الفجوة G7).
  Future<void> _exportWord(OutgoingDetail d) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).outgoingWord(widget.id);
      // اسم الملف برقم الكتاب الرسمي ليسهل إيجاده — وبـ«مسودة» إن لم يُعتمد بعد.
      final name = '${d.number ?? 'مسودة-${widget.id}'}.docx';
      await downloadBytes(bytes, name,
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewDraft() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).previewDraftPdf(widget.id);
      if (!mounted) return;
      _showPdfPreview(bytes, 'معاينة المسودة');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// معاينة PDF داخل البرنامج (لا تنزيل).
  void _showPdfPreview(Uint8List bytes, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: PdfPreview(
            // نسخة جديدة في كل استدعاء — تمرير نفس المخزن يجعله «منفصلاً» بعد أول رسم
            // على الويب (transfer إلى Web Worker) فتفشل الرسمات التالية.
            build: (format) => Uint8List.fromList(bytes),
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName: 'preview-${widget.id}.pdf',
          ),
        ),
      ),
    );
  }

  Future<void> _editApproved(OutgoingDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OutgoingEditApprovedScreen(book: d)));
    if (changed == true) {
      _snack('تم حفظ التعديل وإنشاء إصدار جديد.');
      invalidateOutgoing(ref);
      _reload();
    }
  }

  Future<void> _editDraft(OutgoingDetail d) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OutgoingEditDraftScreen(book: d)));
    if (changed == true) {
      _snack('تم حفظ التعديل.');
      invalidateOutgoing(ref);
      _reload();
    }
  }

  Future<void> _showVersions() async {
    try {
      final versions = await ref.read(apiClientProvider).versions(widget.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: versions.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Text('لا توجد إصدارات سابقة لهذا الكتاب.', style: TextStyle(fontWeight: FontWeight.bold)))
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text('سجل الإصدارات (Versions)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 16),
                    for (final v in versions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.action(context).withValues(alpha: 0.1),
                            foregroundColor: AppColors.action(context),
                            child: Text('V${v.versionNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          title: Text(v.changeNote ?? 'تعديل على محتوى الكتاب', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(v.changedAt.toLocal())),
                        ),
                      ),
                  ],
                ),
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من نقل هذا الكتاب إلى سلة المهملات؟'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteOutgoing(widget.id);
      invalidateOutgoing(ref);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الكتاب الصادر'),
        centerTitle: true,
        actions: [
          // 🔴 **مدخلٌ مُسمّى باسم فعله** (درس ADR-027) — ويغيب لمن لا يملك المهام.
          if (ref.watch(sessionProvider).canSeeTasks)
            IconButton(
              onPressed: () async {
                // ⚠️ **المُرسِل يُلتقط قبل الفجوة غير المتزامنة** — قراءتُه بعدها تستعمل
                //    `context` عبر `await` وهو ما يحذّر منه المحلّل بحقّ.
                final messenger = ScaffoldMessenger.of(context);
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => TaskFormScreen(presetOutgoingId: widget.id)),
                );
                if (created == true) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('أُنشئت المهمة وربطت بهذا الكتاب')),
                  );
                }
              },
              icon: const Icon(Icons.add_task_rounded),
              tooltip: 'إنشاء مهمة من هذا الكتاب',
            ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            tooltip: 'حذف الكتاب',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<OutgoingDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final d = snap.data!;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // Hint: ترويسة الكتاب (الحالة والرقم + الإجراءات).
                  // ⚠️ كانت `Row` واحدة بـ`Spacer`، فحين تكثر الأزرار (معتمد + صلاحية اعتماد +
                  //    تصدير) لا يبقى للصفّ مخرج فيفيض («RenderFlex overflowed by 94 pixels»).
                  //    `Wrap` يُنزل مجموعةَ الأزرار سطراً كاملاً عند الضيق بدل أن تُقتطع.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusPill(status: d.isFinal ? 'Final' : 'Draft'),
                          const SizedBox(width: 16),
                          Text(
                            d.number ?? 'مسودة (بلا رقم حتى الآن)',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, fontFamily: 'Tahoma', letterSpacing: -0.5),
                          ),
                        ],
                      ),
                      // أزرار الإجراءات السريعة — `spacing: 0` لأن `_buildActionButton`
                      // يحمل حشوته الخاصة (right: 12)، فلا نُضاعفها.
                      Wrap(
                        spacing: 0,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                      if (!d.isFinal) ...[
                        _buildActionButton('تعديل المسودة', Icons.edit_document, AppColors.warn, () => _editDraft(d)),
                        _buildActionButton('معاينة القالب', Icons.preview_rounded, AppColors.gold, _previewDraft),
                        // زر الاعتماد يظهر فقط لمن يملك صلاحية اعتماد فعّالة (دور/علَم/تفويض).
                        if (d.canApprove)
                          _buildActionButton('اعتماد وإصدار', Icons.verified_rounded, AppColors.success, _approve, isFilled: true),
                      ],
                      if (d.hasPdf)
                        _buildActionButton('تحميل PDF', Icons.picture_as_pdf_rounded, AppColors.gold, _downloadPdf),
                      // 🔒 مخفيّ بطلب المالك (2026-07-27) — **جاهز ومختبَر**، ينتظر إشارته فقط.
                      // للإظهار: اجعل `_showWordExport = true` أعلى هذا الملف. لا شيء آخر يلزم.
                      if (_showWordExport)
                        // Word متاح للمسودّة والمعتمد معاً — يُولَّد من بيانات الكتاب لا من ملف
                        // مخزَّن، فلا يشترط `hasPdf` (بخلاف زر PDF الذي يقرأ ملفاً مولَّداً عند الاعتماد).
                        _buildActionButton('تصدير Word', Icons.description_rounded, AppColors.action(context),
                            () => _exportWord(d)),
                      if (d.isFinal) ...[
                        _buildActionButton('تعديل كإصدار', Icons.edit_document, AppColors.warn, () => _editApproved(d)),
                        _buildActionButton('سجل الإصدارات', Icons.history_rounded, AppColors.action(context), _showVersions),
                      ]
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Hint: تفاصيل الكتاب موزعة على شكل بطاقات
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // القسم الأيمن (معلومات وصفية)
                      Expanded(
                        flex: 4,
                        child: CustomCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('المعلومات الأساسية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Divider(height: 32),
                              _buildInfoRow('الموضوع', d.subject, Icons.subject_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('تاريخ الكتاب', DateFormat('yyyy/MM/dd').format(d.date), Icons.calendar_month_rounded),
                              const SizedBox(height: 16),
                              _buildInfoRow('الجهة المقصودة', d.entityName, Icons.business_rounded),
                              if (d.signatoryName != null && d.signatoryName!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _buildInfoRow('الموقّع', '${d.signatoryName}${d.signatoryTitle != null && d.signatoryTitle!.isNotEmpty ? ' - ${d.signatoryTitle}' : ''}', Icons.person_rounded),
                              ],
                              
                              if (d.amount != null) ...[
                                const Divider(height: 32),
                                const Text('التفاصيل المالية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                _buildInfoRow('المبلغ الأصلي', '${_fmt(d.amount!)} ${d.currency == 'USD' ? 'دولار' : 'دينار'}', Icons.monetization_on_rounded),
                                if (d.currency == 'USD') ...[
                                  const SizedBox(height: 16),
                                  _buildInfoRow('سعر الصرف', '${d.exchangeRate}', Icons.currency_exchange_rounded),
                                ],
                                const SizedBox(height: 16),
                                _buildInfoRow('المعادل بالدينار', '${_fmt(d.amountInIqd ?? 0)} د.ع', Icons.payments_rounded),
                              ],
                              // ━━━ الكتب المرتبطة (المعاملة) — ADR-045 ━━━
                              RelatedBooksCard(
                                kind: CaseMemberKind.outgoing,
                                bookId: d.outgoingId,
                                canManage: ref.watch(sessionProvider).canManageIncoming,
                                onRelate: () => _relateToPreviousBook(
                                    CaseMemberKind.outgoing, d.outgoingId, d.subject, false),
                                onOpen: (m) => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => m.kind == CaseMemberKind.incoming
                                        ? IncomingDetailScreen(id: m.bookId)
                                        : OutgoingDetailScreen(id: m.bookId))),
                                onOpenCase: (id) => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => CaseFileDetailScreen(id: id))),
                              ),

                              // ━━━ الواردات المردود عليها — **قائمة** منذ ADR-045 ━━━
                              // 🔐 **لا تحمل إلا ما يراه الطالب**: الخادم يبنيها من
                              //    `IncomingService.Query()`، وكان الحقل المفرد يقرأ الجدول
                              //    مباشرةً فيكشف رقم واردٍ محجوبٍ بحدّ القسم.
                              if (d.repliesTo.isNotEmpty || d.hiddenRepliesCount > 0) ...[
                                const Divider(height: 32),
                                Row(children: [
                                  Text(
                                      d.repliesTo.length + d.hiddenRepliesCount == 1
                                          ? 'الارتباط بالوارد'
                                          : 'الواردات المردود عليها',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 16)),
                                  if (d.repliesTo.length > 1) ...[
                                    const SizedBox(width: 8),
                                    Text('(${d.repliesTo.length})',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.action(context))),
                                  ],
                                ]),
                                const SizedBox(height: 16),
                                for (final link in d.repliesTo) ...[
                                  Row(children: [
                                    Icon(Icons.link_rounded,
                                        size: 18, color: AppColors.action(context)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(link.number ?? '#${link.bookId}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700, fontSize: 13.5)),
                                          const SizedBox(height: 2),
                                          Text(link.subject,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color
                                                      ?.withValues(alpha: 0.6))),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'فتح الكتاب الوارد',
                                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                      onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  IncomingDetailScreen(id: link.bookId))),
                                    ),
                                  ]),
                                  if (link != d.repliesTo.last) const SizedBox(height: 10),
                                ],
                                HiddenRepliesNote(count: d.hiddenRepliesCount, outgoing: false),
                              ],

                              if (d.qrContent != null) ...[
                                const Divider(height: 32),
                                const Text('محتوى ختم الـ QR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SelectableText(
                                    d.qrContent!,
                                    style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8), fontFamily: 'Courier'),
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),

                      // القسم الأيسر (محتوى النص)
                      Expanded(
                        flex: 6,
                        child: CustomCard(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.segment_rounded, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
                                  const SizedBox(width: 8),
                                  const Text('نص الكتاب (المحتوى)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              const Divider(height: 32),
                              // TODO: عندما نقوم بدمج flutter_quill سنقوم بعرض المحتوى بشكل أفضل
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: SelectableText(
                                  d.bodyHtml.replaceAll(RegExp(r'<[^>]*>'), ''), // إزالة مؤقتة للـ HTML tags حتى يتم إضافة Quill
                                  style: const TextStyle(fontSize: 15, height: 1.8),
                                ),
                              ),
                              // 📜 **سجلّ الحركة** (ADR-056، طلب المالك) — لكل الأدوار عدا القارئ، كالوارد.
                              if (canViewOutgoingMovements(ref.watch(sessionProvider).auth?.role)) ...[
                                const Divider(height: 48),
                                OutgoingMovementsSection(outgoingId: widget.id),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap, {bool isFilled = false}) {
    if (_busy) return const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: CircularProgressIndicator());
    
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: isFilled
          ? FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
    );
  }

  String _fmt(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

/// شاشة اختيار الكتب الواردة التي يردّ عليها هذا الصادر — قبل الاعتماد (ADR-045).
///
/// 🔴 **شاشةٌ لا حوار** — قاعدةُ مشروعٍ مستقرّة: حقول البحث داخل `showDialog` تسبّب خلل
/// `disposed EngineFlutterView` على الويب.
///
/// ⚠️ **واختيارٌ متعدّد** على نمط شاشة الإحالة (`_ForwardScreen`): صادرٌ واحد يُجيب عدّة
/// واردات، وهو أصلُ هذه الدفعة كلّها.
///
/// 🔐 **والقائمة تأتي من `/incoming` المفلترة بقاعدة رؤية الخادم** — فلا يظهر هنا كتابٌ
/// محجوبٌ بحدّ القسم. وهي **مفلترة على القابل للربط** (جديد · قيد المراجعة · تم الرد)
/// مرآةً لـ`BookReplyRules.CanLink` — فلا يختار المستخدم كتاباً يرفضه الخادم بعد ضغطتين.
class _ReplyTargetsScreen extends ConsumerStatefulWidget {
  const _ReplyTargetsScreen();
  @override
  ConsumerState<_ReplyTargetsScreen> createState() => _ReplyTargetsScreenState();
}

class _ReplyTargetsScreenState extends ConsumerState<_ReplyTargetsScreen> {
  late Future<List<IncomingListItem>> _future;
  final Set<int> _selected = {};
  String _search = '';

  /// مرآةُ `BookReplyRules.CanLink` — والمغلق والمؤرشف خارجها.
  static const _linkable = {'New', 'InReview', 'Replied'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(apiClientProvider).incomingList(search: _search);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(
        title: const Text('هل يردّ هذا الكتاب على واردات؟'),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'إلغاء الاعتماد',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'اختيارٌ اختياريّ — الكتب المختارة تصير حالتها (تم الرد) وتُربط بهذا الصادر. '
                  'وتستطيع الاعتماد بلا اختيار.',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث برقم الكتاب أو موضوعه',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => _search = v,
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<IncomingListItem>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('تعذّر جلب الوارد: ${snap.error}',
                                style: TextStyle(color: AppColors.danger)));
                      }
                      final items = (snap.data ?? [])
                          .where((b) => _linkable.contains(b.status))
                          .toList();
                      if (items.isEmpty) {
                        return Center(
                            child: Text('لا توجد كتب واردة قابلة للربط.',
                                style: TextStyle(color: muted)));
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          return CheckboxListTile(
                            value: _selected.contains(b.incomingId),
                            onChanged: (v) => setState(() => v == true
                                ? _selected.add(b.incomingId)
                                : _selected.remove(b.incomingId)),
                            title: Text(b.incomingNumber ?? '#${b.incomingId}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13.5)),
                            subtitle: Text(b.subject,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted)),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        // ⚠️ **قائمةٌ فارغة لا `null`**: الأولى «اعتمِد بلا ربط»
                        //    والثانية «تراجعتُ عن الاعتماد» — وخلطُهما يعتمد بلا قصد.
                        onPressed: () => Navigator.pop(context, <int>[]),
                        child: const Text('اعتماد بلا ربط'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, _selected.toList()),
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: Text('اعتماد وربط (${_selected.length})'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
