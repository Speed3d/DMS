/// مسحُ ختم QR بالكاميرا (ADR-061) — في المتصفّح وحده: `getUserMedia` + مكتبة `jsQR` المحفوظة داخل النظام (`web/jsqr/jsQR.js`)،
/// فلا يُحمَّل شيءٌ من الإنترنت ولا تُرفع صورةٌ إلى الخادم — **القراءة على جهاز المستخدم**، والخادم يتلقّى نصّ الختم كاللصق تماماً.
///
/// وخارج المتصفّح (الاختبارات · نسخة Windows المؤجَّلة) بديلٌ يعلن عدم الدعم.
library;

export 'qr_scan_types.dart';
export 'qr_scan_stub.dart' if (dart.library.js_interop) 'qr_scan_web.dart';
