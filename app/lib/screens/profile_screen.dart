import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/downloader.dart';
import '../core/profile_providers.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import 'change_password_screen.dart';

/// الملف الشخصي — **ما يخصّ صاحب الجلسة وحده** (ADR-033).
///
/// 🔴 **عرضٌ لا تحرير** (قرار المالك 2026-08-10): لا تعديل للاسم — لا الحسابيّ ولا الرسميّ.
/// وما يُحرَّر هنا شيئان لا ثالث لهما: **كلمة المرور** و**طلب إجازة**. الصورة تُرفع من
/// ملفّ الموظف بيد شؤون الموظفين، فتبقى صورةً رسميةً في ملفٍّ لا صورةَ حسابٍ شخصيّة.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Uint8List? _photo;
  int? _photoForEmployee;

  /// يجلب الصورة مرّةً لكل بطاقة — وفشلُها لا يُسقط الشاشة.
  Future<void> _ensurePhoto(MyProfile p) async {
    if (!p.hasPhoto || p.employeeId == null || _photoForEmployee == p.employeeId) return;
    _photoForEmployee = p.employeeId;
    try {
      final bytes = await ref.read(apiClientProvider).myPhoto();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      // غياب الصورة لا يمنع عرض الملفّ.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfileProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorBox(message: '$e', onRetry: () => invalidateProfile(ref)),
      data: (profile) {
        if (profile == null) {
          return const Center(child: Text('تعذّر قراءة بيانات الحساب.'));
        }
        _ensurePhoto(profile);

        // التبويبتان الأخريان **حقيقةُ ربطٍ لا صلاحية**: بلا بطاقة لا إجازات ولا رواتب.
        final linked = profile.isLinkedToEmployee;
        final tabs = <Tab>[
          const Tab(text: 'هويّتي'),
          if (linked) const Tab(text: 'إجازاتي'),
          if (linked) const Tab(text: 'رواتبي'),
        ];

        return DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              _Header(profile: profile, photo: _photo),
              Material(
                color: Colors.transparent,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: tabs,
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _IdentityTab(profile: profile),
                    if (linked) const _LeavesTab(),
                    if (linked) const _PayslipsTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════ الترويسة ═══════════════════════════

class _Header extends StatelessWidget {
  final MyProfile profile;
  final Uint8List? photo;
  const _Header({required this.profile, this.photo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile.employeeFullName ?? profile.fullName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: CustomCard(
        padding: const EdgeInsets.all(18),
        // ⚠️ `Wrap` لا `Row` — درسُ G12: شريطٌ أفقيّ يفيض تحت ~500 بكسل.
        child: Wrap(
          spacing: 18,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Avatar(photo: photo, fallback: name),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (profile.position != null) profile.position!,
                      _roleLabel(profile.role),
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.gold, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (profile.companyName != null) profile.companyName!,
                      if (profile.departmentName != null) profile.departmentName!,
                    ].join(' — '),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            if (!profile.isLinkedToEmployee) const _UnlinkedNotice(),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Uint8List? photo;
  final String fallback;
  const _Avatar({this.photo, required this.fallback});

  @override
  Widget build(BuildContext context) => Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1B3A6B), Color(0xFF0C1B33)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          image: photo == null
              ? null
              : DecorationImage(image: MemoryImage(photo!), fit: BoxFit.cover),
        ),
        alignment: Alignment.center,
        child: photo != null
            ? null
            : Text(
                fallback.isNotEmpty ? fallback[0] : 'U',
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
              ),
      );
}

/// من لا بطاقةَ له — **يُخبَر بالسبب** بدل أن يرى تبويبتين مفقودتين بلا تفسير.
class _UnlinkedNotice extends StatelessWidget {
  const _UnlinkedNotice();

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warn.withValues(alpha: 0.35)),
        ),
        child: const Text(
          'حسابك غير مرتبط ببطاقة موظف في هذه الشركة — راجع شؤون الموظفين '
          'لتظهر لك إجازاتك ورواتبك.',
          style: TextStyle(fontSize: 12.5, height: 1.5),
        ),
      );
}

// ═══════════════════════════ هويّتي ═══════════════════════════

class _IdentityTab extends StatelessWidget {
  final MyProfile profile;
  const _IdentityTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('بيانات الحساب'),
                _Field('اسم المستخدم', profile.username),
                _Field('الاسم على الحساب', profile.fullName),
                _Field('الدور', _roleLabel(profile.role)),
                _Field('الشركة', profile.companyName),
                _Field('القسم', profile.departmentName),
                if (profile.isLinkedToEmployee) ...[
                  const SizedBox(height: 10),
                  const _SectionTitle('بيانات الموظف'),
                  _Field('الاسم الرسمي', profile.employeeFullName),
                  _Field('الاسم بالإنجليزية', profile.employeeFullNameEn),
                  _Field('الصفة', profile.position),
                  _Field('تاريخ التعيين',
                      profile.hireDate == null ? null : df.format(profile.hireDate!)),
                  _Field('رقم الهوية', profile.nationalId),
                  _Field('الهاتف', profile.phone),
                  _Field('العنوان', profile.address),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('الأمان'),
                const Text(
                  'الاسم وبيانات الموظف تُعدَّل من شؤون الموظفين لا من هنا — '
                  'فهي تظهر في الكتب الرسمية وإيصالات الرواتب.',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('تغيير كلمة المرور'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ إجازاتي ═══════════════════════════

class _LeavesTab extends ConsumerWidget {
  const _LeavesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLeavesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorBox(message: '$e', onRetry: () => invalidateProfile(ref)),
      data: (leaves) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _openRequestDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('طلب إجازة'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الطلب يُرفع معلَّقاً، وقرارُ الحسم من الراتب يعود لمن يوافق.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withValues(alpha: 0.65)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: leaves.isEmpty
                ? const Center(child: Text('لا توجد إجازات مسجَّلة.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                    itemCount: leaves.length,
                    itemBuilder: (_, i) => _LeaveTile(leave: leaves[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRequestDialog(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _RequestLeaveDialog(),
    );
    if (ok == true) invalidateProfile(ref);
  }
}

class _LeaveTile extends ConsumerWidget {
  final LeaveModel leave;
  const _LeaveTile({required this.leave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('yyyy-MM-dd');
    final (color, label) = switch (leave.status) {
      'Approved' => (AppColors.success, 'موافَق عليها'),
      'Rejected' => (AppColors.danger, 'مرفوضة'),
      _ => (AppColors.warn, 'بانتظار الموافقة'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text('${leave.leaveTypeLabel} — ${leave.durationDays} يوماً',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 3),
            Text('${df.format(leave.fromDate)} ← ${df.format(leave.toDate)}',
                style: const TextStyle(fontSize: 12.5)),
            if (leave.notes != null && leave.notes!.isNotEmpty)
              Text(leave.notes!, style: const TextStyle(fontSize: 12)),
            // الحسم يُذكر بعد البتّ فقط — قبله لا قرارَ يُعرض.
            if (leave.isApproved)
              Text(leave.deductFromSalary ? 'تُحسم من الراتب' : 'بلا حسم من الراتب',
                  style: TextStyle(
                      fontSize: 12,
                      color: leave.deductFromSalary ? AppColors.warn : AppColors.success)),
            if (leave.isRejected && leave.reviewNotes != null)
              Text('سبب الرفض: ${leave.reviewNotes}',
                  style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
        ),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11.5, color: color, fontWeight: FontWeight.bold)),
            ),
            // 🔴 السحب لطلبي أنا **وهو معلّق** — بعد البتّ يبقى سجلّاً، وما سجّله
            //    كاتب الشؤون واقعةٌ لا طلبٌ ينتظر.
            if (leave.isSelfRequested && leave.isPending)
              IconButton(
                tooltip: 'سحب الطلب',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _cancel(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سحب الطلب'),
        content: const Text('هل تسحب طلب الإجازة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('سحب')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).cancelMyLeave(leave.leaveId);
      invalidateProfile(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// نموذج طلب الإجازة — **بلا «تحتاج موافقة» وبلا «تُحسم من الراتب»**.
///
/// 🔴 غيابُ الحقلين هو الأمان نفسه لا نقصٌ في النموذج: الأولى يفرضها الخادم `true`،
/// والثانية قرارُ المراجع. عرضُهما هنا كان سيوهم الموظف أنه يملك ما لا يملك.
class _RequestLeaveDialog extends ConsumerStatefulWidget {
  const _RequestLeaveDialog();

  @override
  ConsumerState<_RequestLeaveDialog> createState() => _RequestLeaveDialogState();
}

class _RequestLeaveDialogState extends ConsumerState<_RequestLeaveDialog> {
  String _type = 'Annual';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _types = {
    'Annual': 'اعتيادية',
    'Sick': 'مرضية',
    'Administrative': 'إدارية',
    'Unpaid': 'بلا راتب',
    'Other': 'أخرى',
  };

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).requestLeave({
        'leaveType': _type,
        'fromDate': DateFormat('yyyy-MM-dd').format(_from),
        'toDate': DateFormat('yyyy-MM-dd').format(_to),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final days = _to.difference(_from).inDays + 1;

    return AlertDialog(
      title: const Text('طلب إجازة'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع الإجازة'),
                items: _types.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'Annual'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('من: ${df.format(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('إلى: ${df.format(_to)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('المدّة: $days يوماً',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: 10),
              const Text(
                'يُرفع الطلب معلَّقاً بانتظار الموافقة، وقرارُ الحسم من الراتب يعود '
                'لمن يوافق عليه.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إرسال الطلب'),
        ),
      ],
    );
  }
}

// ═══════════════════════════ رواتبي ═══════════════════════════

class _PayslipsTab extends ConsumerWidget {
  const _PayslipsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPayslipsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorBox(message: '$e', onRetry: () => invalidateProfile(ref)),
      data: (slips) => slips.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد رواتب مُسدَّدة بعد.\n'
                  'تظهر هنا أشهرُ الرواتب بعد تسديدها فقط.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: slips.length,
              itemBuilder: (_, i) => _PayslipCard(slip: slips[i]),
            ),
    );
  }
}

class _PayslipCard extends ConsumerWidget {
  final MyPayslip slip;
  const _PayslipCard({required this.slip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = NumberFormat('#,##0');
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⚠️ `Wrap` لا `Row` — الصفّ يفيض تحت ~500 بكسل (درس G12).
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${slip.monthLabel} ${slip.year}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (slip.paidByOtherCompany ? AppColors.warn : AppColors.success)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(slip.paymentStatusLabel,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: slip.paidByOtherCompany
                              ? AppColors.warn
                              : AppColors.success)),
                ),
                Text('${n.format(slip.netSalaryIqd)} د.ع',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.gold)),
              ],
            ),
            const Divider(height: 20),
            // تفصيلٌ يُفهم منه الرقم — لا رقمٌ مجرَّد يُصدَّق أو يُشكَّك فيه.
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                _Chip('الراتب الأساس', '${n.format(slip.baseSalary)} ${_cur(slip.currency)}'),
                _Chip('الأيام المستحقّة', '${slip.eligibleDays} / ${slip.workingDays}'),
                if (slip.absenceDays > 0) _Chip('أيام الغياب', '${slip.absenceDays}'),
                if (slip.absenceDeduction > 0)
                  _Chip('خصم الغياب', n.format(slip.absenceDeduction)),
                if ((slip.bonusAmount ?? 0) > 0)
                  _Chip('مكافأة', n.format(slip.bonusAmount!)),
                if ((slip.deductionAmount ?? 0) > 0)
                  _Chip('خصم', n.format(slip.deductionAmount!)),
                if (slip.currency != 'IQD')
                  _Chip('الصافي بالعملة', '${n.format(slip.netSalary)} ${_cur(slip.currency)}'),
                if (slip.paidAt != null)
                  _Chip('تاريخ التسديد',
                      DateFormat('yyyy-MM-dd').format(slip.paidAt!.toLocal())),
              ],
            ),
            const SizedBox(height: 12),
            // 🔴 لا إيصال لِما لم تصرفه هذه الشركة (ADR-028) — والزرّ يُخفى لا يُعطَّل صامتاً.
            if (slip.paidByOtherCompany)
              Text(
                'صرفت هذا الشهر شركةٌ أخرى تعمل فيها — إيصالُه يصدر منها.',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7)),
              )
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => _receipt(context, ref),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('إيصال الاستلام (PDF)'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _cur(String c) => c == 'USD' ? '\$' : 'د.ع';

  Future<void> _receipt(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(apiClientProvider).myReceipt(slip.periodId);
      await downloadBytes(bytes, 'receipt-${slip.year}-${slip.month}.pdf', 'application/pdf');
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

// ═══════════════════════════ عناصر مشتركة ═══════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.gold)),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final String? value;
  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      // ⚠️ `Wrap` لا `Row` — تسميةٌ وقيمةٌ طويلتان تفيضان على الشاشات الضيّقة.
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65))),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(value!,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  const _Chip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
        Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

String _roleLabel(String r) => switch (r) {
      'SuperAdmin' => 'سوبر أدمن',
      'President' => 'رئيس الشركة',
      'Manager' => 'مدير',
      'Employee' => 'موظف',
      _ => 'قارئ',
    };
