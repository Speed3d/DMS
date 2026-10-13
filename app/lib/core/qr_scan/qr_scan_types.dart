/// أسبابُ تعذّر قراءة ختم QR (ADR-061) — ولكلٍّ رسالةٌ عربية تقول ما العمل لا ما الخطأ.
enum QrScanFailure {
  /// الكاميرا الحيّة تحتاج رابطاً آمناً (https) — والنظام مفتوحٌ بعنوانٍ داخليّ (http).
  insecure,

  /// المستخدم رفض إذن الكاميرا (أو حظره المتصفّح سابقاً).
  denied,

  /// لا كاميرا في الجهاز.
  noCamera,

  /// الكاميرا يستعملها برنامجٌ آخر.
  busy,

  /// تعذّر تحميل مكتبة القراءة.
  library,

  /// الصورة لا تحوي ختماً مقروءاً.
  notFound,

  /// المنصّة لا تدعم الكاميرا (غير المتصفّح).
  unsupported,

  other,
}

class QrScanError implements Exception {
  const QrScanError(this.kind, [this.detail]);
  final QrScanFailure kind;
  final String? detail;

  /// هل يفيد هنا «التقاط صورة للختم» بديلاً؟
  bool get photoHelps => kind != QrScanFailure.library && kind != QrScanFailure.unsupported;

  String get message => switch (kind) {
        QrScanFailure.insecure =>
          'الكاميرا الحيّة تحتاج رابطاً آمناً (https) — افتح النظام عبر الدومين، أو استعمل «التقاط صورة للختم».',
        QrScanFailure.denied =>
          'لم يُسمح للمتصفّح باستعمال الكاميرا. اسمح بها من رمز القفل بجانب العنوان ثم أعد المحاولة — أو استعمل «التقاط صورة للختم».',
        QrScanFailure.noCamera => 'لم يُعثر على كاميرا في هذا الجهاز — استعمل «اختيار صورة محفوظة» أو الصق الرابط.',
        QrScanFailure.busy => 'الكاميرا مشغولةٌ ببرنامجٍ آخر. أغلقه ثم أعد المحاولة.',
        QrScanFailure.library => 'تعذّر تحميل قارئ الختم. أعد تحميل الصفحة ثم حاول مجدداً.',
        QrScanFailure.notFound =>
          'لم يُعثر على ختم QR واضح في الصورة. قرّب الكاميرا من الختم واجعله في وسط الصورة وبإضاءةٍ جيدة.',
        QrScanFailure.unsupported => 'المسح بالكاميرا متاحٌ في نسخة المتصفّح — الصق محتوى الختم أو رابطه.',
        QrScanFailure.other => 'تعذّر تشغيل الكاميرا${detail == null ? '' : ' ($detail)'}. أعد المحاولة أو استعمل «التقاط صورة للختم».',
      };

  @override
  String toString() => message;
}
