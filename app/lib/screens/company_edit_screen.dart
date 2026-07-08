import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';

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
      if (mounted) Navigator.pop(context);
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
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
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
