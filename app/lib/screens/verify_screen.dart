import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/qr_scan/qr_scan.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

/// شاشة **التحقق من ختم QR** للمستخدم الداخلي (ADR-043 · ADR-061).
///
/// 📷 **خياران متجاوران** (قرار المالك 2026-10-14): **المسح بالكاميرا** — حيّةً في المتصفّح، أو «التقاط صورة للختم» بديلاً —
/// **واللصق** (المحتوى الموقّع أو الرابط). والقراءة على جهاز المستخدم بمكتبةٍ محفوظة داخل النظام؛ الخادم يتلقّى النصّ كاللصق تماماً.
///
/// ⚠️ **الختم المطبوع منذ ADR-043 رابطٌ** (`…/v/{token}`) — والخادم صار يحكم عليه بمنطق صفحة الهاتف نفسه (`IPublicBookVerifier`)،
/// فالنتيجة هنا وعلى الهاتف واحدة: **صادرٌ فعلاً · لم يعُد في السجلّات · تم التلاعب**.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

enum _Mode { camera, paste }

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _ctrl = TextEditingController();
  _Mode _mode = _Mode.paste;
  bool _scanning = false;
  bool _front = false;
  int _cameras = 0;
  QrScanError? _scanError;
  VerifyResult? _result;
  String? _checked;   // النصّ الذي حُكم عليه (لزرّ «فتح صفحة الكتاب»)
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
      _scanError = null;
      _scanning = m == _Mode.camera && _result == null;
    });
  }

  Future<void> _verify(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ref.read(apiClientProvider).verifyQr(text);
      if (!mounted) return;
      setState(() {
        _result = r;
        _checked = text;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onScanned(String text) {
    HapticFeedback.mediumImpact();
    setState(() {
      _scanning = false;
      _ctrl.text = text;
    });
    _verify(text);
  }

  Future<void> _fromPhoto({required bool capture}) async {
    setState(() => _scanError = null);
    try {
      final text = await decodeQrFromPhoto(capture: capture);
      if (text == null || !mounted) return;
      _onScanned(text);
    } on QrScanError catch (e) {
      if (mounted) setState(() => _scanError = e);
    }
  }

  void _again() {
    setState(() {
      _result = null;
      _error = null;
      _scanError = null;
      _ctrl.clear();
      _scanning = _mode == _Mode.camera;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق من ختم QR')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تحقّق من أن الكتاب الذي بين يديك صادرٌ فعلاً من الشركة ولم يُعبث به.',
                  style: TextStyle(fontSize: 14, height: 1.7),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, c) {
                  final narrow = c.maxWidth < 440;
                  final cards = [
                    _ModeCard(
                      key: const Key('verify-mode-camera'),
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'مسح بالكاميرا',
                      subtitle: qrCameraSupported ? 'وجّه الكاميرا إلى الختم فيُقرأ وحده' : 'متاحٌ في نسخة المتصفّح',
                      selected: _mode == _Mode.camera,
                      enabled: qrCameraSupported,
                      onTap: () => _setMode(_Mode.camera),
                    ),
                    _ModeCard(
                      key: const Key('verify-mode-paste'),
                      icon: Icons.content_paste_rounded,
                      title: 'لصق المحتوى أو الرابط',
                      subtitle: 'الرابط المطبوع تحت الختم أو محتواه',
                      selected: _mode == _Mode.paste,
                      onTap: () => _setMode(_Mode.paste),
                    ),
                  ];
                  return narrow
                      ? Column(children: [cards[0], const SizedBox(height: 10), cards[1]])
                      : Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]);
                }),
                const SizedBox(height: 18),
                if (_mode == _Mode.camera) _cameraPanel(context) else _pastePanel(),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 8),
                  const Center(child: Text('جارٍ التحقق…')),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Notice(icon: Icons.cloud_off_rounded, text: _error!, color: AppColors.danger),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  VerdictCard(
                    key: ValueKey(_checked),
                    result: _result!,
                    onAgain: _again,
                    againLabel: _mode == _Mode.camera ? 'مسح ختم آخر' : 'تحقّق من ختم آخر',
                    onOpenPage: _checked != null && _checked!.contains('/v/') ? () => _openPage(_checked!) : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPage(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _pastePanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('verify-input'),
            controller: _ctrl,
            maxLines: 4,
            minLines: 3,
            autofocus: true,
            // الرابط والمحتوى لاتينيّان — يُقرآن من اليسار (كان التلميح يظهر مقلوباً داخل حقلٍ عربيّ)
            textDirection: TextDirection.ltr,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _verify(_ctrl.text),
            decoration: const InputDecoration(
              labelText: 'محتوى الـQR أو الرابط',
              hintText: 'https://…/v/…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('verify-run'),
            onPressed: _busy || _ctrl.text.trim().isEmpty ? null : () => _verify(_ctrl.text),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text(_busy ? 'جارٍ التحقق…' : 'تحقّق'),
          ),
        ],
      );

  Widget _cameraPanel(BuildContext context) {
    final action = AppColors.action(context);
    final err = _scanError;
    final idle = !_scanning && err == null && _result == null && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_scanning && err == null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      QrCameraView(
                        key: const Key('verify-camera'),
                        front: _front,
                        onDetected: _onScanned,
                        onError: (e) => setState(() => _scanError = e),
                        onCameras: (n) => setState(() => _cameras = n),
                      ),
                      // إطارٌ يُري أين يوضع الختم
                      const IgnorePointer(child: CustomPaint(painter: _ScanFrame())),
                      const Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Text(
                            'ضع الختم داخل الإطار',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, shadows: [
                              Shadow(blurRadius: 6, color: Colors.black),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (err != null) _Notice(icon: Icons.no_photography_outlined, text: err.message, color: AppColors.warn),
        if (idle)
          FilledButton.icon(
            key: const Key('verify-camera-start'),
            onPressed: () => setState(() => _scanning = true),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('فتح الكاميرا'),
            style: FilledButton.styleFrom(
              backgroundColor: action,
              foregroundColor: AppColors.onAction(context),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        if (_result == null && !_busy) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_scanning && err == null && _cameras > 1)
                OutlinedButton.icon(
                  key: const Key('verify-camera-switch'),
                  onPressed: () => setState(() => _front = !_front),
                  icon: const Icon(Icons.cameraswitch_rounded, size: 18),
                  label: Text(_front ? 'الكاميرا الخلفية' : 'الكاميرا الأمامية'),
                ),
              if (err == null || err.photoHelps) ...[
                OutlinedButton.icon(
                  key: const Key('verify-photo-capture'),
                  onPressed: () => _fromPhoto(capture: true),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('التقاط صورة للختم'),
                ),
                OutlinedButton.icon(
                  key: const Key('verify-photo-pick'),
                  onPressed: () => _fromPhoto(capture: false),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('اختيار صورة محفوظة'),
                ),
              ],
              if (err != null && err.kind != QrScanFailure.insecure)
                TextButton.icon(
                  key: const Key('verify-camera-retry'),
                  onPressed: () => setState(() {
                    _scanError = null;
                    _scanning = true;
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              if (_scanning && err == null)
                TextButton(
                  key: const Key('verify-camera-stop'),
                  onPressed: () => setState(() => _scanning = false),
                  child: const Text('إيقاف الكاميرا'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// بطاقة الخيار — كبيرةٌ واضحة، والمختار بلون الفعل.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final action = AppColors.action(context);
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? action.withValues(alpha: 0.08) : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? action : theme.dividerColor, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: action.withValues(alpha: selected ? 0.18 : 0.08), shape: BoxShape.circle),
                  child: Icon(icon, color: action, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: selected ? action : null)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زوايا الإطار فوق صورة الكاميرا — وما حوله معتمٌ قليلاً فتتّجه العين إلى الوسط.
class _ScanFrame extends CustomPainter {
  const _ScanFrame();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.62;
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size),
          Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)))),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c.translate(l * dx, 0), p);
      canvas.drawLine(c, c.translate(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.6))),
          ],
        ),
      );
}

