import 'dart:typed_data';
import 'dart:ui';

import '../../color/color_science.dart';
import 'skin/skin_weight_map.dart';
import 'skin_mask_utils.dart';

/// Tom de pele amostrado da bochecha — thresholds relativos (cap. 16).
class SkinToneCalibration {
  const SkinToneCalibration({
    required this.referenceLinearLuma,
    required this.oklabL,
    required this.oklabA,
    required this.oklabB,
    this.sampleCount = 0,
  });

  final double referenceLinearLuma;
  final double oklabL;
  final double oklabA;
  final double oklabB;
  final int sampleCount;

  bool get isValid => sampleCount > 0;

  /// Joelho de brilho especular relativo ao tom amostrado.
  double get shineKnee => referenceLinearLuma * 1.18;

  /// L mínimo OKLab para considerar pixel como dente (relativo ao tom).
  double get teethMinOklabL => (oklabL + 0.12).clamp(0.55, 0.95);

  /// Cromatividade máxima para dente (evita lábios).
  double get teethMaxChroma => 0.08 + (0.92 - oklabL.clamp(0, 1)) * 0.06;

  static SkinToneCalibration empty = const SkinToneCalibration(
    referenceLinearLuma: 0.45,
    oklabL: 0.65,
    oklabA: 0,
    oklabB: 0,
    sampleCount: 0,
  );

  /// Amostra pele de alta confiança nas bochechas, fora de olheiras.
  static SkinToneCalibration sample({
    required Uint8List rgba,
    required Uint8List skinWeights,
    required SkinProcessingMask geometric,
    required int width,
    required int height,
    SkinTileMapping mapping = const SkinTileMapping(),
  }) {
    final pixels = width * height;
    if (pixels <= 0 || rgba.length < pixels * 4 || skinWeights.length != pixels) {
      return empty;
    }

    final table = ColorScience.srgbToLinearTable;
    final lab = Float64List(3);
    var sumL = 0.0;
    var sumLin = 0.0;
    var sumA = 0.0;
    var sumB = 0.0;
    var count = 0;
    final resolved = mapping.resolve(width, height);

    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        if (skinWeights[p] < 200) continue;

        final nx = resolved.normalizedX(x);
        final onCheek = geometric.cheekRegions.any((r) => r.contains(Offset(nx, ny)));
        if (!onCheek) continue;
        if (SkinMaskUtils.underEyeWeight(nx, ny, geometric) > 0.05) continue;

        final i = p * 4;
        final r = table[rgba[i]];
        final g = table[rgba[i + 1]];
        final b = table[rgba[i + 2]];
        ColorScience.linearRgbToOklab(r, g, b, lab);
        sumLin += ColorScience.linearLuma(r, g, b);
        sumL += lab[0];
        sumA += lab[1];
        sumB += lab[2];
        count++;
      }
    }

    if (count == 0) return empty;
    return SkinToneCalibration(
      referenceLinearLuma: sumLin / count,
      oklabL: sumL / count,
      oklabA: sumA / count,
      oklabB: sumB / count,
      sampleCount: count,
    );
  }
}
