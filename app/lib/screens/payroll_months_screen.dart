import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/hr_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'payroll_sheet_screen.dart';

/// Hint: شبكة الأشهر الاثني عشر — الرمادي لم يُنشأ، الأصفر مسودّة، الأخضر مُسدَّد.
class PayrollMonthsScreen extends ConsumerStatefulWidget {
  final int year;
  const PayrollMonthsScreen({super.key, required this.year});

  @override
  ConsumerState<PayrollMonthsScreen> createState() => _PayrollMonthsScreenState();
}

class _PayrollMonthsScreenState extends ConsumerState<PayrollMonthsScreen> {
  late Future<List<PayrollMonth>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiClientProvider).payrollMonths(widget.year);
    setState(() {});
  }

  Future<void> _openMonth(PayrollMonth m) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayrollSheetScreen(year: widget.year, month: m.month),
      ),
    );
    _reload();
    invalidateHr(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0');

    return Scaffold(
      appBar: AppBar(title: Text('رواتب ${widget.year}')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: FutureBuilder<List<PayrollMonth>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child:
                      Text('${snap.error}', style: const TextStyle(color: AppColors.danger)));
            }
            final months = snap.data ?? const <PayrollMonth>[];
            final total = months.fold<double>(0, (s, m) => s + m.totalIqd);
            final paidCount = months.where((m) => m.isPaid).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      mainAxisExtent: 132,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: months.length,
                    itemBuilder: (context, i) =>
                        _MonthCard(month: months[i], onTap: () => _openMonth(months[i])),
                  ),
                ),
                const SizedBox(height: 18),
                CustomCard(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.summarize_rounded, size: 20, color: AppColors.gold),
                      const SizedBox(width: 10),
                      Text('إجمالي السنة',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.75))),
                      const SizedBox(width: 16),
                      Text('$paidCount من 12 شهراً مُسدَّد',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.6))),
                      const Spacer(),
                      Text('${money.format(total)} د.ع',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  final PayrollMonth month;
  final VoidCallback onTap;
  const _MonthCard({required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final money = NumberFormat('#,##0');

    late Color accent;
    late String label;
    if (!month.exists) {
      accent = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.35) ?? Colors.grey;
      label = 'لم يُنشأ';
    } else if (month.isPaid) {
      accent = isDark ? AppColors.successDark : AppColors.success;
      label = 'مُسدَّد';
    } else {
      accent = isDark ? AppColors.warnDark : AppColors.warn;
      label = 'مسودة';
    }

    return CustomCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(month.monthName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w800, color: accent)),
              ),
            ],
          ),
          const Spacer(),
          if (month.exists) ...[
            Text('${money.format(month.totalIqd)} د.ع',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${month.employeeCount} موظفاً',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ] else
            Text('اضغط للتوليد',
                style: TextStyle(
                    fontSize: 12.5,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
