import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/downloader.dart';
import '../core/hr_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'payroll_payment_dialog.dart';

/// Hint: كشف الرواتب الشهري — أهمّ شاشة في الوحدة. جدول أفقي قابل للتحرير المباشر.
///
/// ⚠️ **الصافي يعرضه الخادم لا تحسبه الشاشة:** كل حفظ يُعيد الكشف محسوباً، فما تراه هو
/// ما هو مخزَّن فعلاً. حسابٌ محليّ موازٍ كان سيتباعد عن الخادم عند أول قاعدة تتغيّر.
class PayrollSheetScreen extends ConsumerStatefulWidget {
  final int year;
  final int month;
  const PayrollSheetScreen({super.key, required this.year, required this.month});

  @override
  ConsumerState<PayrollSheetScreen> createState() => _PayrollSheetScreenState();
}

class _PayrollSheetScreenState extends ConsumerState<PayrollSheetScreen> {
  PayrollPeriodModel? _period;
  List<ExternalPaymentHint> _external = const [];
  List<EndOfServiceSuggestion> _endOfService = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// مدخلات المستخدم لكل سطر — تُرسل عند الحفظ، والخادم يحسب الصافي منها.
  final Map<int, _EntryEdit> _edits = {};

  final _rate = TextEditingController();
  final _workingDays = TextEditingController();
  String _mode = 'Fixed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    _workingDays.dispose();
    for (final e in _edits.values) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final p = await api.payrollPeriod(widget.year, widget.month);
      List<ExternalPaymentHint> ext = const [];
      List<EndOfServiceSuggestion> eos = const [];
      if (p != null && !p.isPaid) {
        try {
          ext = await api.externalPayments(widget.year, widget.month);
        } catch (_) {
          // الكشف عبر الشركات مساعِدٌ لا حاسم — فشلُه لا يُعطّل الشاشة.
        }
        try {
          eos = await api.endOfServiceSuggestions(widget.year, widget.month);
        } catch (_) {
          // اقتراح المكافأة كذلك — مطفأٌ افتراضياً في الإعدادات.
        }
      }
      if (!mounted) return;
      _applyPeriod(p);
      setState(() {
        _external = ext;
        _endOfService = eos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _applyPeriod(PayrollPeriodModel? p) {
    _period = p;
    for (final e in _edits.values) {
      e.dispose();
    }
    _edits.clear();
    if (p == null) return;

    _rate.text = p.exchangeRate?.toStringAsFixed(0) ?? '';
    _workingDays.text = '${p.workingDays}';
    _mode = p.workingDaysMode;
    for (final entry in p.entries) {
      _edits[entry.entryId] = _EntryEdit.from(entry);
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiClientProvider).generatePayroll(widget.year, widget.month);
      await _load();
      if (mounted) {
        _snack('أُضيف ${r['added']} · موجود ${r['existing']} · متخطّى ${r['skipped']}');
      }
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveSettings() async {
    final p = _period;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(apiClientProvider).updatePayrollSettings(
            widget.year, widget.month,
            rowVersion: p.rowVersion,
            exchangeRate: double.tryParse(_rate.text.trim()),
            workingDaysMode: _mode,
            workingDays: int.tryParse(_workingDays.text.trim()) ?? p.workingDays,
            notes: p.notes,
          );
      if (!mounted) return;
      setState(() => _applyPeriod(updated));
      _snack('حُدّثت إعدادات الشهر وأُعيد حساب الكشف.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveEntries() async {
    final p = _period;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final body = _edits.entries.map((e) => e.value.toJson(e.key)).toList();
      final updated = await ref
          .read(apiClientProvider)
          .savePayrollEntries(widget.year, widget.month, p.rowVersion, body);
      if (!mounted) return;
      setState(() => _applyPeriod(updated));
      _snack('حُفظ الكشف.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pay() async {
    final p = _period;
    if (p == null) return;

    if (p.needsExchangeRate) {
      _snack('الكشف فيه رواتب بالدولار — حدّد سعر الصرف قبل التسديد.', error: true);
      return;
    }

    final result = await showDialog<PaymentResult>(
      context: context,
      builder: (_) => PayrollPaymentDialog(
        monthLabel: '${p.monthName} ${p.year}',
        totalIqd: p.totalIqd,
        employeeCount: p.entries.length,
      ),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).payPayroll(
            widget.year, widget.month,
            rowVersion: p.rowVersion,
            paidAt: result.paidAt,
            outgoingBookId: null,
            manualBookNumber: result.bookNumber,
            notes: result.notes,
          );
      await _load();
      invalidateHr(ref);
      if (mounted) _snack('سُدّدت رواتب ${p.monthName}.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmExternal(ExternalPaymentHint hint) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مدفوع من شركة أخرى'),
        content: Text(
            'صُرف راتب «${hint.employeeName}» هذا الشهر من «${hint.paidByCompanyName}».\n\n'
            'التأكيد يُعلّم سطره «مدفوع من الخارج» فلا يُصرف مرتين، ولا يغيّر شيئاً في الشركة الأخرى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).confirmExternalPayment(hint.entryId);
      await _load();
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  /// يضع المكافأة المقترَحة في السطر ثم يحفظ — **بضغطة المستخدم لا تلقائياً**.
  Future<void> _applyEndOfService(EndOfServiceSuggestion s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مكافأة نهاية الخدمة'),
        content: Text(
            '«${s.employeeName}» خدم ${s.yearsServed.toStringAsFixed(2)} سنة، '
            'وبنسبة ${s.daysPerYear} يوماً عن كل سنة تكون المكافأة المقترَحة:\n\n'
            '${NumberFormat('#,##0.##').format(s.amount)} ${s.currency == 'USD' ? '\$' : 'د.ع'}\n\n'
            'ستُضاف إلى صافي راتبه هذا الشهر، ويمكنك تعديل الرقم بعدها قبل التسديد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تطبيق')),
        ],
      ),
    );
    if (ok != true) return;

    _edits[s.entryId]?.endOfServiceAmount = s.amount;
    await _saveEntries();
    await _load();
  }

  Future<void> _export(String kind, String ext, String mime) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(apiClientProvider).payrollFile(widget.year, widget.month, kind);
      await downloadBytes(
          bytes, 'payroll-${widget.year}-${widget.month.toString().padLeft(2, '0')}.$ext', mime);
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(sessionProvider).canManageHr;
    final p = _period;

    return Scaffold(
      appBar: AppBar(
        title: Text('رواتب ${arabicMonth(widget.month)} ${widget.year}'),
        actions: [
          if (p != null) ...[
            IconButton(
                onPressed: _busy ? null : () => _export('excel', 'xlsx',
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
                icon: const Icon(Icons.table_view_rounded),
                tooltip: 'تصدير Excel'),
            IconButton(
                onPressed: _busy ? null : () => _export('pdf', 'pdf', 'application/pdf'),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: 'كشف PDF'),
            IconButton(
                onPressed: _busy ? null : () => _export('receipts', 'pdf', 'application/pdf'),
                icon: const Icon(Icons.print_rounded),
                tooltip: 'طباعة كل الإيصالات'),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
              : p == null
                  ? _NotGenerated(busy: _busy, canManage: canManage, onGenerate: _generate)
                  : _buildSheet(p, canManage),
    );
  }

  Widget _buildSheet(PayrollPeriodModel p, bool canManage) {
    final editable = canManage && !p.isPaid;

    return Column(
      children: [
        _Toolbar(
          period: p,
          rate: _rate,
          workingDays: _workingDays,
          mode: _mode,
          editable: editable,
          busy: _busy,
          onModeChanged: (m) => setState(() {
            _mode = m;
            if (m == 'Calendar') {
              _workingDays.text = '${DateUtils.getDaysInMonth(p.year, p.month)}';
            }
          }),
          onApply: _saveSettings,
          onRegenerate: _generate,
        ),

        // تنبيهات «مدفوع من شركة أخرى» (ADR-024)
        if (_external.isNotEmpty && editable)
          _ExternalBanner(hints: _external, onConfirm: _confirmExternal),

        // مكافآت نهاية الخدمة المقترَحة (الدفعة ٢)
        if (_endOfService.isNotEmpty && editable)
          _EndOfServiceBanner(items: _endOfService, onApply: _applyEndOfService),

        if (p.needsExchangeRate)
          const _WarnBanner(
            message: 'الكشف فيه رواتب بالدولار بلا سعر صرف — '
                'المعادل بالدينار صفرٌ مؤقّت، والتسديد مرفوض حتى تحدّده.',
          ),

        Expanded(child: _EntriesTable(period: p, edits: _edits, editable: editable)),

        _BottomBar(
          period: p,
          editable: editable,
          busy: _busy,
          onSave: _saveEntries,
          onPay: _pay,
        ),
      ],
    );
  }
}

/// حالة تحرير سطر — تُمسك المتحكّمات ومنها يُبنى جسم الطلب.
class _EntryEdit {
  final TextEditingController absenceDays;
  final TextEditingController bonus;
  final TextEditingController deduction;
  final TextEditingController notes;

  /// خصم غياب عدّله المستخدم يدوياً — `null` يعني «اترك الخادم يقترحه».
  double? manualAbsenceDeduction;

  /// مكافأة نهاية الخدمة — تُرسل فقط لمن انتهت خدمته، وبقرار المستخدم.
  double? endOfServiceAmount;

  _EntryEdit({
    required this.absenceDays,
    required this.bonus,
    required this.deduction,
    required this.notes,
    this.manualAbsenceDeduction,
    this.endOfServiceAmount,
  });

  factory _EntryEdit.from(PayrollEntryModel e) => _EntryEdit(
        absenceDays: TextEditingController(text: e.absenceDays == 0 ? '' : '${e.absenceDays}'),
        bonus: TextEditingController(text: e.bonusAmount?.toStringAsFixed(0) ?? ''),
        deduction: TextEditingController(text: e.deductionAmount?.toStringAsFixed(0) ?? ''),
        notes: TextEditingController(text: e.notes ?? ''),
        manualAbsenceDeduction: e.absenceDeductionIsManual ? e.absenceDeduction : null,
        endOfServiceAmount: e.endOfServiceAmount,
      );

  Map<String, dynamic> toJson(int entryId) => {
        'entryId': entryId,
        'absenceDays': int.tryParse(absenceDays.text.trim()) ?? 0,
        'bonusAmount': double.tryParse(bonus.text.trim()),
        'deductionAmount': double.tryParse(deduction.text.trim()),
        'manualAbsenceDeduction': manualAbsenceDeduction,
        'eligibleDaysOverride': null,
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'endOfServiceAmount': endOfServiceAmount,
      };

  void dispose() {
    absenceDays.dispose();
    bonus.dispose();
    deduction.dispose();
    notes.dispose();
  }
}

class _NotGenerated extends StatelessWidget {
  final bool busy;
  final bool canManage;
  final VoidCallback onGenerate;
  const _NotGenerated(
      {required this.busy, required this.canManage, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_add_rounded,
              size: 60, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          const Text('لم يُنشأ كشف هذا الشهر بعد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('التوليد يجلب كل موظفي الشركة المستحقّين في هذا الشهر.',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (busy || !canManage) ? null : onGenerate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('توليد كشف الشهر',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyDeep,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final PayrollPeriodModel period;
  final TextEditingController rate;
  final TextEditingController workingDays;
  final String mode;
  final bool editable;
  final bool busy;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onApply;
  final VoidCallback onRegenerate;

  const _Toolbar({
    required this.period, required this.rate, required this.workingDays,
    required this.mode, required this.editable, required this.busy,
    required this.onModeChanged, required this.onApply, required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = period.isPaid
        ? (isDark ? AppColors.successDark : AppColors.success)
        : (isDark ? AppColors.warnDark : AppColors.warn);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: CustomCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(period.isPaid ? 'مُسدَّد' : 'مسودة',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: statusColor)),
            ),
            SizedBox(
              width: 170,
              child: TextField(
                controller: rate,
                enabled: editable,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                decoration: InputDecoration(
                  labelText: 'سعر الصرف (دولار)',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: InputDecoration(
                  labelText: 'أيام العمل',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Fixed', child: Text('ثابت')),
                  DropdownMenuItem(value: 'Calendar', child: Text('تقويمي')),
                ],
                onChanged: editable ? (v) => onModeChanged(v!) : null,
              ),
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: workingDays,
                enabled: editable && mode == 'Fixed',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'عدد الأيام',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (editable)
              OutlinedButton.icon(
                onPressed: busy ? null : onApply,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('تطبيق وإعادة الحساب'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            if (editable)
              OutlinedButton.icon(
                onPressed: busy ? null : onRegenerate,
                icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                // التوليد تراكميّ — يضيف الناقص ولا يمسّ ما أُدخل يدوياً.
                label: const Text('جلب الموظفين الجدد'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExternalBanner extends StatelessWidget {
  final List<ExternalPaymentHint> hints;
  final ValueChanged<ExternalPaymentHint> onConfirm;
  const _ExternalBanner({required this.hints, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warn, size: 20),
              SizedBox(width: 10),
              Text('موظفون صُرفت رواتبهم من شركة أخرى هذا الشهر',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.warn)),
            ]),
            const SizedBox(height: 10),
            ...hints.map((h) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      // ⚠️ **التاريخ جزءٌ من التنبيه لا زينة** — المحاسب يحتاج أن يعرف
                      //    *متى* صُرف ليطابقه بسجلّه (بلاغ المالك ٢). ويُحذف إن غاب بدل
                      //    عرض «بتاريخ —» التي توهم أن الصرف بلا تاريخ.
                      child: Text(
                          '${h.employeeName} — صُرف من «${h.paidByCompanyName}»'
                          '${h.paidAt != null ? ' بتاريخ ${DateFormat('yyyy-MM-dd').format(h.paidAt!)}' : ''}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => onConfirm(h),
                      child: const Text('تأكيد — مدفوع من الخارج'),
                    ),
                  ]),
                )),
          ],
        ),
      ),
    );
  }
}

/// مكافآت نهاية الخدمة المقترَحة — **اقتراحٌ لا تطبيق**، والتفعيل من إعدادات الوحدة.
class _EndOfServiceBanner extends StatelessWidget {
  final List<EndOfServiceSuggestion> items;
  final ValueChanged<EndOfServiceSuggestion> onApply;
  const _EndOfServiceBanner({required this.items, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.##');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 20),
              SizedBox(width: 10),
              Text('مكافآت نهاية خدمة مقترَحة',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.gold)),
            ]),
            ...items.map((s) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${s.employeeName} — ${s.yearsServed.toStringAsFixed(2)} سنة خدمة '
                        '⇐ ${money.format(s.amount)} ${s.currency == 'USD' ? '\$' : 'د.ع'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: () => onApply(s), child: const Text('تطبيق')),
                  ]),
                )),
          ],
        ),
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  final String message;
  const _WarnBanner({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.danger, height: 1.6))),
          ]),
        ),
      );
}

