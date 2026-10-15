import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cores e Nunito do guia visual. O tema global continua na Space Grotesk.
class BrandVisual {
  static const Color blue = Color(0xFF168BFF);
  static const Color navy = Color(0xFF10213D);

  static TextStyle title({
    double size = 28,
    Color? color,
    double height = 1.15,
  }) {
    return GoogleFonts.nunito(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: color ?? navy,
      height: height,
    );
  }

  static TextStyle text({
    double size = 16,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.35,
  }) {
    return GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color ?? navy,
      height: height,
    );
  }
}
