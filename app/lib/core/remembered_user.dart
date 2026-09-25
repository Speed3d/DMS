import 'package:shared_preferences/shared_preferences.dart';

/// «تذكّرني» في شاشة الدخول — يحفظ **اسم المستخدم وحده** على هذا الجهاز (قرار المالك 2026-09-25).
///
/// ⚠️ **كان المربّع لا يفعل شيئاً** — قيمته لا تُقرأ في أيّ موضع (مُبلَّغٌ في ADR-053).
/// 🔐 **الاسم لا كلمة المرور** — والجلسة نفسها محفوظةٌ أصلاً حتى يخرج صاحبها. **ويُمحى الاسم** إن
/// دخل صاحبه والمربّع غير مؤشَّر، فجهازٌ عامّ لا يحتفظ باسم مَن لم يطلب ذلك.
class RememberedUser {
  static const _key = 'dms_remembered_username';

  /// الاسم المحفوظ — أو `null`.
  ///
  /// ⚠️ **تخزينٌ معطَّل لا يمنع الدخول** (تصفّحٌ خاص · متصفّحٌ يحجبه) — يعود `null` بصمت.
  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// بعد دخولٍ ناجح: يحفظ الاسم إن طُلب، **ويمحوه إن لم يُطلب**.
  /// ⚠️ **وفشلُ الحفظ لا يُفشل الدخول** — «تذكّرني» راحةٌ لا شرط.
  static Future<void> afterLogin(String username, {required bool remember}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = username.trim();
      if (remember && name.isNotEmpty) {
        await prefs.setString(_key, name);
      } else {
        await prefs.remove(_key);
      }
    } catch (_) {
      // لا شيء — الدخول يمضي.
    }
  }
}
