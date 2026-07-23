// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // === BRAND ===
  static const Color accent = Color(0xFF002FA7); // International Klein Blue
  static const Color accentLight = Color(0xFF4D6FD1);
  static const Color destructive = Color(0xFFD4183D);

  // === LIGHT MODE ===
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightFg = Color(0xFF1A1A1A);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardAlt = Color(0xFFFAFAFA);
  static const Color lightMuted = Color(0xFF737373);
  static const Color lightBorder = Color(0x0F000000); // rgba(0,0,0,0.06)
  static const Color lightBorderStrong = Color(0x26000000);
  static const Color lightSecondary = Color(0xFFF5F5F5);

  // === DARK MODE ===
  static const Color darkBg = Color(0xFF0A0A0A);
  static const Color darkBgAlt = Color(0xFF050505);
  static const Color darkCard = Color(0xFF0F0F0F);
  static const Color darkCardAlt = Color(0xFF121212);
  static const Color darkFg = Color(0xFFF5F5F5);
  static const Color darkFgDim = Color(0xFFA3A3A3);
  static const Color darkBorder = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const Color darkBorderStrong = Color(0x33FFFFFF);
  static const Color darkSecondary = Color(0xFF1A1A1A);
}

class AppTheme {
  // Kept for backward compat during migration
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF0F0F0F);
  static const Color surfaceHighlight = Color(0xFF1A1A1A);
  static const Color primary = Color(0xFF002FA7);
  static const Color secondary = Color(0xFF4D6FD1);
  static const Color textMain = Color(0xFFF5F5F5);
  static const Color textDim = Color(0xFFA3A3A3);
  static const Color error = Color(0xFFD4183D);

  static TextTheme _buildTextTheme(Color bodyColor) {
    return GoogleFonts.spaceGroteskTextTheme().copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w300, fontSize: 52),
      displayMedium: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w300, fontSize: 42),
      headlineLarge: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 28),
      headlineMedium: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 22),
      headlineSmall: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 18),
      titleLarge: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 16),
      titleMedium: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 14),
      bodyLarge: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w300, fontSize: 16),
      bodyMedium: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w300, fontSize: 14),
      bodySmall: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w300, fontSize: 12),
      labelLarge: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 12),
      labelSmall: GoogleFonts.spaceGrotesk(color: bodyColor, fontWeight: FontWeight.w500, fontSize: 10),
    );
  }

  static ThemeData get lightTheme {
    const bg = AppColors.lightBg;
    const fg = AppColors.lightFg;
    const card = AppColors.lightCard;
    const border = AppColors.lightBorder;
    const accent = AppColors.accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: AppColors.accentLight,
        surface: card,
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSurface: fg,
        onSecondary: Colors.white,
      ),
      textTheme: _buildTextTheme(fg),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: fg, fontSize: 20, fontWeight: FontWeight.w500,
        ),
        iconTheme: const IconThemeData(color: fg),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      dividerColor: border,
      iconTheme: const IconThemeData(color: AppColors.lightMuted),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.lightMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightCard,
        modalBackgroundColor: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData get darkTheme {
    const bg = AppColors.darkBg;
    const fg = AppColors.darkFg;
    const card = AppColors.darkCard;
    const border = AppColors.darkBorder;
    const accent = AppColors.accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: AppColors.accentLight,
        surface: card,
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSurface: fg,
        onSecondary: Colors.white,
      ),
      textTheme: _buildTextTheme(fg),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: fg, fontSize: 20, fontWeight: FontWeight.w500,
        ),
        iconTheme: const IconThemeData(color: fg),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      dividerColor: border,
      iconTheme: const IconThemeData(color: AppColors.darkFgDim),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.darkFgDim),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkCard,
        modalBackgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
