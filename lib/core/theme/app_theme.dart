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
        surfaceContainer: AppColors.lightSecondary,
        surfaceContainerHigh: AppColors.lightCardAlt,
        surfaceContainerHighest: const Color(0xFFEFEFEF),
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSurface: fg,
        onSurfaceVariant: AppColors.lightMuted,
        onSecondary: Colors.white,
        outline: border,
        outlineVariant: AppColors.lightBorderStrong,
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
        surfaceContainer: AppColors.darkSecondary,
        surfaceContainerHigh: AppColors.darkCardAlt,
        surfaceContainerHighest: const Color(0xFF1E1E1E),
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSurface: fg,
        onSurfaceVariant: AppColors.darkFgDim,
        onSecondary: Colors.white,
        outline: border,
        outlineVariant: AppColors.darkBorderStrong,
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

  /// Reusable destructive confirmation dialog adhering to [AppTheme].
  static Future<bool> showDestructiveConfirmationDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
  }) {
    return _showDestructiveConfirmationDialogImpl(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
  }

  static TextTheme _buildBalatroTextTheme(Color bodyColor) {
    return _buildTextTheme(bodyColor).apply(
      fontFamily: GoogleFonts.pressStart2p().fontFamily,
      bodyColor: bodyColor,
      displayColor: bodyColor,
    );
  }

  static ThemeData get balatroTheme {
    const bg = Color(0xFF0A1C14); // Void green
    const fg = Colors.white;
    const card = Color(0xFF0E241B);
    const border = Colors.white;
    const accent = Color(0xFFFF3333); // Poker red
    const secondary = Color(0xFF33CCFF); // Electric cyan

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: secondary,
        surface: card,
        surfaceContainer: Color(0xFF050A1F),
        surfaceContainerHigh: Color(0xFF0E241B),
        surfaceContainerHighest: Color(0xFF18382B),
        error: Color(0xFFFF2222),
        onPrimary: Colors.white,
        onSurface: fg,
        onSurfaceVariant: Color(0xFF8EF7C2),
        onSecondary: Colors.black,
        outline: border,
        outlineVariant: Colors.white70,
      ),
      textTheme: _buildBalatroTextTheme(fg),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.pressStart2p(
          color: fg, fontSize: 14, fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: fg),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 3),
        ),
      ),
      dividerColor: border,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
          textStyle: GoogleFonts.pressStart2p(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Standardized destructive confirmation dialog adhering to the current Theme and ColorScheme.
///
/// Prompts the user with [title] and [message] before proceeding with a destructive action.
/// Returns `true` if confirmed, and `false` otherwise.
Future<bool> showDestructiveConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) {
  return _showDestructiveConfirmationDialogImpl(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
  );
}

Future<bool> _showDestructiveConfirmationDialogImpl({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.spaceGrotesk(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            cancelLabel,
            style: GoogleFonts.spaceGrotesk(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.error,
          ),
          child: Text(
            confirmLabel,
            style: GoogleFonts.spaceGrotesk(
              color: colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

