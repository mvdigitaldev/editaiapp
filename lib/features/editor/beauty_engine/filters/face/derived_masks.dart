import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../color/color_science.dart';
import '../../segment/face_parsing_class.dart';
import '../../segment/face_parsing_result.dart';
import 'mask_sampling.dart';
import 'skin/skin_weight_map.dart';
import 'skin_mask_utils.dart';
import 'skin_tone_calibration.dart';

/// Máscaras derivadas do face parsing + calibração por tom (Sprint 5 / cap. 2.3).
class DerivedMaskBundle {
  const DerivedMaskBundle({
    required this.teeth,
    required this.underEye,
    required this.shine,
    required this.jawBand,
    required this.iris,
    required this.eyebrows,
    required this.tone,
    required this.width,
    required this.height,
  });

  final Uint8List teeth;
  final Uint8List underEye;
  final Uint8List shine;
  final Uint8List jawBand;
  final Uint8List iris;
  final Uint8List eyebrows;
  final SkinToneCalibration tone;
  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0;
}

/// Constrói máscaras derivadas (dentes ∩ OKLab, olheiras v2, brilho, etc.).
abstract final class DerivedMaskBuilder {
  static const teethParsingClasses = {
    FaceParsingClass.mouth,
    FaceParsingClass.lipUpper,
    FaceParsingClass.lipLower,
  };

  static const browParsingClasses = {
    FaceParsingClass.browG,
    FaceParsingClass.browL,
  };

  static const irisIndicesLeft = {468, 469, 470, 471, 472};
  static const irisIndicesRight = {473, 474, 475, 476, 477};

  static DerivedMaskBundle build({
    required Uint8List rgba,
    required int width,
    required int height,
    required SkinProcessingMask geometric,
    required Uint8List skinWeights,
    FaceParsingResult? parsing,
    SkinTileMapping mapping = const SkinTileMapping(),
    MaskSamplingContext sampling = const MaskSamplingContext(),
  }) {
    final pixels = math.max(width * height, 0);
    if (pixels <= 0) {
      return DerivedMaskBundle(
        teeth: Uint8List(0),
        underEye: Uint8List(0),
        shine: Uint8List(0),
        jawBand: Uint8List(0),
        iris: Uint8List(0),
        eyebrows: Uint8List(0),
        tone: SkinToneCalibration.empty,
        width: width,
        height: height,
      );
    }

    final tone = SkinToneCalibration.sample(
      rgba: rgba,
      skinWeights: skinWeights,
      geometric: geometric,
      width: width,
      height: height,
      mapping: mapping,
    );

    final teeth = Uint8List(pixels);
    final underEye = Uint8List(pixels);
    final shine = Uint8List(pixels);
    final jawBand = Uint8List(pixels);
    final iris = Uint8List(pixels);
    final eyebrows = Uint8List(pixels);

    final table = ColorScience.srgbToLinearTable;
    final lab = Float64List(3);
    final shineKnee = tone.shineKnee;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        final sample = sampling.maskNormalized(
          x: x,
          y: y,
          width: width,
          height: height,
        );
        final nx = sample.dx;
        final ny = sample.dy;

        final skinW = skinWeights[p] / 255.0;

        // --- Olheiras v2: landmark ∩ pele ---
        final under = SkinMaskUtils.underEyeWeight(nx, ny, geometric);
        if (under > 0 && skinW > 0.15) {
          underEye[p] = (under * skinW * 255).round().clamp(0, 255);
        }

        // --- Mandíbula / contorno ---
        final jaw = SkinMaskUtils.softRegionsWeight(
          nx,
          ny,
          geometric.contourRegions,
          edgeFeather: 0.035,
        );
        if (jaw > 0) {
          jawBand[p] = (jaw * 255).round().clamp(0, 255);
        }

        // --- Sobrancelhas ---
        var browW = 0.0;
        if (parsing != null && !parsing.isEmpty) {
          if (browParsingClasses.contains(parsing.classAtNormalized(nx, ny))) {
            browW = 1.0;
          }
        }
        browW = math.max(
          browW,
          SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            geometric.eyebrowRegions,
            edgeFeather: 0.02,
          ),
        );
        if (browW > 0) {
          eyebrows[p] = (browW * 255).round().clamp(0, 255);
        }

        // --- Íris ---
        final irisW = _irisWeight(nx, ny, geometric);
        if (irisW > 0) {
          iris[p] = (irisW * 255).round().clamp(0, 255);
        }

        // --- Brilho: pele + highlight acima do joelho relativo ---
        if (skinW > 0.2 && !SkinMaskUtils.isProtected(nx, ny, geometric)) {
          final i = p * 4;
          final lin = ColorScience.linearLuma(
            table[rgba[i]],
            table[rgba[i + 1]],
            table[rgba[i + 2]],
          );
          if (shineKnee > 0 && lin > shineKnee) {
            final excess = ((lin - shineKnee) / (1 - shineKnee)).clamp(0.0, 1.0);
            shine[p] = (excess * skinW * 255).round().clamp(0, 255);
          }
        }

        // --- Dentes: inner mouth ∩ OKLab ---
        var region = _teethRegion(nx, ny, geometric, parsing);
        if (region <= 0) continue;

        final i = p * 4;
        ColorScience.linearRgbToOklab(
          table[rgba[i]],
          table[rgba[i + 1]],
          table[rgba[i + 2]],
          lab,
        );
        final chroma = math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
        if (lab[0] >= tone.teethMinOklabL && chroma <= tone.teethMaxChroma) {
          final pixelW = _teethPixelWeight(lab[0], chroma, tone);
          teeth[p] = (region * pixelW * 255).round().clamp(0, 255);
        }
      }
    }

    return DerivedMaskBundle(
      teeth: teeth,
      underEye: underEye,
      shine: shine,
      jawBand: jawBand,
      iris: iris,
      eyebrows: eyebrows,
      tone: tone,
      width: width,
      height: height,
    );
  }

  static double _teethRegion(
    double nx,
    double ny,
    SkinProcessingMask geometric,
    FaceParsingResult? parsing,
  ) {
    if (parsing != null &&
        !parsing.isEmpty &&
        teethParsingClasses.contains(parsing.classAtNormalized(nx, ny))) {
      return 1.0;
    }
    return SkinMaskUtils.teethRegionWeight(nx, ny, geometric);
  }

  static double _teethPixelWeight(double oklabL, double chroma, SkinToneCalibration tone) {
    final lumFactor = ((oklabL - tone.teethMinOklabL) / 0.25).clamp(0.0, 1.0);
    final satFactor = ((tone.teethMaxChroma - chroma) / tone.teethMaxChroma)
        .clamp(0.0, 1.0);
    return (0.5 + 0.5 * lumFactor * satFactor).clamp(0.0, 1.0);
  }

  static double _irisWeight(double nx, double ny, SkinProcessingMask geometric) {
    // Protege olho branco — só a elipse da íris.
    for (final region in geometric.protectedRegions.take(2)) {
      if (!region.inflate(0.01).contains(Offset(nx, ny))) {
        continue;
      }
      // Dentro do olho: usar distância ao centro aproximado da íris.
      final center = region.center;
      final rx = region.width * 0.22;
      final ry = region.height * 0.35;
      final dx = (nx - center.dx) / rx;
      final dy = (ny - center.dy) / ry;
      final radial = dx * dx + dy * dy;
      if (radial <= 1.0) {
        return (1 - radial).clamp(0.0, 1.0);
      }
    }
    return 0;
  }
}
