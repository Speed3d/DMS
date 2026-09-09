import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

/// شاشة **التحقق من ختم QR** للمستخدم الداخلي (ADR-043).
///
/// 🔴 **لماذا لصقٌ لا كاميرا؟** المتحقِّق المقصود بالميزة **جهةٌ خارجية تمسح بكاميرا هاتفها
/// الأصلية** فتفتح صفحةَ الخادم — وهذا هو الغرض كلُّه. وهذه الشاشة للحالة الداخلية: كتابٌ
/// وصلك ورقةً وتريد التأكّد. **وإضافةُ حزمة كاميرا للراحة الداخلية كلفةٌ بلا مقابل** ما دام
/// أيّ هاتفٍ في المكتب يفعلها بلا برنامج.
///
/// ⚠️ **وتقبل الصيغتين**: المحتوى الموقّع الخامّ، **أو الرابط** — فمن يلصق رابطاً لا يعرف
/// أنه ألصق «الشيء الخطأ»، **ورفضُه حارسٌ يخدم الآلة لا الإنسان**.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _ctrl = TextEditingController();
  VerifyResult? _result;
  bool _busy = false;
  String? _error;

  /// رابطٌ عامّ لا محتوىً موقّعاً — يُفتح بصفحته لا بهذه النقطة.
  bool get _looksLikeLink => _ctrl.text.contains('/v/');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() { _busy = true; _error = null; _result = null; });
    try {
      _result = await ref.read(apiClientProvider).verifyQr(text);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق من ختم QR')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الصِق محتوى ختم الـQR أو رابط التحقق المطبوع على الكتاب.',
                  style: TextStyle(fontSize: 13.5, height: 1.7),
                ),
                const SizedBox(height: 4),
                Text(
                  'وأي هاتفٍ يمسح الرمز بكاميرته يفتح صفحة التحقق مباشرةً بلا برنامج.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.7),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ctrl,
                  maxLines: 4,
                  minLines: 3,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _run(),
                  decoration: const InputDecoration(
                    labelText: 'محتوى الـQR أو الرابط',
                    hintText: 'DMS2|… أو https://…/v/…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _ctrl.text.trim().isEmpty ? null : _run,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: Text(_busy ? 'جارٍ التحقق…' : 'تحقّق'),
                ),

                // ⚠️ **تلميحٌ لا رفض**: الرابط يُفتح بصفحته العامّة، والنقطة هنا تفهم
                //    المحتوى الموقّع. فيُقال ذلك بدل أن تُردّ محاولتُه بلا تفسير.
                if (_looksLikeLink) ...[
                  const SizedBox(height: 10),
                  _Hint(
                    icon: Icons.open_in_new_rounded,
                    text: 'هذا رابطُ تحقّق — افتحه في المتصفّح مباشرةً وستظهر النتيجة كاملةً '
                        'مع إمكان تنزيل الكتاب.',
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],

                if (_result != null) ...[
                  const SizedBox(height: 20),
                  _Verdict(result: _result!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.6)),
          ),
        ],
      );
}

/// حكمُ التحقق — **ثلاث حالات لا اثنتان**، مطابقةً لصفحة التحقق العامّة.
class _Verdict extends StatelessWidget {
  final VerifyResult result;
  const _Verdict({required this.result});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔴 **توقيعٌ صحيحٌ لكتابٍ غير موجود ليس «صحيحاً»** — الفرق بين «صادرٌ عنّا» و«كان
    //    صادراً ثم سُحب» معلومةٌ يحتاجها من يقرّر الاعتماد على الورقة.
    final (color, icon, title, note) = !result.isValid
        ? (isDark ? AppColors.dangerDark : AppColors.danger, Icons.gpp_bad_rounded,
            'تم التلاعب بالكتاب', result.message)
        : result.foundInDb
            ? (isDark ? AppColors.successDark : AppColors.success, Icons.verified_rounded,
                'تم إصدار هذا الكتاب فعلاً من الشركة', 'طابِق البيانات أدناه مع الورقة.')
            : (isDark ? AppColors.warnDark : AppColors.warn, Icons.gpp_maybe_rounded,
                'التوقيع صحيح — والكتاب ليس في السجلّ',
                'قد يكون سُحب أو حُذف. راجِع قبل الاعتماد عليه.');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 12.5, height: 1.6)),
          if (result.isValid) ...[
            const Divider(height: 24),
            _Row('رقم الكتاب', result.number),
            _Row('التاريخ', result.date),
            _Row('الجهة', result.entity),
            // ⚠️ **المبلغ يُعرض هنا ولا يُعرض في الصفحة العامّة** — هذه شاشةٌ داخلية
            //    لمستخدمٍ يرى الكتاب كلَّه أصلاً، وتلك صفحةٌ لمن لا يملك النظام.
            _Row('المبلغ بالدينار', result.amountInIqd),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty || value == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value!,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}