/// حكمُ التحقق — **بطاقةٌ كبيرة واضحة** (طلب المالك): ثلاث حالاتٍ بثلاثة ألوانٍ وأيقونات، **بنصّ صفحة الهاتف العامّة نفسه**.
class VerdictCard extends StatelessWidget {
  const VerdictCard({super.key, required this.result, required this.onAgain, required this.againLabel, this.onOpenPage});
  final VerifyResult result;
  final VoidCallback onAgain;
  final String againLabel;
  final VoidCallback? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final v = result.verdict;
    final (color, icon, fallbackTitle, fallbackNote) = switch (v) {
      'Genuine' => (
          dark ? AppColors.successDark : AppColors.success,
          Icons.verified_rounded,
          'تم إصدار هذا الكتاب فعلاً من الشركة',
          'طابِق البيانات أدناه مع الورقة التي بين يديك.',
        ),
      'Withdrawn' => (
          dark ? AppColors.warnDark : AppColors.warn,
          Icons.report_gmailerrorred_rounded,
          'هذا الكتاب لم يعُد ضمن سجلّات الشركة',
          'قد يكون سُحب أو أُلغي. راجِع الجهة المُصدِرة قبل الاعتماد عليه.',
        ),
      _ => (
          dark ? AppColors.dangerDark : AppColors.danger,
          Icons.gpp_bad_rounded,
          'تم التلاعب بالكتاب',
          'هذا الرمز لا يطابق أي كتابٍ صادرٍ عن الشركة. لا تعتمد على هذه الورقة.',
        ),
    };
    final label = switch (v) { 'Genuine' => 'كتابٌ صحيح', 'Withdrawn' => 'انتبه', _ => 'غير صحيح' };
    final versions = result.versionNo ?? 1;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, s, child) =>
          Opacity(opacity: ((s - 0.9) / 0.1).clamp(0.0, 1.0), child: Transform.scale(scale: s, child: child)),
      child: Container(
        key: Key('verify-verdict-$v'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.04)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 2)],
              ),
              child: Icon(icon, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
            const SizedBox(height: 10),
            Text(
              result.title ?? fallbackTitle,
              key: const Key('verify-verdict-title'),
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 21, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(result.note ?? fallbackNote, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.7)),
            if (v != 'Tampered' && (result.number ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [
                    _Row('رقم الكتاب', result.number, strong: true),
                    _Row('التاريخ', result.date),
                    _Row('الجهة', result.entity),
                    _Row('الشركة', result.companyName),
                    // ⚠️ المبلغ في المحتوى الموقّع الخامّ وحده — والرابط بلا مبلغ كصفحة الهاتف (قرار المالك 2026-09-09)
                    _Row('المبلغ بالدينار', result.amountInIqd),
                    if (versions > 1) _Row('الإصدار', 'عُدِّل بعد اعتماده — هذا الإصدار $versions'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('verify-again'),
                  onPressed: onAgain,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(againLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.action(context),
                    foregroundColor: AppColors.onAction(context),
                  ),
                ),
                if (onOpenPage != null && v == 'Genuine')
                  OutlinedButton.icon(
                    key: const Key('verify-open-page'),
                    onPressed: onOpenPage,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('فتح صفحة الكتاب'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  final bool strong;
  const _Row(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty || value == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor))),
          Expanded(
            child: Text(value!,
                style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: strong ? 15.5 : 14)),
          ),
        ],
      ),
    );
  }
}
