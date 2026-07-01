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
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF070E1C),
      primaryColor: AppColors.navyDark,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navyDark,
        secondary: AppColors.goldDark,
        surface: const Color(0xFF0F1B30),
        surfaceContainerHighest: const Color(0xFF13223C), // surface-2
        surfaceContainer: const Color(0xFF17294A), // surface-3
        error: AppColors.dangerDark,
      ),
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFFE8EEF9),
        displayColor: const Color(0xFFE8EEF9),
      ),
      dividerColor: const Color(0xFF1E2F4E), // border
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1B30),
        foregroundColor: Color(0xFFE8EEF9),
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
