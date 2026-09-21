import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

class CompanyEditScreen extends ConsumerStatefulWidget {
  final int companyId;
  const CompanyEditScreen({super.key, required this.companyId});
  @override
  ConsumerState<CompanyEditScreen> createState() => _State();
}

class _State extends ConsumerState<CompanyEditScreen> {
  final _name = TextEditingController();
  final _prefix = TextEditingController();
  final _sigName = TextEditingController();
  final _sigTitle = TextEditingController();
  bool _active = true;
  bool _loading = true;
  bool _busy = false;
  String? _logoKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _prefix.dispose();
    _sigName.dispose();
    _sigTitle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final c = await api.getCompany(widget.companyId);
    _name.text = c.name;
    _prefix.text = c.prefix;
    _sigName.text = c.defaultSignatoryName ?? '';
    _sigTitle.text = c.defaultSignatoryTitle ?? '';
    _active = c.isActive;
    _logoKey = c.logoImageKey;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickLogo() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    if (f.size > 2 * 1024 * 1024) {
      messenger.showSnackBar(const SnackBar(content: Text('الحجم يتجاوز 2MB'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).uploadCompanyLogo(widget.companyId, f.bytes!, f.name);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('تم رفع الشعار بنجاح')));
      if (mounted) setState(() => _busy = false);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _prefix.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).updateCompany(
        widget.companyId,
        _name.text.trim(),
        _prefix.text.trim(),
        _active,
        defaultSignatoryName: _sigName.text.trim(),
        defaultSignatoryTitle: _sigTitle.text.trim(),
      );
      messenger.showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح')));
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      setState(() => _busy = false);
    }
  }

  /// حذفُ الشركة — **بيانٌ بالأرقام أولاً، ثم كتابةُ الاسم** (ADR-047).
  ///
  /// 🔴 **حوارُ التحذير العامّ استُبدل ببيان**: القديم كان يقول «سيُحذف كيان الشركة
  /// وإعداداتها… هل أنت متأكد؟» **بلا رقمٍ واحد** — فالموافقة عليه موافقةٌ على المجهول.
  /// 🔑 **«لا تحذف ما لا تراه.»**
  ///
  /// ⚠️ **والزرّ الأحمر استُبدل بكتابة الاسم**: ضغطةٌ واحدة تقع بالخطأ، وكتابةُ اسمٍ لا تقع.
  /// وهو نمطُ شاشة الاستعادة القائم في النظام أصلاً.
  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);

    // البيان يُقرأ من الخادم — فالأرقام **محسوبةٌ هناك** لا مُخمَّنةٌ هنا.
    CompanyDeletePreview preview;
    setState(() => _busy = true);
    try {
      preview = await api.companyDeletePreview(widget.companyId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => DeleteCompanyDialog(preview: preview),
    );
    if (typed == null || !mounted) return;

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await api.deleteCompany(widget.companyId, confirm: typed);
      messenger.showSnackBar(SnackBar(
          content: Text('حُذفت «${preview.name}» — وأُخذت نسخةٌ احتياطية قبل الحذف.')));
      navigator.pop(); // إغلاق شاشة التعديل
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final apiBaseUrl = kApiBaseUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل تفاصيل الشركة'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _logoKey != null && _logoKey!.isNotEmpty
                              ? NetworkImage('$apiBaseUrl/companies/${widget.companyId}/logo')
                              : null,
                          child: _logoKey == null || _logoKey!.isEmpty ? const Icon(Icons.business, size: 50, color: Colors.grey) : null,
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('شعار الشركة', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              const Text('يظهر الشعار في الشريط العلوي وقائمة المستخدمين.', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _busy ? null : _pickLogo,
                                icon: const Icon(Icons.upload),
                                label: const Text('تغيير الشعار'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 48),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'اسم الشركة', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _prefix,
                      decoration: const InputDecoration(labelText: 'الرمز (DEN)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sigName,
                      decoration: const InputDecoration(labelText: 'الاسم الافتراضي للموقّع (اختياري)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sigTitle,
                      decoration: const InputDecoration(labelText: 'المنصب الافتراضي للموقّع (اختياري)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('نشط'),
                      value: _active,
                      onChanged: _busy ? null : (v) => setState(() => _active = v),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        if (widget.companyId > 0)
                          TextButton.icon(
                            onPressed: _busy ? null : _delete,
                            icon: const Icon(Icons.delete, color: Colors.red),
                            label: const Text('حذف الشركة', style: TextStyle(color: Colors.red)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _busy ? null : () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                          label: const Text('حفظ التعديلات'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// حوارُ حذف الشركة — **بيانٌ بالأرقام وتأكيدٌ بالكتابة** (ADR-047).
///
/// 🔴 **وُلد من حادثةٍ وقعت**: حوارٌ أحمر عامّ بزرّ «نعم» كان يجاور زرّاً آخر أحمر يصفّر
/// القاعدة كلَّها — فضُغط الخطأ مكان الصواب. **والعلاج ليس تحذيراً أشدّ بل إجراءً مختلفاً:**
/// أرقامٌ تُقرأ، واسمٌ يُكتب.
class DeleteCompanyDialog extends StatefulWidget {
  final CompanyDeletePreview preview;
  const DeleteCompanyDialog({super.key, required this.preview});

  @override
  State<DeleteCompanyDialog> createState() => DeleteCompanyDialogState();
}

class DeleteCompanyDialogState extends State<DeleteCompanyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final theme = Theme.of(context);
    final danger = theme.brightness == Brightness.dark
        ? AppColors.dangerDark
        : AppColors.danger;

    // ⚠️ **المطابقة بعد التشذيب** — مسافةٌ لاصقة من اللصق كانت تُفشل اسماً صحيحاً.
    final matches = _ctrl.text.trim() == p.name.trim();
    final rows = p.rows;

    return AlertDialog(
      title: Text('حذف «${p.name}»', style: TextStyle(color: danger)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!p.canDelete) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: danger.withValues(alpha: 0.35)),
                  ),
                  child: Text(p.blockMessage ?? 'لا يمكن حذف هذه الشركة الآن.',
                      style: TextStyle(color: danger, height: 1.7)),
                ),
                const SizedBox(height: 14),
              ],

              // ── البيان: ما سيُمحى فعلاً ──
              Text('ما سيُمحى نهائياً', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              if (rows.isEmpty)
                Text('لا سجلّات — الشركة فارغة.',
                    style: theme.textTheme.bodySmall)
              else
                ...rows.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(r.$3 ? Icons.delete_outline : Icons.circle,
                              size: r.$3 ? 15 : 7,
                              color: theme.textTheme.bodySmall?.color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(r.$1)),
                          Text('${r.$2}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),

              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.backup_outlined, size: 16, color: AppColors.action(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('ستُؤخذ نسخةٌ احتياطية كاملة قبل الحذف تلقائياً.',
                      style: theme.textTheme.bodySmall),
                ),
              ]),

              if (p.canDelete) ...[
                const SizedBox(height: 16),
                Text('للتأكيد اكتب اسم الشركة حرفياً:',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                SelectableText(p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'اسم الشركة',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        // 🔴 **الزرّ معطَّلٌ حتى يطابق الاسم** — والواجهة مرآةٌ للخادم لا حارسٌ ثانٍ:
        //    الخادم يفحص التأكيد أيضاً، فالالتفاف على الحوار لا يحذف شيئاً.
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger),
          onPressed: (p.canDelete && matches)
              ? () => Navigator.pop(context, _ctrl.text)
              : null,
          child: const Text('احذف نهائياً'),
        ),
      ],
    );
  }
}
