import 'package:flutter/material.dart';

class AppTheme {
  // ── Fresh White + Vivid Blue palette ────────────────────────────────────
  static const Color primaryBlue  = Color(0xFF2563EB); // Vivid Blue
  static const Color lightBlue    = Color(0xFF60A5FA); // Soft Blue
  static const Color accentBlue   = Color(0xFF0EA5E9); // Sky Blue
  static const Color successGreen = Color(0xFF10B981); // Emerald
  static const Color warningAmber = Color(0xFFF59E0B); // Amber
  static const Color errorRed     = Color(0xFFEF4444); // Red

  static const Color bgWhite      = Color(0xFFFFFFFF); // Pure White
  static const Color bgSurface    = Color(0xFFF0F7FF); // Blue-tint white
  static const Color bgCard       = Color(0xFFFFFFFF); // White card
  static const Color bgInput      = Color(0xFFF4F8FF); // Input fill

  static const Color textDark     = Color(0xFF1E293B); // Slate 800
  static const Color textMid      = Color(0xFF64748B); // Slate 500
  static const Color textLight    = Color(0xFF94A3B8); // Slate 400
  static const Color divider      = Color(0xFFE2E8F0); // Slate 200

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: bgWhite,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: accentBlue,
        surface: bgCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textDark, fontWeight: FontWeight.w800,
          fontFamily: 'Outfit', fontSize: 28,
        ),
        displayMedium: TextStyle(
          color: textDark, fontWeight: FontWeight.w700,
          fontFamily: 'Outfit', fontSize: 22,
        ),
        titleLarge: TextStyle(
          color: textDark, fontWeight: FontWeight.w600,
          fontFamily: 'Outfit', fontSize: 18,
        ),
        titleMedium: TextStyle(
          color: textDark, fontWeight: FontWeight.w600,
          fontFamily: 'Inter', fontSize: 15,
        ),
        bodyLarge: TextStyle(
          color: textDark, fontFamily: 'Inter', fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: textMid, fontFamily: 'Inter', fontSize: 13,
        ),
        labelLarge: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600,
          fontFamily: 'Inter', fontSize: 15,
        ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: divider, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgWhite,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: textDark),
        titleTextStyle: TextStyle(
          color: textDark, fontFamily: 'Outfit',
          fontSize: 20, fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        hintStyle: const TextStyle(color: textLight, fontFamily: 'Inter', fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          side: const BorderSide(color: primaryBlue),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          textStyle: const TextStyle(
            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14,
          ),
        ),
      ),
      dividerColor: divider,
      iconTheme: const IconThemeData(color: textMid),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBlue,
      ),
    );
  }
}