/// الحشو الأفقي داخل صفوف الجدول وترويسته — يدخل في حساب العرض الكلّي.
const double _kRowHPadding = 16;

/// أعمدة كشف الرواتب — **العنوان والعرض في مصدر واحد**.
///
/// ⚠️ **لماذا تعداد لا أرقام متناثرة؟** كان عرض الجدول رقماً أكتبه بيدي (`1476`) بينما
/// مجموع الأعمدة 1538، فتجاوزَه بـ**94 بكسل** وظهر شريط «RIGHT OVERFLOWED» فوق عمود
/// الاسم فحجب أسماء الموظفين. وأخطأتُ فيه **مرّتين**: مرّةً عند البناء الأول ومرّةً حين
/// أضفتُ عمود «نهاية الخدمة» وزدتُ الرقمين بمقدارٍ واحد فبقي الفارق كما هو.
/// الآن **العرض يُحسب من هذه القائمة لا يُكتب**، فإضافة عمود لا تحتاج تذكّر رقمٍ في مكان آخر.
enum _Col {
  seq('#', 34),
  employee('الاسم', 190),
  position('الصفة', 130),
  currency('العملة', 60),
  base('الأساسي', 120),
  days('الأيام', 66),
  absence('غياب', 82),
  absenceDed('خصم الغياب', 116),
  bonus('مكافأة', 116),
  endOfService('نهاية الخدمة', 116),
  deduction('خصم', 116),
  net('الصافي', 122),
  netIqd('بالدينار', 130),
  notes('ملاحظات', 140);

