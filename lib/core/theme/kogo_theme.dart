import 'package:flutter/material.dart';

import 'kogo_colors.dart';

/// Tema Kogo Belajar mengikuti desain Figma "Learning App": latar gradien
/// lembut, kartu putih membulat (rounded-3xl), teks tebal, dan aksen ungu-pink.
class KogoTheme {
  KogoTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: KogoColors.purple500,
      primary: KogoColors.purple600,
      secondary: KogoColors.pink500,
      tertiary: KogoColors.teal500,
      surface: KogoColors.white,
      onSurface: KogoColors.gray800,
      error: KogoColors.red500,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: KogoColors.orange50,
      textTheme: base.textTheme.apply(bodyColor: KogoColors.gray800, displayColor: KogoColors.gray800),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KogoColors.gray800,
        contentTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KogoColors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: KogoColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: KogoColors.gray800),
        contentTextStyle: const TextStyle(fontSize: 16, height: 1.4, color: KogoColors.gray600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KogoColors.gray100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: KogoColors.purple400, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: KogoColors.red400, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: KogoColors.red500, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KogoColors.gray600),
        errorStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()}),
    );
  }
}
