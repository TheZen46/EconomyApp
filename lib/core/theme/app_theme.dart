import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors (Imported from Figma React Design)
  static const Color background = Color(0xFF121212); // Deep Figma Dark
  static const Color surface = Color(0xFF1A1A1A);    // Widget surface background
  static const Color surfaceHighlight = Color(0xFF262626); // Modals / Dialogs
  static const Color primary = Color(0xFF002FA7);    // Figma Neon Cobalt Blue
  static const Color secondary = Color(0xFF4ADE80);  // Keeping Green for positive flow
  static const Color textMain = Color(0xFFFFFFFF);   // Pure White
  static const Color textDim = Color(0xFFA3A3A3);    // text-[#a3a3a3]
  static const Color error = Color(0xFFEF4444);      // Red 500

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
        onSurface: textMain,
      ),
      textTheme: GoogleFonts.outfitTextTheme().apply(
        bodyColor: textMain,
        displayColor: textMain,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceHighlight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceHighlight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textDim),
        floatingLabelStyle: const TextStyle(color: primary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceHighlight,
        modalBackgroundColor: surfaceHighlight,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHighlight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      iconTheme: const IconThemeData(color: textDim),
    );
  }
}
