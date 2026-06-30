import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  final bool forced;
  const ChangePasswordScreen({super.key, this.forced = false});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _State();
}

class _State extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_next.text.length < 8) { setState(() => _error = 'كلمة المرور يجب ألا تقل عن 8 أحرف.'); return; }
    if (_next.text != _confirm.text) { setState(() => _error = 'تأكيد كلمة المرور غير مطابق.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(apiClientProvider).changePassword(_current.text, _next.text);
      await ref.read(sessionProvider.notifier).clearMustChange();
      if (mounted && !widget.forced) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور.')));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة المرور'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced)
            TextButton(
              onPressed: () => ref.read(sessionProvider.notifier).logout(),
              child: const Text('خروج', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.forced)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('يجب تغيير كلمة المرور المؤقتة قبل المتابعة.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الحالية')),
                const SizedBox(height: 12),
                TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
                const SizedBox(height: 12),
                TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
                if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
