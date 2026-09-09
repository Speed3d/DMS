import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Hint: هذا المزود مسؤول عن تبديل المظهر بين الفاتح والداكن
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void toggle() => state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
}
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Hint: الألوان الأساسية الخاصة بالتصميم الجديد (Tokens)
class AppColors {
  // ألوان الـ Navy (الأساس)
  static const Color navy = Color(0xFF15315C);
  static const Color navyDeep = Color(0xFF0C1B33);
  static const Color navyDark = Color(0xFF16294A);
  static const Color navyDeepDark = Color(0xFF0A1428);

  // ألوان الـ Gold (التمييز)
  static const Color gold = Color(0xFFBE9A47);
  static const Color goldBright = Color(0xFFD6B158);
  static const Color goldDark = Color(0xFFD9B458);
  static const Color goldBrightDark = Color(0xFFEDCC73);

  // الحالة (Status)
  static const Color success = Color(0xFF178A5B);
  static const Color successDark = Color(0xFF34B27B);
  
  static const Color warn = Color(0xFFBE7A12);
  static const Color warnDark = Color(0xFFE0A23C);
  
  static const Color danger = Color(0xFFC13B33);
  static const Color dangerDark = Color(0xFFE2655C);

  /// 🔴 **لونُ الفعل — يعرف الوضع** (بلاغ المالك 2026-09-09).
  ///
  /// كان `navyDeep` (`#0C1B33`) مكتوباً صراحةً في **٨٢ موضعاً بأربعة وعشرين ملفاً**:
  /// نصوصُ أزرارٍ وإطاراتُها وأيقونات. وعلى الخلفية الليلية (`#070E1C`) تباينُه ≈ **1.1:1**
  /// — أي **غير مرئيّ عملياً**، وهو ما اشتكى منه المالك في «إحالة لقسم» و«استيراد دفعة»
  /// و«رفع مرفق» و«سجل الإصدارات».
  ///
  /// ✅ **كحليٌّ نهاراً كما كان بالضبط، وذهبيٌّ فاتح ليلاً** (قرار المالك: هويّة الشركة).
  /// ⚠️ **ولا يُستعمل للخلفيات الداكنة المقصودة** (تدرّج شاشة اختيار الشركة · خلفية
  /// التنبيهات) — تلك كحليّةٌ في الوضعين عمداً.
  static Color action(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? goldBrightDark : navyDeep;

  /// نصُّ ما يعلو [action] حين يكون خلفيةً — **يُقلب معه** فلا يبقى فاتحاً على فاتح.
  static Color onAction(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? navyDeepDark : Colors.white;
}

class AppTheme {
  // Hint: النمط الفاتح (Light Theme)
  static ThemeData get light {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFE9EDF4),
      primaryColor: AppColors.navy,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        secondary: AppColors.gold,
        surface: const Color(0xFFFFFFFF),
        surfaceContainerHighest: const Color(0xFFF4F6FA), // surface-2
        surfaceContainer: const Color(0xFFECEFF5), // surface-3
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFF0F1D38),
        displayColor: const Color(0xFF0F1D38),
      ),
      dividerColor: const Color(0xFFE2E7EF), // border
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF0F1D38),
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  // Hint: النمط الداكن (Dark Theme)
  //
  // 🔴 **لماذا أُعيد ضبطه كاملاً (بلاغ المالك 2026-09-09)؟** كان يُعيد تعريف **خمسة أدوار
  //    فقط** (`primary` · `secondary` · `surface` · `surfaceContainer*` · `error`)
  //    و**تبقى البقية على لوحة Material البنفسجية**. والنتيجة مقيسة لا مُخمَّنة:
  //    `onPrimary = #381E72` بنفسجيّ داكن — **وهو نصُّ زرّ «حفظ كمسودة نهائية»**؛
  //    و`primaryContainer = #4F378B`، و`inversePrimary = #6750A4`، و`tertiary = #EFB8C8`
  //    ورديّ، و`surfaceContainerLow/High` رماديّان بنفسجيّان **بينما أسطح التطبيق كحليّة** —
  //    وهو سببُ أن الحوارات والقوائم السفلية تبدو غريبةً عن التصميم.
  //
  // 🔴 **و`primary` كان أغمق من الخلفية**: `#16294A` على `#070E1C` بتباينٍ ≈ **1.2:1**،
  //    وكلُّ `TextButton`/`OutlinedButton` بلا لونٍ صريح يأخذه — فكان «سجل الإصدارات»
  //    و«إلغاء» شبه غير مرئيَّين. **وقاعدة Material أن `primary` في الداكن لونٌ فاتح.**
  //
  // ✅ **والقرار (المالك):** العنصر التفاعلي ليلاً **ذهبيٌّ فاتح** — هويّة الشركة نفسها
  //    (كحليّ + ذهبيّ)، وتباينُه ≈ 11:1. **والوضع النهاري لم يُمسّ بحرف.**
  static ThemeData get dark {
    final base = ThemeData.dark();

    const gold = AppColors.goldBrightDark;   // #EDCC73 — الفعل والتمييز
    const onGold = AppColors.navyDeepDark;   // #0A1428 — النصّ فوق الذهبي
    const ink = Color(0xFFE8EEF9);           // النصّ الأساسي
    const inkMuted = Color(0xFFA9BBD9);      // النصّ الثانوي (لون القائمة الجانبية نفسه)
    const surface = Color(0xFF0F1B30);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF070E1C),
      primaryColor: AppColors.navyDark,
      colorScheme: base.colorScheme.copyWith(
        primary: gold,
        onPrimary: onGold,
        // الحاويات تبقى **كحليّة** ومحتواها ذهبيّ — فالذهب لهجةٌ لا سطح.
        primaryContainer: const Color(0xFF17294A),
        onPrimaryContainer: gold,

        secondary: AppColors.goldDark,
        onSecondary: onGold,
        secondaryContainer: const Color(0xFF17294A),
        onSecondaryContainer: ink,

        // لهجةٌ ثالثة **زرقاء** لا وردية — للحالات المحايدة.
        tertiary: const Color(0xFF8FB6E8),
        onTertiary: onGold,
        tertiaryContainer: const Color(0xFF13223C),
        onTertiaryContainer: const Color(0xFFDCE7FA),

        error: AppColors.dangerDark,
        onError: const Color(0xFF2A0B08),
        errorContainer: const Color(0xFF4A1712),
        onErrorContainer: const Color(0xFFFFDAD6),

        surface: surface,
        onSurface: ink,
        // ⚠️ **`surfaceContainer` و`…Highest` تُتركان كما كانتا** — شاشاتٌ قائمة تبني
        //    عليهما، وتغييرُهما يُبدّل مظهراً يعمل. تُضاف الدرجات الناقصة فقط.
        surfaceContainerLowest: const Color(0xFF070E1C),
        surfaceContainerLow: const Color(0xFF0C1526),
        surfaceContainerHighest: const Color(0xFF13223C), // surface-2
        surfaceContainer: const Color(0xFF17294A), // surface-3
        surfaceContainerHigh: const Color(0xFF1B3155),
        onSurfaceVariant: inkMuted,

        outline: const Color(0xFF3A4E73),
        outlineVariant: const Color(0xFF22334F),
        inversePrimary: AppColors.navy,
        inverseSurface: ink,
        onInverseSurface: surface,
        // ⚠️ **بلا صبغةٍ ذهبية على الأسطح المرتفعة** — الذهب لهجةُ فعلٍ لا لونُ بطاقة.
        surfaceTint: Colors.transparent,
      ),
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      dividerColor: const Color(0xFF1E2F4E), // border
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
      ),

      // ── الأسطح المنبثقة: كحليّةٌ كبقيّة التطبيق لا رماديّةٌ بنفسجية ──
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),

      // ── الأزرار: **الذهبي هو الفعل** ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: BorderSide(color: gold.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: onGold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF17294A),
          foregroundColor: gold,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),

      // ── التبويبات والحقول والشرائح ──
      tabBarTheme: const TabBarThemeData(
        labelColor: gold,
        unselectedLabelColor: inkMuted,
        indicatorColor: gold,
        dividerColor: Color(0xFF1E2F4E),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: inkMuted),
        hintStyle: TextStyle(color: Color(0xFF7F93B8)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: gold, width: 1.6),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFF13223C),
        selectedColor: gold.withValues(alpha: 0.22),
        side: const BorderSide(color: Color(0xFF22334F)),
        labelStyle: const TextStyle(color: ink),
        secondaryLabelStyle: const TextStyle(color: gold),
      ),
      listTileTheme: const ListTileThemeData(iconColor: inkMuted, textColor: ink),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: gold),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF17294A),
        contentTextStyle: TextStyle(color: ink),
        actionTextColor: gold,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF1E2F4E)),
    );
  }
}
