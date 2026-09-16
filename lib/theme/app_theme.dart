import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  C._();
  static const primary = Color(0xFF6C5CE7);
  static const secondary = Color(0xFF00D2FF);
  static const accent = Color(0xFFFD79A8);
  static const success = Color(0xFF00E676);
  static const danger = Color(0xFFFF5252);
  static const warning = Color(0xFFFFC107);
  static const info = Color(0xFF29B6F6);
  static const bgDark = Color(0xFF0A0E21);
  static const bgDarker = Color(0xFF05070F);
  static const bgCard = Color(0xFF151A30);
  static const bgCardLight = Color(0xFF1E2545);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8BED4);
  static const textHint = Color(0xFF7A81A0);
  static const border = Color(0x1AFFFFFF);

  static Color pingColor(int? ms) {
    if (ms == null || ms >= 9999) return textSecondary;
    if (ms < 150) return success;
    if (ms < 350) return secondary;
    if (ms < 700) return warning;
    return danger;
  }

  static Color protoColor(String p) {
    switch (p.toLowerCase()) {
      case 'ss':
        return const Color(0xFF2196F3);
      case 'vless':
        return const Color(0xFF9C27B0);
      case 'vmess':
        return const Color(0xFFFF9800);
      case 'trojan':
        return const Color(0xFF4CAF50);
      default:
        return textSecondary;
    }
  }
}

class AppTheme {
  AppTheme._();
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: C.bgDark,
      colorScheme: const ColorScheme.dark(
        primary: C.primary,
        secondary: C.secondary,
        surface: C.bgCard,
        error: C.danger,
      ),
      textTheme: GoogleFonts.vazirmatnTextTheme(base.textTheme).apply(
        bodyColor: C.textPrimary,
        displayColor: C.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: C.textPrimary),
        titleTextStyle: GoogleFonts.vazirmatn(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: C.textPrimary,
          letterSpacing: 1,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: C.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: C.bgCardLight,
        hintStyle: const TextStyle(color: C.textHint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.secondary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: C.bgCardLight,
        contentTextStyle: GoogleFonts.vazirmatn(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: GoogleFonts.vazirmatn(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: C.textPrimary,
        ),
      ),
    );
  }
} 
