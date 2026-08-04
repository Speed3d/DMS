import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/downloader.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'employee_form_screen.dart';

/// Hint: ملفّ الموظف — ترويسة بالصورة والحالة، ثم تبويبا المعلومات وسجلّ الرواتب.
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  final int employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  EmployeeDetail? _employee;
  List<SalaryHistoryItem> _history = const [];
  Uint8List? _photo;
  bool _loading = true;
  String? _error;

  /// هل تغيّر شيء يستوجب إعادة تحميل القائمة عند الرجوع؟
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final e = await api.employee(widget.employeeId);
      final h = await api.salaryHistory(widget.employeeId);
      Uint8List? photo;
      if (e.hasPhoto) {
        try {
          photo = await api.employeePhoto(widget.employeeId);
        } catch (_) {
          // غياب الصورة لا يمنع عرض الملفّ.
        }
      }
      if (!mounted) return;
      setState(() {
        _employee = e;
        _history = h;
        _photo = photo;
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

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employeeId: widget.employeeId)),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _terminate() async {
    final result = await showDialog<_TerminationResult>(
      context: context,
      builder: (_) => _TerminateDialog(hireDate: _employee?.employment?.hireDate),
    );
    if (result == null) return;
    try {
      await ref.read(apiClientProvider).terminateEmployee(
          widget.employeeId, result.date, result.reason, result.notes);
      _changed = true;
      await _load();
      if (mounted) _snack('سُجّل إنهاء الخدمة.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
  }

  Future<void> _printReceipt(SalaryHistoryItem item) async {
    try {
      final bytes = await ref.read(apiClientProvider).payrollFile(
          item.year, item.month, 'receipts', employeeId: widget.employeeId);
      await downloadBytes(
          bytes, 'receipt-${item.year}-${item.month.toString().padLeft(2, '0')}.pdf',
          'application/pdf');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    }
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
    final e = _employee;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ملفّ الموظف'),
          actions: [
            if (canManage && e != null) ...[
              IconButton(
                onPressed: _edit,
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'تعديل',
              ),
              if (e.employment?.terminationDate == null)
                IconButton(
                  onPressed: _terminate,
                  icon: const Icon(Icons.person_off_rounded),
                  tooltip: 'إنهاء الخدمة',
                ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                : ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      _Header(employee: e!, photo: _photo),
                      const SizedBox(height: 20),
                      _InfoCard(employee: e),
                      const SizedBox(height: 20),
                      _SalaryHistoryCard(items: _history, onPrint: _printReceipt),
                    ],
                  ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final EmployeeDetail employee;
  final Uint8List? photo;
  const _Header({required this.employee, this.photo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final job = employee.employment;
    final terminated = job?.terminationDate != null;

    return CustomCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.navy.withValues(alpha: 0.12),
            backgroundImage: photo != null ? MemoryImage(photo!) : null,
            child: photo == null
                ? Text(
                    employee.fullName.trim().isNotEmpty
                        ? employee.fullName.trim().characters.first
                        : '؟',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.navy))
                : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                if (employee.fullNameEn != null && employee.fullNameEn!.isNotEmpty)
                  Text(employee.fullNameEn!,
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Text(job?.position ?? '—',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _Chip(
                    icon: Icons.event_available_rounded,
                    label: job != null
                        ? 'التعيين ${DateFormat('yyyy-MM-dd').format(job.hireDate)}'
                        : '—',
                  ),
                  if (job != null)
                    _Chip(
                      icon: Icons.payments_rounded,
                      label:
                          '${NumberFormat('#,##0.##').format(job.baseSalary)} ${job.salaryCurrency == 'USD' ? '\$' : 'د.ع'}',
                    ),
                  _Chip(
                    icon: terminated ? Icons.person_off_rounded : Icons.verified_user_rounded,
                    label: terminated
                        ? 'منتهي الخدمة ${DateFormat('yyyy-MM-dd').format(job!.terminationDate!)}'
                        : 'على رأس العمل',
                    color: terminated
                        ? (isDark ? AppColors.dangerDark : AppColors.danger)
                        : (isDark ? AppColors.successDark : AppColors.success),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? theme.dividerColor).withValues(alpha: color != null ? 0.13 : 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final EmployeeDetail employee;
  const _InfoCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final job = employee.employment;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.info_outline_rounded, title: 'المعلومات'),
          _Row(label: 'رقم الهوية', value: employee.nationalId),
          _Row(label: 'الهاتف', value: employee.phone),
          _Row(label: 'العنوان', value: employee.address),
          _Row(
              label: 'لغة الإيصال',
              value: employee.receiptLanguage == 'English' ? 'الإنجليزية' : 'العربية'),
          if (job != null) ...[
            _Row(label: 'الصفة بالإنجليزية', value: job.positionEn),
            _Row(label: 'الترتيب في الكشف', value: '${job.displayOrder}'),
            if (job.terminationReason != null)
              _Row(label: 'سبب إنهاء الخدمة', value: _reasonLabel(job.terminationReason!)),
            if (job.terminationNotes != null)
              _Row(label: 'ملاحظات الإنهاء', value: job.terminationNotes),
          ],
          _Row(label: 'ملاحظات', value: employee.notes),
        ],
      ),
    );
  }

  static String _reasonLabel(String r) => switch (r) {
        'Resignation' => 'استقالة',
        'Termination' => 'فصل',
        'Retirement' => 'تقاعد',
        'Death' => 'وفاة',
        _ => 'أخرى',
      };
}

class _SalaryHistoryCard extends StatelessWidget {
  final List<SalaryHistoryItem> items;
  final ValueChanged<SalaryHistoryItem> onPrint;
  const _SalaryHistoryCard({required this.items, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat('#,##0.##');

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.receipt_long_rounded, title: 'سجلّ الرواتب'),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('لا توجد رواتب مسجَّلة بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            )
          else
            ...items.map((h) {
              final paid = h.periodStatus == 'Paid';
              final color = paid
                  ? (theme.brightness == Brightness.dark
                      ? AppColors.successDark
                      : AppColors.success)
                  : (theme.brightness == Brightness.dark ? AppColors.warnDark : AppColors.warn);
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text('${h.monthName} ${h.year}',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(
                        '${money.format(h.netSalary)} ${h.currency == 'USD' ? '\$' : 'د.ع'}'
                        '${h.currency == 'USD' ? '  (${money.format(h.netSalaryIqd)} د.ع)' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(paid ? 'مُسدَّد' : 'مسودة',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
                    ),
                    IconButton(
                      // الإيصال يُطبع للمُسدَّد وللمسودّة معاً — المحاسب قد يطبعه قبل الصرف.
                      onPressed: () => onPrint(h),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      tooltip: 'طباعة إيصال الاستلام',
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ),
          Expanded(
            child: Text(
              (value == null || value!.trim().isEmpty) ? '—' : value!,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminationResult {
  final DateTime date;
  final String reason;
  final String? notes;
  _TerminationResult(this.date, this.reason, this.notes);
}

class _TerminateDialog extends StatefulWidget {
  final DateTime? hireDate;
  const _TerminateDialog({this.hireDate});
  @override
  State<_TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<_TerminateDialog> {
  DateTime _date = DateTime.now();
  String _reason = 'Resignation';
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invalid = widget.hireDate != null && _date.isBefore(widget.hireDate!);
    return AlertDialog(
      title: const Text('إنهاء الخدمة'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_rounded, size: 18),
              title: Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}',
                  style: const TextStyle(fontSize: 14)),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: widget.hireDate ?? DateTime(1970),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _date = d);
                },
                child: const Text('تغيير'),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'السبب', isDense: true),
              items: const [
                DropdownMenuItem(value: 'Resignation', child: Text('استقالة')),
                DropdownMenuItem(value: 'Termination', child: Text('فصل')),
                DropdownMenuItem(value: 'Retirement', child: Text('تقاعد')),
                DropdownMenuItem(value: 'Death', child: Text('وفاة')),
                DropdownMenuItem(value: 'Other', child: Text('أخرى')),
              ],
              onChanged: (v) => setState(() => _reason = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true),
            ),
            if (invalid)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('تاريخ الإنهاء لا يسبق تاريخ التعيين.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: invalid
              ? null
              : () => Navigator.pop(
                  context,
                  _TerminationResult(
                      _date, _reason, _notes.text.trim().isEmpty ? null : _notes.text.trim())),
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
