import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> loadThemeMode() async {
    themeModeNotifier.value = await StorageService.getThemeMode();
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    await StorageService.saveThemeMode(mode);
  }

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

  // ── Blackberry-Violet + Pure-Black Dark palette ─────────────────────────
  static const Color blackberryCream  = Color(0xFF472A44);
  static const Color midnightViolet   = Color(0xFF3F253C);
  static const Color midnightViolet2  = Color(0xFF372135);
  static const Color midnightViolet3  = Color(0xFF2F1C2D);
  static const Color midnightViolet4  = Color(0xFF271726);
  static const Color coffeeBean       = Color(0xFF20131E);
  static const Color coffeeBean2      = Color(0xFF180E17);
  static const Color coffeeBean3      = Color(0xFF10090F);
  static const Color darkBlack        = Color(0xFF080508);

  static const Color darkBg       = Color(0xFF000000);
  static const Color darkSurface  = coffeeBean3;
  static const Color darkCard     = coffeeBean2;
  static const Color darkInput    = coffeeBean;
  static const Color darkText     = Color(0xFFF8F4F8);
  static const Color darkTextMid  = Color(0xFFC7B6C5);
  static const Color darkDivider  = midnightViolet3;

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color scaffoldBg(BuildContext context) => isDark(context) ? darkBg : bgWhite;
  static Color surfaceBg(BuildContext context) => isDark(context) ? darkSurface : bgSurface;
  static Color cardBg(BuildContext context) => isDark(context) ? darkCard : bgCard;
  static Color inputBg(BuildContext context) => isDark(context) ? darkInput : bgInput;
  static Color textPrimary(BuildContext context) => isDark(context) ? darkText : textDark;
  static Color textSecondary(BuildContext context) => isDark(context) ? darkTextMid : textMid;
  static Color border(BuildContext context) => isDark(context) ? darkDivider : divider;

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        bg: bgWhite,
        card: bgCard,
        input: bgInput,
        text: textDark,
        subText: textMid,
        borderColor: divider,
        accent: primaryBlue,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        bg: darkBg,
        card: darkCard,
        input: darkInput,
        text: darkText,
        subText: darkTextMid,
        borderColor: darkDivider,
        accent: lightBlue,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color input,
    required Color text,
    required Color subText,
    required Color borderColor,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryBlue,
        onPrimary: Colors.white,
        secondary: accentBlue,
        onSecondary: Colors.white,
        error: errorRed,
        onError: Colors.white,
        surface: card,
        onSurface: text,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: text, fontWeight: FontWeight.w800, fontFamily: 'Outfit', fontSize: 28),
        displayMedium: TextStyle(color: text, fontWeight: FontWeight.w700, fontFamily: 'Outfit', fontSize: 22),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w600, fontFamily: 'Outfit', fontSize: 18),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontSize: 15),
        bodyLarge: TextStyle(color: text, fontFamily: 'Inter', fontSize: 15),
        bodyMedium: TextStyle(color: subText, fontFamily: 'Inter', fontSize: 13),
        labelLarge: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontSize: 15),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 10 : 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        textStyle: TextStyle(color: text, fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(color: text, fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 2)),
        hintStyle: TextStyle(color: isDark ? darkTextMid : textLight, fontFamily: 'Inter', fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      dividerColor: borderColor,
      iconTheme: IconThemeData(color: subText),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );
  }
}
