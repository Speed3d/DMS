import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';

/// نتيجة نافذة التسديد.
class PaymentResult {
  final DateTime paidAt;
  final String? bookNumber;
  final String? notes;
  PaymentResult(this.paidAt, this.bookNumber, this.notes);
}

/// Hint: نافذة تأكيد تسديد رواتب الشهر — **العملية لا رجعة فيها** فالتحذير صريح.
class PayrollPaymentDialog extends StatefulWidget {
  final String monthLabel;
  final double totalIqd;
  final int employeeCount;

  const PayrollPaymentDialog({
    super.key,
    required this.monthLabel,
    required this.totalIqd,
    required this.employeeCount,
  });

  @override
  State<PayrollPaymentDialog> createState() => _PayrollPaymentDialogState();
}

class _PayrollPaymentDialogState extends State<PayrollPaymentDialog> {
  DateTime _paidAt = DateTime.now();
  final _book = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _book.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0.##');

    return AlertDialog(
      title: Text('تسديد رواتب ${widget.monthLabel}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('${widget.employeeCount} موظفاً',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Text('${money.format(widget.totalIqd)} د.ع',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ]),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, size: 18),
              title: Text('تاريخ التسديد: ${DateFormat('yyyy-MM-dd').format(_paidAt)}',
                  style: const TextStyle(fontSize: 14)),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _paidAt,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _paidAt = d);
                },
                child: const Text('تغيير'),
              ),
            ),
            TextField(
              controller: _book,
              decoration: const InputDecoration(
                labelText: 'رقم كتاب الصرف (اختياري)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'لا يمكن التراجع عن التسديد — يُقفل الكشف فلا يقبل تعديلاً ولا حذفاً.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.6),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            PaymentResult(
              _paidAt,
              _book.text.trim().isEmpty ? null : _book.text.trim(),
              _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          ),
          icon: const Icon(Icons.verified_rounded, size: 18),
          label: const Text('تأكيد التسديد'),
        ),
      ],
    );
  }
}
