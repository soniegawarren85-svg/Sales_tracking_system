import 'package:sales_tracking/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData theme = ThemeData(
    primarySwatch: AppColors.brand,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(),
    primaryTextTheme: GoogleFonts.dmSansTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      toolbarTextStyle: GoogleFonts.dmSans(color: Colors.white, fontSize: 16),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.blush,
      selectionHandleColor: AppColors.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      prefixIconColor: AppColors.brand,
      suffixIconColor: AppColors.brand,
      labelStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.brand),
      hintStyle: GoogleFonts.dmSans(fontSize: 14, color: Colors.grey),
      helperStyle: GoogleFonts.dmSans(fontSize: 12, color: Colors.grey),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.brand),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.brand.shade100),
        borderRadius: BorderRadius.circular(12),
      ),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.brand.shade100),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        textStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
