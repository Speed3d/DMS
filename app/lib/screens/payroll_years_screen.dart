import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/hr_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'payroll_months_screen.dart';

/// Hint: الشاشة الرئيسية للرواتب — بطاقة لكل سنة بإجمالياتها.
///
/// ⚠️ **لا كيان «سنة» في الباك-إند** — السنوات مشتقّة من الفترات. لذلك «سنة جديدة» هنا
/// مجرّد فتحٍ لشبكة أشهرها، والسنة تُولَد فعلياً عند توليد أول شهر فيها.
class PayrollYearsScreen extends ConsumerStatefulWidget {
  const PayrollYearsScreen({super.key});
  @override
  ConsumerState<PayrollYearsScreen> createState() => _PayrollYearsScreenState();
}

class _PayrollYearsScreenState extends ConsumerState<PayrollYearsScreen> {
  late Future<List<PayrollYear>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).payrollYears();
    setState(() {});
  }

  Future<void> _openYear(int year) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PayrollMonthsScreen(year: year)),
    );
    _reload();
    invalidateHr(ref);
  }

  Future<void> _addYear() async {
    final now = DateTime.now().year;
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _YearPickerDialog(initial: now),
    );
    if (picked != null && mounted) _openYear(picked);
  }

  Future<void> _deleteYear(PayrollYear y) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('حذف سنة ${y.year}'),
        content: Text('سيُحذف ${y.monthsCreated} كشفاً حذفاً ناعماً. '
            'العملية مرفوضة إن كان في السنة شهرٌ مُسدَّد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deletePayrollYear(y.year);
      _reload();
      invalidateHr(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(sessionProvider).canManagePayroll;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('سنوات الرواتب',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: theme.textTheme.bodyLarge?.color)),
                ),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: canManage ? _addYear : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('فتح سنة',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyDeep,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      shadowColor: AppColors.navyDeep.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: FutureBuilder<List<PayrollYear>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                        child: Text('${snap.error}',
                            style: const TextStyle(color: AppColors.danger)));
                  }
                  final years = snap.data ?? const <PayrollYear>[];
                  if (years.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_outlined,
                              size: 56,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.35)),
                          const SizedBox(height: 14),
                          const Text('لا توجد كشوف رواتب بعد',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('افتح سنة ثم ولّد كشف أول شهر.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.6))),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      mainAxisExtent: 168,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                    ),
                    itemCount: years.length,
                    itemBuilder: (context, i) => _YearCard(
                      year: years[i],
                      canManage: canManage,
                      onOpen: () => _openYear(years[i].year),
                      onDelete: () => _deleteYear(years[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearCard extends StatelessWidget {
  final PayrollYear year;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  const _YearCard(
      {required this.year, required this.canManage, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final money = NumberFormat('#,##0');
    final allPaid = year.monthsCreated > 0 && year.monthsPaid == year.monthsCreated;

    return CustomCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${year.year}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (canManage)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  tooltip: 'حذف السنة',
                  color: AppColors.danger,
                ),
            ],
          ),
          const Spacer(),
          // 🔴 **الرقم الكبير = المُسدَّد فقط** (بلاغ المالك 2026-08-06): كان يجمع المسودّات
          //    معه، فتَعِد البطاقةُ بمصروفٍ لم يقع نصفُه.
          Row(children: [
            Text('${money.format(year.totalIqd)} د.ع',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppColors.goldBrightDark : AppColors.gold)),
            const SizedBox(width: 6),
            Text('مُسدَّد',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
          ]),
          // والمسودّات سطرٌ ثانٍ — يُعرَف ولا يُخلط.
          if (year.hasDraft)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('+ ${money.format(year.draftTotalIqd)} د.ع بانتظار التسديد',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.warnDark : AppColors.warn)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.event_note_rounded,
                size: 14, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text('${year.monthsCreated} شهراً · ${year.monthsPaid} مُسدَّد',
                style: TextStyle(
                    fontSize: 12.5,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65))),
            const Spacer(),
            if (allPaid)
              Icon(Icons.check_circle_rounded,
                  size: 16, color: isDark ? AppColors.successDark : AppColors.success),
          ]),
        ],
      ),
    );
  }
}

class _YearPickerDialog extends StatefulWidget {
  final int initial;
  const _YearPickerDialog({required this.initial});
  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late int _year = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فتح سنة'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.remove_circle_outline_rounded)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('$_year',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          ),
          IconButton(
              // سنةٌ واحدة إلى الأمام كحدّ — الباك-إند يرفض ما بعدها.
              onPressed: _year >= DateTime.now().year + 1
                  ? null
                  : () => setState(() => _year++),
              icon: const Icon(Icons.add_circle_outline_rounded)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _year), child: const Text('فتح')),
      ],
    );
  }
}
