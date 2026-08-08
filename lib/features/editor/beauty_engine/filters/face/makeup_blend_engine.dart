import 'dart:typed_data';

import '../../color/color_science.dart';

/// Blends perceptuais de makeup em OKLab / soft-light (Sprint 8).
abstract final class MakeupBlendEngine {
  static final _oklabBuf = Float64List(3);
  static final _rgbBuf = Float64List(3);

  /// Clareia pele subindo L em OKLab em direção ao alvo (0..1).
  static void applyWhitening({
    required int r,
    required int g,
    required int b,
    required double amount,
    required double targetLightness,
    required Float64List out,
  }) {
    if (amount <= 0) {
      out[0] = r.toDouble();
      out[1] = g.toDouble();
      out[2] = b.toDouble();
      return;
    }

    final lr = ColorScience.srgbToLinear(r / 255.0);
    final lg = ColorScience.srgbToLinear(g / 255.0);
    final lb = ColorScience.srgbToLinear(b / 255.0);
    ColorScience.linearRgbToOklab(lr, lg, lb, _oklabBuf);

    final lift = amount * 0.14;
    _oklabBuf[0] = _oklabBuf[0] + (targetLightness - _oklabBuf[0]) * lift;

    ColorScience.oklabToLinearRgb(
      _oklabBuf[0],
      _oklabBuf[1],
      _oklabBuf[2],
      _rgbBuf,
    );
    out[0] = ColorScience.linearToSrgb8(_rgbBuf[0]).toDouble();
    out[1] = ColorScience.linearToSrgb8(_rgbBuf[1]).toDouble();
    out[2] = ColorScience.linearToSrgb8(_rgbBuf[2]).toDouble();
  }

  /// Blush soft-light adaptativo (cor em sRGB, mix em OKLab).
  static void applyBlush({
    required int r,
    required int g,
    required int b,
    required double amount,
    required double weight,
    required Float64List out,
  }) {
    if (amount <= 0 || weight <= 0) {
      out[0] = r.toDouble();
      out[1] = g.toDouble();
      out[2] = b.toDouble();
      return;
    }

    const blushR = 220.0;
    const blushG = 96.0;
    const blushB = 108.0;
    final t = (amount * weight * 0.55).clamp(0.0, 0.65);

    final lr = ColorScience.srgbToLinear(r / 255.0);
    final lg = ColorScience.srgbToLinear(g / 255.0);
    final lb = ColorScience.srgbToLinear(b / 255.0);
    ColorScience.linearRgbToOklab(lr, lg, lb, _oklabBuf);

    final br = ColorScience.srgbToLinear(blushR / 255.0);
    final bg = ColorScience.srgbToLinear(blushG / 255.0);
    final bb = ColorScience.srgbToLinear(blushB / 255.0);
    ColorScience.linearRgbToOklab(br, bg, bb, _rgbBuf);

    _oklabBuf[0] = _oklabBuf[0] + (_rgbBuf[0] - _oklabBuf[0]) * t * 0.35;
    _oklabBuf[1] = _oklabBuf[1] + (_rgbBuf[1] - _oklabBuf[1]) * t;
    _oklabBuf[2] = _oklabBuf[2] + (_rgbBuf[2] - _oklabBuf[2]) * t;

    ColorScience.oklabToLinearRgb(
      _oklabBuf[0],
      _oklabBuf[1],
      _oklabBuf[2],
      _rgbBuf,
    );
    out[0] = ColorScience.linearToSrgb8(_rgbBuf[0]).toDouble();
    out[1] = ColorScience.linearToSrgb8(_rgbBuf[1]).toDouble();
    out[2] = ColorScience.linearToSrgb8(_rgbBuf[2]).toDouble();
  }

  /// Escurece só luminância (sobrancelhas) preservando croma relativo.
  static void applyEyebrowDarken({
    required int r,
    required int g,
    required int b,
    required double amount,
    required double weight,
    required Float64List out,
  }) {
    if (amount <= 0 || weight <= 0) {
      out[0] = r.toDouble();
      out[1] = g.toDouble();
      out[2] = b.toDouble();
      return;
    }

    final lr = ColorScience.srgbToLinear(r / 255.0);
    final lg = ColorScience.srgbToLinear(g / 255.0);
    final lb = ColorScience.srgbToLinear(b / 255.0);
    ColorScience.linearRgbToOklab(lr, lg, lb, _oklabBuf);

    final darken = amount * weight * 0.22;
    _oklabBuf[0] = (_oklabBuf[0] - darken).clamp(0.0, 1.0);

    ColorScience.oklabToLinearRgb(
      _oklabBuf[0],
      _oklabBuf[1],
      _oklabBuf[2],
      _rgbBuf,
    );
    out[0] = ColorScience.linearToSrgb8(_rgbBuf[0]).toDouble();
    out[1] = ColorScience.linearToSrgb8(_rgbBuf[1]).toDouble();
    out[2] = ColorScience.linearToSrgb8(_rgbBuf[2]).toDouble();
  }
}
