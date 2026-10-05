import 'package:flutter/services.dart';

/// خطوط «الورقة» (ADR-057) — **الملفّات نفسها التي يطبع بها الخادم** (`Dms.Documents/Assets/Fonts`).
///
/// 🔴 **المتصفّح لا يرى خطوط ويندوز**: بلا هذه كانت الورقة تُرسم بخطٍّ بديلٍ أعرض، فـ«الكمية» تنكسر سطرين في المحرّر وتبقى سطراً في
/// الـPDF (كشفه المتصفّح الحقيقيّ) — والورقة وعدُها أن تُري الكتاب كما يُطبع.
///
/// ⚡ **تُحمَّل عند فتح المحرّر لا عند الإقلاع** (~5.4 ميغا)، مرّةً واحدة للجلسة، ثم يحفظها المتصفّح. وإلى أن تصل تُرسم الورقة بالبديل
/// ثم تُعاد بالخطّ الصحيح وحدها. وفشلُ التحميل لا يمنع الكتابة (الطباعة بخطوط الخادم على كل حال).
class PaperFonts {
  PaperFonts._();

  static const _families = {
    'Times New Roman': ['times.ttf', 'timesbd.ttf'],
    'Arial': ['arial.ttf', 'arialbd.ttf'],
    'Amiri': ['Amiri-Regular.ttf', 'Amiri-Bold.ttf'],
    'Cairo': ['Cairo-Regular.ttf', 'Cairo-Bold.ttf'],
  };

  static Future<void>? _loading;

  /// يُحمّل الخطوط مرّةً واحدة — والنداءات التالية تنتظر التحميل نفسه.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      await Future.wait([
        for (final e in _families.entries)
          (FontLoader(e.key)..addFonts(e.value)).load(),
      ]);
    } catch (_) {
      _loading = null;   // محاولةٌ أخرى عند فتح المحرّر التالي
    }
  }
}

extension on FontLoader {
  void addFonts(List<String> files) {
    for (final f in files) {
      addFont(rootBundle.load('assets/fonts/$f'));
    }
  }
}
