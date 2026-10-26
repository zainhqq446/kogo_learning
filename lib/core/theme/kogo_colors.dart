import 'package:flutter/material.dart';

/// Palet warna yang diambil langsung dari desain Figma "Learning App"
/// (kelas Tailwind CSS). Nama mengikuti skala Tailwind agar mudah dicocokkan
/// dengan desain, misalnya `orange400` = `orange-400`.
class KogoColors {
  KogoColors._();

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);

  static const red100 = Color(0xFFFEE2E2);
  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);

  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange300 = Color(0xFFFDBA74);
  static const orange400 = Color(0xFFFB923C);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);

  static const amber100 = Color(0xFFFEF3C7);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);

  static const yellow50 = Color(0xFFFEFCE8);
  static const yellow100 = Color(0xFFFEF9C3);
  static const yellow200 = Color(0xFFFEF08A);
  static const yellow300 = Color(0xFFFDE047);
  static const yellow400 = Color(0xFFFACC15);
  static const yellow500 = Color(0xFFEAB308);
  static const yellow600 = Color(0xFFCA8A04);

  static const green100 = Color(0xFFDCFCE7);
  static const green400 = Color(0xFF4ADE80);
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF16A34A);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);

  static const teal100 = Color(0xFFCCFBF1);
  static const teal400 = Color(0xFF2DD4BF);
  static const teal500 = Color(0xFF14B8A6);
  static const teal600 = Color(0xFF0D9488);

  static const cyan100 = Color(0xFFCFFAFE);
  static const cyan400 = Color(0xFF22D3EE);

  static const sky100 = Color(0xFFE0F2FE);

  static const blue50 = Color(0xFFEFF6FF);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);

  static const violet500 = Color(0xFF8B5CF6);

  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple200 = Color(0xFFE9D5FF);
  static const purple400 = Color(0xFFC084FC);
  static const purple500 = Color(0xFFA855F7);
  static const purple600 = Color(0xFF9333EA);
  static const purple700 = Color(0xFF7E22CE);

  static const pink50 = Color(0xFFFDF2F8);
  static const pink100 = Color(0xFFFCE7F3);
  static const pink400 = Color(0xFFF472B6);
  static const pink500 = Color(0xFFEC4899);

  /// Gradien diagonal `bg-gradient-to-br from-X to-Y`.
  static LinearGradient br(Color from, Color to) => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]);

  /// Gradien horizontal `bg-gradient-to-r from-X to-Y`.
  static LinearGradient r(Color from, Color to) => LinearGradient(colors: [from, to]);

  /// Gradien vertikal latar halaman `bg-gradient-to-b from-X (via-Y) to-Z`.
  static LinearGradient b(List<Color> colors) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors);

  static const correct = [green400, emerald500];
  static const wrong = [red400, pink500];
  static const neutralChoice = [blue400, purple400];
  static const selected = [yellow400, orange500];
}
