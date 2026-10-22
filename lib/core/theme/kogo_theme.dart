import 'package:flutter/material.dart';

/// Tema Kogo Voice Learning yang disesuaikan untuk anak usia dini dan referensi Figma.
/// Menggunakan warna cerah hangat (cream background, coral primary, leaf green, sky blue),
/// sudut melengkung besar (rounded corners 20-28px), dan tipografi yang sangat mudah dibaca.
class KogoTheme {
  // Palet Warna Utama
  static const Color creamBackground = Color(0xFFFFF9EB);
  static const Color creamSurface = Color(0xFFFFF4DB);
  static const Color pureWhite = Color(0xFFFFFFFF);

  static const Color primaryCoral = Color(0xFFFF6B4A);
  static const Color primaryDarkCoral = Color(0xFFE25232);
  static const Color softPeach = Color(0xFFFFECE6);

  static const Color sunnyYellow = Color(0xFFFFB703);
  static const Color softYellow = Color(0xFFFFF1C2);

  static const Color leafGreen = Color(0xFF48BB78);
  static const Color softGreen = Color(0xFFE6F7ED);

  static const Color skyBlue = Color(0xFF4A90E2);
  static const Color softBlue = Color(0xFFEBF3FC);

  static const Color playfulPurple = Color(0xFF9B51E0);
  static const Color softPurple = Color(0xFFF3E8FC);

  static const Color darkSlate = Color(0xFF2D3748);
  static const Color mediumSlate = Color(0xFF4A5568);
  static const Color lightSlate = Color(0xFF718096);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: creamBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryCoral,
        primary: primaryCoral,
        onPrimary: pureWhite,
        primaryContainer: softPeach,
        onPrimaryContainer: primaryDarkCoral,
        secondary: skyBlue,
        onSecondary: pureWhite,
        secondaryContainer: softBlue,
        onSecondaryContainer: skyBlue,
        tertiary: leafGreen,
        tertiaryContainer: softGreen,
        surface: pureWhite,
        onSurface: darkSlate,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: creamBackground,
        foregroundColor: darkSlate,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: darkSlate,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(
          color: darkSlate,
          size: 26,
        ),
      ),
      cardTheme: CardThemeData(
        color: pureWhite,
        elevation: 2,
        shadowColor: const Color(0x1A000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryCoral,
          foregroundColor: pureWhite,
          elevation: 3,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryCoral,
          side: const BorderSide(color: primaryCoral, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: pureWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        titleTextStyle: const TextStyle(
          color: darkSlate,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: mediumSlate,
          fontSize: 17,
          height: 1.4,
        ),
      ),
    );
  }
}
