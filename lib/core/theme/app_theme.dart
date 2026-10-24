import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Aptigen brand blue (`#0a6ed1`, the desktop app's primary action color)
/// used as the Material 3 seed so this app stays visually on-brand with
/// erp/desktop while keeping the sibling Flutter app's seed-color technique.
class AppColors {
  static const brand = Color(0xFF0A6ED1);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF0EA5E9);

  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate400 = Color(0xFF94A3B8);
  static const slate600 = Color(0xFF475569);
  static const slate900 = Color(0xFF0F172A);

  /// App-wide page background — the same tones the Store / Sell screens use
  /// (MarketPalette.bg), so every module shares one canvas.
  static const pageLight = Color(0xFFF5F6F7);
  static const pageDark = Color(0xFF12171C);
  static const cardLight = Colors.white;
  static const cardDark = Color(0xFF1D232A);
  static Color page(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? pageDark : pageLight;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: AppColors.cardLight),
      scaffoldBackgroundColor: AppColors.pageLight,
      canvasColor: AppColors.pageLight,
      cardColor: AppColors.cardLight,
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.slate400.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: AppColors.cardDark),
      scaffoldBackgroundColor: AppColors.pageDark,
      canvasColor: AppColors.pageDark,
      cardColor: AppColors.cardDark,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
    );
  }
}
