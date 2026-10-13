import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'qr_scan_types.dart';

// ─────────────────────────── jsQR (web/jsqr/jsQR.js — Apache-2.0) ───────────────────────────

@JS('jsQR')
external _QrCode? _jsQR(JSUint8ClampedArray data, int width, int height, JSObject options);

extension type _QrCode._(JSObject _) implements JSObject {
  external String get data;
}

Future<void>? _loading;

/// تُحمَّل المكتبة عند أوّل مسحٍ لا مع كل صفحة — ومن مجلد النظام نفسه، **لا من الإنترنت**.
Future<void> _ensureJsQr() {
  if (globalContext.has('jsQR')) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = 'jsqr/jsQR.js'
      ..async = true;
    script.onload = ((web.Event _) => done.complete()).toJS;
    script.onerror = ((web.Event _) {
      _loading = null;   // محاولةٌ لاحقة تُعيد التحميل
      done.completeError(const QrScanError(QrScanFailure.library));
    }).toJS;
    web.document.head!.append(script);
    return done.future;
  }();
}

/// يقرأ الختم من الإطار المرسوم على اللوحة — و`null` إن لم يوجد.
String? _decode(web.CanvasRenderingContext2D ctx, int w, int h, {required bool thorough}) {
  final image = ctx.getImageData(0, 0, w, h);
  final options = JSObject()..setProperty('inversionAttempts'.toJS, (thorough ? 'attemptBoth' : 'dontInvert').toJS);
  final text = _jsQR(image.data, w, h, options)?.data;
  return text == null || text.trim().isEmpty ? null : text.trim();
}

web.CanvasRenderingContext2D _context(web.HTMLCanvasElement canvas) =>
    canvas.getContext('2d', {'willReadFrequently': true}.jsify()) as web.CanvasRenderingContext2D;

/// اسم خطأ المتصفّح — DOMException يُرمى كائناً لا رسالة.
QrScanError _cameraError(Object e) {
  final s = e.toString();
  if (s.contains('NotAllowedError') || s.contains('PermissionDenied') || s.contains('SecurityError')) {
    return const QrScanError(QrScanFailure.denied);
  }
  if (s.contains('NotFoundError') || s.contains('DevicesNotFound') || s.contains('OverconstrainedError')) {
    return const QrScanError(QrScanFailure.noCamera);
  }
  if (s.contains('NotReadableError') || s.contains('TrackStartError') || s.contains('AbortError')) {
    return const QrScanError(QrScanFailure.busy);
  }
  if (e is QrScanError) return e;
  return QrScanError(QrScanFailure.other, s.length > 80 ? s.substring(0, 80) : s);
}

// ─────────────────────────── الواجهة العامّة ───────────────────────────

/// المتصفّح يدعم الكاميرا (والرابط الآمن يُفحص عند التشغيل لتُقال رسالته).
bool get qrCameraSupported => true;

