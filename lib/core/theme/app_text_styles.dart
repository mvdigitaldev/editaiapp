import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  static TextStyle get displayLarge => GoogleFonts.spaceGrotesk(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.02,
        height: 1.2,
      );

  static TextStyle get displayMedium => GoogleFonts.spaceGrotesk(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.02,
        height: 1.2,
      );

  static TextStyle get displaySmall => GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.015,
        height: 1.2,
      );

  static TextStyle get headingLarge => GoogleFonts.spaceGrotesk(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.015,
        height: 1.3,
      );

  static TextStyle get headingMedium => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.015,
        height: 1.3,
      );

  static TextStyle get headingSmall => GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.01,
        height: 1.4,
      );

  static TextStyle get bodyLarge => GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.normal,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get bodyMedium => GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get bodySmall => GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get labelLarge => GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.4,
      );

  static TextStyle get labelMedium => GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.4,
      );

  static TextStyle get labelSmall => GoogleFonts.spaceGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.4,
      );

  static TextStyle get caption => GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        letterSpacing: 0.4,
        height: 1.4,
      );

  static TextStyle get overline => GoogleFonts.spaceGrotesk(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        height: 1.4,
      );
}
