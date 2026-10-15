import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  static TextStyle _nunito({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    double height = 1.35,
  }) {
    return GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle get displayLarge => _nunito(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.02,
        height: 1.15,
      );

  static TextStyle get displayMedium => _nunito(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.02,
        height: 1.15,
      );

  static TextStyle get displaySmall => _nunito(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.015,
        height: 1.15,
      );

  static TextStyle get headingLarge => _nunito(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.015,
        height: 1.2,
      );

  static TextStyle get headingMedium => _nunito(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.015,
        height: 1.2,
      );

  static TextStyle get headingSmall => _nunito(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.25,
      );

  static TextStyle get bodyLarge => _nunito(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.45,
      );

  static TextStyle get bodyMedium => _nunito(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
      );

  static TextStyle get bodySmall => _nunito(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get labelLarge => _nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  static TextStyle get labelMedium => _nunito(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  static TextStyle get labelSmall => _nunito(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get caption => _nunito(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
      );

  static TextStyle get overline => _nunito(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        height: 1.3,
      );
}