  const _Col(this.label, this.width);
  final String label;
  final double width;

  /// العرض الكلّي — مجموع الأعمدة زائد الحشو على الجانبين.
  static double get tableWidth =>
      values.fold<double>(0, (sum, c) => sum + c.width) + _kRowHPadding * 2;
}

class _EntriesTable extends StatelessWidget {
  final PayrollPeriodModel period;
  final Map<int, _EntryEdit> edits;
  final bool editable;
  const _EntriesTable(
      {required this.period, required this.edits, required this.editable});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0.##');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CustomCard(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _Col.tableWidth,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _kRowHPadding, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  // الترويسة تُبنى من التعداد نفسه — فلا تتباعد عن أعرض الصفوف.
                  child: Row(
                    children: [
                      for (final c in _Col.values)
                        SizedBox(width: c.width, child: _H(c.label)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: period.entries.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, i) {
                      final e = period.entries[i];
                      final edit = edits[e.entryId];
                      return _EntryRow(
                          index: i + 1, entry: e, edit: edit, editable: editable, money: money);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final int index;
  final PayrollEntryModel entry;
  final _EntryEdit? edit;
  final bool editable;
  final NumberFormat money;

  const _EntryRow({
    required this.index, required this.entry, required this.edit,
    required this.editable, required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ألوان الحالات الخاصة — نفس دلالات Excel والـPDF فلا يتعلّم المستخدم ترميزين.
    final Color? bg = entry.isTerminated
        ? AppColors.danger.withValues(alpha: isDark ? 0.13 : 0.07)
        : entry.isNewHire
            ? Colors.blue.withValues(alpha: isDark ? 0.13 : 0.07)
            : entry.paidElsewhere
                ? AppColors.warn.withValues(alpha: isDark ? 0.13 : 0.07)
                : null;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: _kRowHPadding, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: _Col.seq.width, child: Text('$index', style: const TextStyle(fontSize: 12.5))),
          SizedBox(
            width: _Col.employee.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                if (entry.isNewHire || entry.isTerminated || entry.paidElsewhere)
                  Text(
                    entry.isTerminated
                        ? 'منتهي الخدمة'
                        : entry.isNewHire
                            ? 'تعيين جديد'
                            : 'مدفوع من ${entry.paidByCompanyName ?? "شركة أخرى"}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: entry.isTerminated
                            ? AppColors.danger
                            : entry.isNewHire
                                ? Colors.blue
                                : AppColors.warn),
                  ),
              ],
            ),
          ),
          SizedBox(
              width: _Col.position.width,
              child: Text(entry.position,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5))),
          SizedBox(
              width: _Col.currency.width,
              child: Text(entry.isUsd ? '\$' : 'د.ع',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          SizedBox(
              width: _Col.base.width,
              child: Text(money.format(entry.baseSalary),
                  style: const TextStyle(fontSize: 12.5))),
          SizedBox(
              width: _Col.days.width,
              child: Text('${entry.eligibleDays}',
                  style: const TextStyle(fontSize: 12.5))),
          SizedBox(
            width: _Col.absence.width,
            child: _Cell(controller: edit?.absenceDays, editable: editable, digitsOnly: true),
          ),
          SizedBox(
              width: _Col.absenceDed.width,
              child: Text(money.format(entry.absenceDeduction),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          entry.absenceDeductionIsManual ? FontWeight.w900 : FontWeight.normal,
                      color: entry.absenceDeduction > 0 ? AppColors.danger : null))),
          SizedBox(width: _Col.bonus.width, child: _Cell(controller: edit?.bonus, editable: editable)),
          SizedBox(
            width: _Col.endOfService.width,
            // تُعرض للمنتهية خدمته وحده — الخادم يرفضها لغيره على أي حال.
            child: entry.isTerminated
                ? Text(
                    entry.endOfServiceAmount == null
                        ? '—'
                        : money.format(entry.endOfServiceAmount),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: entry.endOfServiceAmount != null ? AppColors.gold : null))
                : const Text('—', style: TextStyle(fontSize: 12.5)),
          ),
          SizedBox(width: _Col.deduction.width, child: _Cell(controller: edit?.deduction, editable: editable)),
          SizedBox(
              width: _Col.net.width,
              child: Text(money.format(entry.netSalary),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
          SizedBox(
            width: _Col.netIqd.width,
            child: Text(money.format(entry.netSalaryIqd),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppColors.goldBrightDark : AppColors.gold)),
          ),
          SizedBox(
              width: _Col.notes.width,
              child: _Cell(controller: edit?.notes, editable: editable, numeric: false)),
        ],
      ),
    );
  }
}

