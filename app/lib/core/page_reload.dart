// معرفةُ إصدار الواجهة المنشور وإعادةُ تحميل الصفحة — عبر الاستيراد الشرطي (ADR-050).
export 'page_reload_io.dart' if (dart.library.html) 'page_reload_web.dart';
