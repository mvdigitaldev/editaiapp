import 'dart:math' as math;
import 'dart:typed_data';

/// Disciplina de espaço de cor da Beauty Engine (cap. 13 do plano do SDK
/// facial).
///
/// Regra do pipeline:
/// - blur / blend / interpolação → **linear RGB** (blur em sRGB com gama
///   escurece transições e cria bordas sujas em pele);
/// - pele / olheira / dentes / white balance → **OKLab** (hue uniforme, mais
///   barato que CIELAB e sem o shift de matiz do HSV);
/// - curvas / LUT / saída → sRGB (expectativa do usuário e dos .cube).
abstract final class ColorScience {
  /// sRGB 8-bit → linear (0..1). Tabela de 256 entradas: a conversão aparece
  /// em todo pixel de todo pass, então vale o cache.
  static final Float32List srgbToLinearTable = _buildSrgbToLinearTable();

  static Float32List _buildSrgbToLinearTable() {
    final table = Float32List(256);
    for (var i = 0; i < 256; i++) {
      final c = i / 255.0;
      table[i] = c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    return table;
  }

  static double srgbToLinear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double linearToSrgb(double c) {
    if (c <= 0) return 0;
    if (c >= 1) return 1;
    return c <= 0.0031308
        ? c * 12.92
        : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
  }

  static int linearToSrgb8(double c) {
    return (linearToSrgb(c) * 255).round().clamp(0, 255);
  }

  /// Luminância relativa (Rec. 709) em luz linear.
  static double linearLuma(double r, double g, double b) {
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Extrai o canal de luminância linear de um buffer RGBA8.
  static Float32List lumaFromRgba(Uint8List rgba, int width, int height) {
    final table = srgbToLinearTable;
    final out = Float32List(width * height);
    for (var i = 0, p = 0; p < out.length; i += 4, p++) {
      out[p] = 0.2126 * table[rgba[i]] +
          0.7152 * table[rgba[i + 1]] +
          0.0722 * table[rgba[i + 2]];
    }
    return out;
  }

  // --- OKLab (Björn Ottosson) ---

  /// Linear RGB → OKLab. Retorna [L, a, b] no buffer [out] (evita alocação
  /// por pixel em loops quentes).
  static void linearRgbToOklab(
    double r,
    double g,
    double b,
    Float64List out,
  ) {
    final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    final l_ = _cbrt(l);
    final m_ = _cbrt(m);
    final s_ = _cbrt(s);

    out[0] = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    out[1] = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    out[2] = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
  }

  /// OKLab → linear RGB, escrito em [out] como [r, g, b].
  static void oklabToLinearRgb(
    double lightness,
    double a,
    double b,
    Float64List out,
  ) {
    final l_ = lightness + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = lightness - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = lightness - 0.0894841775 * a - 1.2914855480 * b;

    final l = l_ * l_ * l_;
    final m = m_ * m_ * m_;
    final s = s_ * s_ * s_;

    out[0] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    out[1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    out[2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  }

  static double _cbrt(double value) {
    if (value == 0) return 0;
    return value < 0
        ? -math.pow(-value, 1 / 3).toDouble()
        : math.pow(value, 1 / 3).toDouble();
  }
}
