import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// Hint: نموذج إضافة/تعديل موظف — تبويبان: بيانات شخصية + بيانات الوظيفة في هذه الشركة.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  /// `null` = موظف جديد.
  final int? employeeId;
  const EmployeeFormScreen({super.key, this.employeeId});

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // بيانات شخصية
  final _name = TextEditingController();
  final _nameEn = TextEditingController();
  final _nationalId = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _receiptLanguage = 'Arabic';

  // بيانات الوظيفة
  final _position = TextEditingController();
  final _positionEn = TextEditingController();
  final _baseSalary = TextEditingController();
  final _displayOrder = TextEditingController(text: '0');
  String _currency = 'IQD';
  DateTime _hireDate = DateTime.now();
  bool _isActive = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// تنبيه «هذا الشخص مسجَّل أصلاً» بعد البحث برقم الهوية.
  ExistingEmployeeHint? _existing;

  bool get _isEdit => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _nameEn, _nationalId, _phone, _address, _notes,
      _position, _positionEn, _baseSalary, _displayOrder,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await ref.read(apiClientProvider).employee(widget.employeeId!);
      _name.text = e.fullName;
      _nameEn.text = e.fullNameEn ?? '';
      _nationalId.text = e.nationalId ?? '';
      _phone.text = e.phone ?? '';
      _address.text = e.address ?? '';
      _notes.text = e.notes ?? '';
      _receiptLanguage = e.receiptLanguage;

      final job = e.employment;
      if (job != null) {
        _position.text = job.position;
        _positionEn.text = job.positionEn ?? '';
        _baseSalary.text = job.baseSalary.toStringAsFixed(0);
        _displayOrder.text = '${job.displayOrder}';
        _currency = job.salaryCurrency;
        _hireDate = job.hireDate;
        _isActive = job.isActive;
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// يبحث عن ملفّ قائم بنفس رقم الهوية — يمنع ملفّين لشخص واحد (ADR-023).
  Future<void> _lookup() async {
    final id = _nationalId.text.trim();
    if (id.isEmpty || _isEdit) return;
    try {
      final hint = await ref.read(apiClientProvider).lookupEmployee(id);
      if (mounted) setState(() => _existing = hint);
    } catch (_) {
      // البحث مساعِدٌ لا حاسم — فشلُه لا يمنع الإدخال.
    }
  }

  Map<String, dynamic> get _profileBody => {
        'fullName': _name.text.trim(),
        'fullNameEn': _nameEn.text.trim().isEmpty ? null : _nameEn.text.trim(),
        'nationalId': _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'receiptLanguage': _receiptLanguage,
      };

  Map<String, dynamic> get _employmentBody => {
        'position': _position.text.trim(),
        'positionEn': _positionEn.text.trim().isEmpty ? null : _positionEn.text.trim(),
        'hireDate': _hireDate.toIso8601String(),
        'salaryCurrency': _currency,
        'baseSalary': double.tryParse(_baseSalary.text.trim()) ?? 0,
        'displayOrder': int.tryParse(_displayOrder.text.trim()) ?? 0,
        'isActive': _isActive,
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (_isEdit) {
        await api.updateEmployee(widget.employeeId!, _profileBody);
        await api.saveEmployment(widget.employeeId!, _employmentBody);
      } else if (_existing != null && !_existing!.alreadyInThisCompany) {
        // الشخص مسجَّل في شركة أخرى ⇒ نُسنده لشركتنا بدل إنشاء ملفّ ثانٍ له.
        await api.saveEmployment(_existing!.employeeId, _employmentBody);
      } else {
        await api.createEmployee(_profileBody, _employmentBody);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(sessionProvider).canManageHr;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل موظف' : 'موظف جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // ── تنبيه الملفّ القائم ──
                  if (_existing != null) ...[
                    _ExistingBanner(hint: _existing!),
                    const SizedBox(height: 16),
                  ],

                  _Section(
                    title: 'البيانات الشخصية',
                    icon: Icons.badge_outlined,
                    children: [
                      _Field(
                        controller: _name,
                        label: 'الاسم الكامل بالعربية *',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                      ),
                      _Field(
                        controller: _nameEn,
                        label: 'الاسم بالإنجليزية',
                        hint: 'إلزامي لمن لغة إيصاله إنجليزية',
                        validator: (v) =>
                            (_receiptLanguage == 'English' && (v == null || v.trim().isEmpty))
                                ? 'مطلوب لأن لغة الإيصال إنجليزية'
                                : null,
                      ),
                      _Field(controller: _nationalId, label: 'رقم الهوية', onEditingDone: _lookup),
                      _Field(controller: _phone, label: 'الهاتف'),
                      _Field(controller: _address, label: 'العنوان'),
                      _Dropdown<String>(
                        label: 'لغة إيصال الراتب',
                        value: _receiptLanguage,
                        items: const {'Arabic': 'العربية', 'English': 'الإنجليزية'},
                        onChanged: (v) => setState(() => _receiptLanguage = v!),
                      ),
                      _Field(controller: _notes, label: 'ملاحظات', maxLines: 3),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _Section(
                    title: 'بيانات الوظيفة في هذه الشركة',
                    icon: Icons.work_outline_rounded,
                    subtitle: 'الراتب والصفة يخصّان الشركة الفعّالة وحدها — '
                        'للموظف في شركة أخرى شروطُ عملٍ مستقلّة هناك.',
                    children: [
                      _Field(
                        controller: _position,
                        label: 'الصفة بالعربية *',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'الصفة مطلوبة' : null,
                      ),
                      _Field(controller: _positionEn, label: 'الصفة بالإنجليزية'),
                      _DateField(
                        label: 'تاريخ التعيين *',
                        value: _hireDate,
                        onChanged: (d) => setState(() => _hireDate = d),
                      ),
                      _Dropdown<String>(
                        label: 'عملة الراتب',
                        value: _currency,
                        items: const {'IQD': 'دينار عراقي', 'USD': 'دولار أمريكي'},
                        onChanged: (v) => setState(() => _currency = v!),
                      ),
                      _Field(
                        controller: _baseSalary,
                        label: 'الراتب الأساسي *',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return 'أدخل رقماً صحيحاً';
                          if (n < 0) return 'الراتب لا يكون سالباً';
                          return null;
                        },
                      ),
                      _Field(
                        controller: _displayOrder,
                        label: 'الترتيب في كشف الرواتب',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        title: const Text('على رأس العمل', style: TextStyle(fontSize: 14)),
                        subtitle: Text('غير الفعّال لا يُدرَج في كشوف الشهور الجديدة',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.6))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: (_saving || !canManage) ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navyDeep,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: AppColors.navyDeep.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (!canManage)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('لا تملك صلاحية إدارة الموظفين — العرض فقط.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.6))),
                    ),
                ],
              ),
            ),
    );
  }
}

