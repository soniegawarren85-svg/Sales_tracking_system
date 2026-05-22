import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData theme = ThemeData(
    primarySwatch: Colors.pink,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.pink)
        .copyWith(secondary: Colors.pink),
    textTheme: GoogleFonts.dmSansTextTheme(),
    primaryTextTheme: GoogleFonts.dmSansTextTheme(),
    appBarTheme: AppBarTheme(
      titleTextStyle: GoogleFonts.dmSans(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      toolbarTextStyle: GoogleFonts.dmSans(
        color: Colors.white,
        fontSize: 16,
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.pink),
    inputDecorationTheme: InputDecorationTheme(
      prefixIconColor: Colors.pink,
      suffixIconColor: Colors.pink,
      labelStyle: GoogleFonts.dmSans(
        fontSize: 14,
        color: Colors.pink,
      ),
      hintStyle: GoogleFonts.dmSans(
        fontSize: 14,
        color: Colors.grey,
      ),
      helperStyle: GoogleFonts.dmSans(
        fontSize: 12,
        color: Colors.grey,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.pink),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.pink.shade100),
        borderRadius: BorderRadius.circular(12),
      ),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.pink.shade100),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.pink,
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