/// خلية قابلة للتحرير داخل الجدول.
class _Cell extends StatelessWidget {
  final TextEditingController? controller;
  final bool editable;
  final bool numeric;
  final bool digitsOnly;
  const _Cell({
    required this.controller,
    required this.editable,
    this.numeric = true,
    this.digitsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextField(
        controller: controller,
        enabled: editable,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric
            ? [
                digitsOnly
                    ? FilteringTextInputFormatter.digitsOnly
                    : FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ]
            : null,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          hintText: '—',
          hintStyle: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final PayrollPeriodModel period;
  final bool editable;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onPay;

  const _BottomBar({
    required this.period, required this.editable, required this.busy,
    required this.onSave, required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final money = NumberFormat('#,##0.##');

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
      child: Row(
        children: [
          Text('${period.entries.length} موظفاً',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65))),
          const SizedBox(width: 20),
          Text('الإجمالي: ',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75))),
          Text('${money.format(period.totalIqd)} د.ع',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppColors.goldBrightDark : AppColors.gold)),
          const Spacer(),
          if (editable) ...[
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('حفظ المسودة',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: busy ? null : onPay,
                icon: const Icon(Icons.verified_rounded, size: 18),
                label: const Text('تسديد الرواتب',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.successDark : AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
              ),
            ),
          ] else if (period.isPaid)
            Row(children: [
              Icon(Icons.lock_rounded,
                  size: 17, color: isDark ? AppColors.successDark : AppColors.success),
              const SizedBox(width: 8),
              Text(
                'مُسدَّد${period.manualBookNumber != null ? ' — كتاب ${period.manualBookNumber}' : ''}',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.successDark : AppColors.success),
              ),
            ]),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
      ));
}
