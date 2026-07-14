import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';

class TemplateEditScreen extends ConsumerStatefulWidget {
  final int templateId;
  const TemplateEditScreen({super.key, required this.templateId});
  @override
  ConsumerState<TemplateEditScreen> createState() => _State();
}

class _State extends ConsumerState<TemplateEditScreen> {
  final _name = TextEditingController();
  int _opacity = 8;
  final _mTop = TextEditingController();
  final _mRight = TextEditingController();
  final _mBottom = TextEditingController();
  final _mLeft = TextEditingController();
  bool _active = true;
  bool _loading = true;
  bool _busy = false;
  final Map<String, Uint8List?> _images = {'header': null, 'footer': null, 'watermark': null};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _mTop.dispose(); _mRight.dispose(); _mBottom.dispose(); _mLeft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final t = await api.getTemplate(widget.templateId);
    _name.text = t.name;
    _opacity = t.watermarkOpacity;
    _mTop.text = '${t.marginTop}';
    _mRight.text = '${t.marginRight}';
    _mBottom.text = '${t.marginBottom}';
    _mLeft.text = '${t.marginLeft}';
    _active = t.isActive;
    for (final kind in _images.keys.toList()) {
      _images[kind] = await api.getTemplateImage(widget.templateId, kind);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickImage(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    if (!(f.name.toLowerCase().endsWith('.png') ||
        f.name.toLowerCase().endsWith('.jpg') ||
        f.name.toLowerCase().endsWith('.jpeg'))) {
      messenger.showSnackBar(const SnackBar(content: Text('الصورة يجب أن تكون PNG أو JPEG.'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).uploadTemplateImage(widget.templateId, kind, f.bytes!, f.name);
      final img = await ref.read(apiClientProvider).getTemplateImage(widget.templateId, kind);
      if (mounted) setState(() => _images[kind] = img);
      messenger.showSnackBar(const SnackBar(content: Text('تم رفع الصورة.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).updateTemplate(widget.templateId, {
        'name': _name.text.trim(),
        'watermarkOpacity': _opacity,
        'marginTop': int.tryParse(_mTop.text) ?? 24,
        'marginRight': int.tryParse(_mRight.text) ?? 40,
        'marginBottom': int.tryParse(_mBottom.text) ?? 24,
        'marginLeft': int.tryParse(_mLeft.text) ?? 40,
        'pageSize': 'A4',
        'fontFamily': 'Amiri',
        'isActive': _active,
      });
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('تم حفظ القالب.')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTemplate() async {
    final api = ref.read(apiClientProvider);
    setState(() => _busy = true);
    try {
      final usageCount = await api.getTemplateUsage(widget.templateId);
      if (!mounted) return;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.red)),
          content: Text('يُستخدم هذا القالب في $usageCount كتاب/كتب.\nإذا قمت بحذفه، أي تعديل مستقبلي على هذه الكتب سيكون بدون قالب.\nهل أنت متأكد من الحذف؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true), 
              child: const Text('نعم، احذف القالب')
            ),
          ],
        )
      );

      if (confirm == true) {
        setState(() => _busy = true);
        await api.deleteTemplate(widget.templateId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف بنجاح.')));
          Navigator.pop(context, true);
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: ${e.message}'), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف غير متوقع: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل القالب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'حذف القالب',
            onPressed: _busy ? null : _deleteTemplate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // لوحة التحكم وتعديل القيم
                Expanded(
                  flex: 1,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'اسم القالب'),
                        onChanged: (_) => setState((){}),
                      ),
                      const SizedBox(height: 16),
                      Text('شفافية العلامة المائية: $_opacity%'),
                      Slider(
                        value: _opacity.toDouble(),
                        min: 0, max: 100, divisions: 100, label: '$_opacity%',
                        onChanged: (v) => setState(() => _opacity = v.round()),
                      ),
                      const SizedBox(height: 8),
                      const Text('الهوامش (نقاط)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _mTop, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أعلى'), onChanged: (_) => setState((){}))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _mRight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'يمين'), onChanged: (_) => setState((){}))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _mBottom, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أسفل'), onChanged: (_) => setState((){}))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _mLeft, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'يسار'), onChanged: (_) => setState((){}))),
                      ]),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        title: const Text('مُفعّل'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 32),
                      const Text('صور القالب', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _imageRow('الهيدر', 'header'),
                      _imageRow('الفوتر', 'footer'),
                      _imageRow('العلامة المائية', 'watermark'),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(_busy ? 'جارٍ...' : 'حفظ'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: Colors.black12),
                // المعاينة الحية المباشرة (A4 Simulation)
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: AspectRatio(
                      aspectRatio: 1 / 1.414,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2)],
                        ),
                        child: Stack(
                          children: [
                            if (_images['watermark'] != null)
                              Center(
                                child: Opacity(
                                  opacity: _opacity / 100.0,
                                  child: Image.memory(_images['watermark']!, fit: BoxFit.contain),
                                ),
                              ),
                            if (_images['header'] != null)
                              Positioned(
                                top: 0, left: 0, right: 0,
                                child: Image.memory(_images['header']!, fit: BoxFit.fitWidth),
                              ),
                            if (_images['footer'] != null)
                              Positioned(
                                bottom: 0, left: 0, right: 0,
                                child: Image.memory(_images['footer']!, fit: BoxFit.fitWidth),
                              ),
                            Positioned(
                              top: (double.tryParse(_mTop.text) ?? 24),
                              right: (double.tryParse(_mRight.text) ?? 40),
                              bottom: (double.tryParse(_mBottom.text) ?? 24),
                              left: (double.tryParse(_mLeft.text) ?? 40),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.5), style: BorderStyle.solid),
                                  color: Colors.blue.withValues(alpha: 0.05),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'هنا مساحة النص الفعلي\nتتأثر مباشرة بالهوامش التي تحددها.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.blue, fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _imageRow(String label, String kind) {
    final img = _images[kind];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Container(
            width: 140, height: 70,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            alignment: Alignment.center,
            child: img != null
                ? Image.memory(img, fit: BoxFit.contain)
                : const Text('لا توجد', style: TextStyle(color: Colors.black45)),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickImage(kind),
            icon: const Icon(Icons.upload),
            label: const Text('اختيار صورة'),
          ),
        ],
      ),
    );
  }
}