/// «التقاط صورة للختم» ([capture]: كاميرا الهاتف مباشرةً) أو «اختيار صورة محفوظة» — ثم قراءتها على الجهاز.
/// `null` إن ألغى المستخدم. ويعمل **بلا https** (حقل ملفٍّ لا بثٌّ حيّ) — فهو البديل حين تُرفض الكاميرا الحيّة.
///
/// 🔴 **الحقل يُنقر قبل أيّ انتظار**: سفاري الآيفون لا يفتح الملفّات إلا من داخل لمسة المستخدم نفسها — وانتظارُ تحميل
/// المكتبة قبل النقر يقطع تلك السلسلة فلا يحدث شيء.
Future<String?> decodeQrFromPhoto({required bool capture}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  if (capture) input.setAttribute('capture', 'environment');
  input.style.display = 'none';
  web.document.body!.append(input);
  final picked = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    if (!picked.isCompleted) picked.complete(input.files?.item(0));
  }).toJS;
  input.addEventListener('cancel', ((web.Event _) {
    if (!picked.isCompleted) picked.complete(null);
  }).toJS);
  input.click();

  final web.File? file;
  try {
    file = await picked.future;
  } finally {
    input.remove();
  }
  if (file == null) return null;

  await _ensureJsQr();
  final url = web.URL.createObjectURL(file);
  try {
    final img = web.HTMLImageElement()..src = url;
    await img.decode().toDart;
    final canvas = web.HTMLCanvasElement();
    final ctx = _context(canvas);
    // صورة الهاتف كبيرة (12 ميغابكسل) — تُصغَّر، وتُجرَّب بمقاسين: الختمُ الصغير في صورةٍ كبيرة يُقرأ أحياناً بالأصغر
    for (final max in [1600, 900]) {
      final scale = math.min(1.0, max / math.max(img.naturalWidth, img.naturalHeight));
      final w = math.max(1, (img.naturalWidth * scale).round()), h = math.max(1, (img.naturalHeight * scale).round());
      canvas
        ..width = w
        ..height = h;
      ctx.drawImage(img, 0, 0, w, h);
      final text = _decode(ctx, w, h, thorough: true);
      if (text != null) return text;
    }
    throw const QrScanError(QrScanFailure.notFound);
  } on QrScanError {
    rethrow;
  } catch (_) {
    throw const QrScanError(QrScanFailure.notFound);
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

/// الكاميرا الحيّة: صورتها في إطار، وتُقرأ أربع مرّاتٍ في الثانية حتى يظهر ختم — ثم تُطفأ وحدها.
class QrCameraView extends StatefulWidget {
  const QrCameraView({super.key, required this.onDetected, required this.onError, this.onCameras, this.front = false});
  final ValueChanged<String> onDetected;
  final ValueChanged<QrScanError> onError;
  final ValueChanged<int>? onCameras;
  final bool front;

  @override
  State<QrCameraView> createState() => _QrCameraViewState();
}

class _QrCameraViewState extends State<QrCameraView> {
  static var _seq = 0;
  late final String _viewType = 'dms-qr-camera-${_seq++}';
  final _video = web.HTMLVideoElement();
  final _canvas = web.HTMLCanvasElement();
  web.MediaStream? _stream;
  Timer? _timer;
  bool _done = false;
  int _start = 0;   // يُبطل تشغيلاً سابقاً إن تبدّلت الكاميرا قبل أن يكتمل

  @override
  void initState() {
    super.initState();
    _video
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')   // 🔴 آيفون: بدونها تُفتح الكاميرا ملءَ الشاشة خارج الصفحة
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.pointerEvents = 'none';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
    _run();
  }

  @override
  void didUpdateWidget(QrCameraView old) {
    super.didUpdateWidget(old);
    if (old.front != widget.front) _run();
  }

  Future<void> _run() async {
    final my = ++_start;
    _stop();
    _video.style.transform = widget.front ? 'scaleX(-1)' : '';   // الأمامية كالمرآة كما يتوقّعها المستخدم
    try {
      if (!web.window.isSecureContext) throw const QrScanError(QrScanFailure.insecure);
      final library = _ensureJsQr();
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(
            video: {
              'facingMode': {'ideal': widget.front ? 'user' : 'environment'},
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }.jsify()!,
            audio: false.toJS,
          ))
          .toDart;
      if (!mounted || my != _start) {
        _stopStream(stream);
        return;
      }
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      await library;
      _countCameras();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    } catch (e) {
      if (mounted && my == _start) widget.onError(_cameraError(e));
    }
  }

  Future<void> _countCameras() async {
    final cb = widget.onCameras;
    if (cb == null) return;
    try {
      final devices = (await web.window.navigator.mediaDevices.enumerateDevices().toDart).toDart;
      if (mounted) cb(devices.where((d) => d.kind == 'videoinput').length);
    } catch (_) {/* التبديل يغيب — لا شيء أكثر */}
  }

  void _tick() {
    if (_done || _video.readyState < 2) return;   // HAVE_CURRENT_DATA
    final vw = _video.videoWidth, vh = _video.videoHeight;
    if (vw == 0 || vh == 0) return;
    // يكفي 720 للختم المطبوع — والأكبر يُبطئ الهاتف بلا فائدة
    final scale = math.min(1.0, 720 / math.max(vw, vh));
    final w = (vw * scale).round(), h = (vh * scale).round();
    _canvas
      ..width = w
      ..height = h;
    final ctx = _context(_canvas);
    ctx.drawImage(_video, 0, 0, w, h);
    final text = _decode(ctx, w, h, thorough: false);
    if (text == null) return;
    _done = true;
    _stop();
    try {
      web.window.navigator.vibrate(80.toJS);   // أندرويد: نبضةٌ تقول «قُرئ» — وما لا يدعمها يتجاهلها
    } catch (_) {}
    widget.onDetected(text);
  }

  void _stopStream(web.MediaStream s) {
    for (final t in s.getTracks().toDart) {
      t.stop();
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    final s = _stream;
    _stream = null;
    if (s != null) _stopStream(s);   // 🔐 ضوء الكاميرا ينطفئ فور القراءة أو الإغلاق — لا تبقى تعمل في الخلفية
    _video.srcObject = null;
  }

  @override
  void dispose() {
    _start++;
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
