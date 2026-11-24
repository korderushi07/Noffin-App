import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF707070);
  static const Color tertiaryText = Color(0xFFA0A0A0);
  static const Color emptyCell = Color(0xFFF2F2F2);
  static const Color lightFill = Color(0xFFCCCCCC);
  static const Color darkFill = Color(0xFF111111);
  static const Color cardBackground = Color(0xFFF7F7F7);
  static const Color background = Color(0xFFFFFFFF);
  static const Color todayBorder = Color(0xFF111111);
  static const Color separator = Color(0xFFE5E5E5);
  static const Color error = Color(0xFF111111);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    colorScheme: const ColorScheme.light(
      surface: AppColors.background,
      primary: AppColors.darkFill,
      onPrimary: Colors.white,
      onSurface: AppColors.text,
      outline: AppColors.separator,
      error: AppColors.error,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: 56,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.text,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          );
        }
        return GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Colors.white);
        }
        return const IconThemeData(color: AppColors.secondaryText);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: GoogleFonts.manrope(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkFill, width: 1.5),
      ),
    ),
  );
}
