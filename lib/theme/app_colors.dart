import 'package:flutter/material.dart';

/// Shared raspberry palette for authentication, admin, and staff screens.
class AppColors {
  AppColors._();

  static const primary = Color(0xFFB91C49);
  static const primaryDark = Color(0xFF94163A);
  static const primaryDeep = Color(0xFF70132E);
  static const accent = Color(0xFFC93D64);
  static const rose = Color(0xFFD989A0);
  static const blush = Color(0xFFF2DCE4);
  static const background = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFCFCFD);
  static const surfaceTint = Color(0xFFF8F0F3);
  static const border = Color(0xFFE7D6DD);
  static const text = Color(0xFF302831);
  static const textMuted = Color(0xFF786570);

  static const brand = MaterialColor(0xFFB91C49, {
    50: Color(0xFFF8F0F3),
    100: Color(0xFFF2DCE4),
    200: Color(0xFFE7B8C7),
    300: Color(0xFFD989A0),
    400: Color(0xFFC93D64),
    500: primary,
    600: Color(0xFFA81942),
    700: primaryDark,
    800: Color(0xFF821333),
    900: primaryDeep,
  });
}
