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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل القالب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم القالب')),
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
                      Expanded(child: TextField(controller: _mTop, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أعلى'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _mRight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'يمين'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _mBottom, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أسفل'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _mLeft, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'يسار'))),
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
