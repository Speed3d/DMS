import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

/// نتيجة نافذة «إضافة موظف قائم».
///
/// ⚠️ **حالتان لا واحدة**: الموظف قد يكون في هذه الشركة أصلاً — وحينها الفعلُ الصحيح
/// **فتحُ بطاقته** لا إسنادُه ثانيةً. إرجاعُ المعرّف وحده كان سيدفع الشاشة إلى فتح نموذج
/// إسنادٍ لمن هو مُسنَدٌ فعلاً، فيبدو للمستخدم أنه ينشئ إسناداً ثانياً وهو يحرّر الأول.
class EmployeeLinkResult {
  final int employeeId;
  final String fullName;

  /// مُسنَدٌ إلى الشركة الفعّالة أصلاً.
  final bool alreadyHere;

  const EmployeeLinkResult({
    required this.employeeId,
    required this.fullName,
    required this.alreadyHere,
  });
}

/// Hint: نافذة البحث عن موظف قائم برقم هويته لإسناده إلى الشركة الفعّالة (ADR-027).
///
/// **البحث برقم الهوية وحده — بقرار المالك (2026-08-06).** والبديل المرفوض كان البحث
/// بالاسم: هو أسهل، لكنه يجعل حقلَ بحثٍ في شركةٍ **يستعرض قائمة موظفي شركةٍ أخرى** لمن
/// يجرّب الأسماء. ورقمُ الهوية لا يكشف إلا لمن يعرفه سلفاً، فالكشف يبقى **جواباً عن سؤالٍ
/// محدَّد لا استعراضاً**. (نفس مبدأ `LookupByNationalIdAsync` في الخادم.)
class EmployeeLinkDialog extends ConsumerStatefulWidget {
  const EmployeeLinkDialog({super.key});

  @override
  ConsumerState<EmployeeLinkDialog> createState() => _EmployeeLinkDialogState();
}

class _EmployeeLinkDialogState extends ConsumerState<EmployeeLinkDialog> {
  final _nationalId = TextEditingController();
  bool _searching = false;

  /// هل جرى بحثٌ واكتمل؟ يفصل «لم أبحث بعد» عن «بحثتُ فلم أجد».
  bool _searched = false;

  ExistingEmployeeHint? _hint;
  String? _error;

  @override
  void dispose() {
    _nationalId.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = _nationalId.text.trim();
    if (id.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
      // النتيجة السابقة تُمحى **قبل** البحث لا بعده: إبقاؤها معروضةً أثناء بحثٍ جديد
      // يجعل المستخدم يقرأ اسم الموظف السابق ويظنّه جواب رقمه الجديد.
      _hint = null;
      _searched = false;
    });
    try {
      final hint = await ref.read(apiClientProvider).lookupEmployee(id);
      if (!mounted) return;
      setState(() {
        _hint = hint;
        _searched = true;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('إضافة موظف قائم'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الموظف الذي يعمل في أكثر من شركة له ملفٌّ واحد في النظام. '
              'ابحث برقم هويته لإسناده إلى هذه الشركة بشروط عملٍ مستقلّة — '
              'بلا إنشاء ملفّ ثانٍ له.',
              style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nationalId,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'رقم الهوية',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _searching ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search_rounded, size: 18),
                    label: const Text('بحث', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyDeep,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _Banner(
                icon: Icons.error_outline_rounded,
                color: isDark ? AppColors.dangerDark : AppColors.danger,
                text: 'تعذّر البحث: $_error',
              ),
            ],
            if (_searched && _hint == null && _error == null) ...[
              const SizedBox(height: 14),
              _Banner(
                icon: Icons.person_search_rounded,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                text: 'لا يوجد موظف بهذا الرقم في النظام.\n'
                    'إن كان موظفاً جديداً فأنشئه من زرّ «موظف جديد».',
              ),
            ],
            if (_hint != null) ...[
              const SizedBox(height: 14),
              _Banner(
                icon: _hint!.alreadyInThisCompany
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: _hint!.alreadyInThisCompany
                    ? (isDark ? AppColors.warnDark : AppColors.warn)
                    : (isDark ? AppColors.successDark : AppColors.success),
                text: _hint!.alreadyInThisCompany
                    ? 'الموظف «${_hint!.fullName}» مُسنَدٌ إلى هذه الشركة بالفعل.'
                    : 'وُجد: «${_hint!.fullName}» — يعمل في شركة أخرى.\n'
                        'اضغط «إسناده إلى هذه الشركة» لتحديد صفته وراتبه هنا.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        if (_hint != null)
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(EmployeeLinkResult(
              employeeId: _hint!.employeeId,
              fullName: _hint!.fullName,
              alreadyHere: _hint!.alreadyInThisCompany,
            )),
            icon: Icon(
                _hint!.alreadyInThisCompany
                    ? Icons.open_in_new_rounded
                    : Icons.link_rounded,
                size: 18),
            label: Text(
              _hint!.alreadyInThisCompany ? 'فتح بطاقته' : 'إسناده إلى هذه الشركة',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyDeep,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String text;
  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: c, height: 1.6)),
          ),
        ],
      ),
    );
  }
}
