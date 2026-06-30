import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.login(_user.text.trim(), _pass.text);
      await ref.read(sessionProvider.notifier).setAuth(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'تعذّر تسجيل الدخول. تأكد من تشغيل الخادم.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.description, size: 56, color: Color(0xFF0B3D91)),
                    const SizedBox(height: 12),
                    Text('نظام إدارة الوثائق',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const Text('DEN LAND', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _user,
                      decoration: const InputDecoration(
                          labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تسجيل الدخول'),
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