/// «هذا الشخص مسجَّل أصلاً» — الجسر الوحيد بين الشركات، ويعرض الاسم فقط.
class _ExistingBanner extends StatelessWidget {
  final ExistingEmployeeHint hint;
  const _ExistingBanner({required this.hint});

  @override
  Widget build(BuildContext context) {
    final here = hint.alreadyInThisCompany;
    final color = here ? AppColors.danger : AppColors.warn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(here ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              here
                  ? 'رقم الهوية هذا مسجَّل بالفعل للموظف «${hint.fullName}» في هذه الشركة.'
                  : 'هذا الشخص («${hint.fullName}») مسجَّل في النظام ويعمل في شركة أخرى.\n'
                      'الحفظ سيُسنده إلى شركتك بشروط العمل أدناه — بلا إنشاء ملفّ ثانٍ له.',
              style: TextStyle(fontSize: 13, color: color, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.6))),
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;
  const _Section(
      {required this.title, required this.icon, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final VoidCallback? onEditingDone;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onEditingDone,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onEditingComplete: onEditingDone,
          onTapOutside: (_) => onEditingDone?.call(),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      );
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Dropdown(
      {required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          items: items.entries
              .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: onChanged,
        ),
      );
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(1970),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded,
                size: 16, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Text(DateFormat('yyyy-MM-dd').format(value), style: const TextStyle(fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}
