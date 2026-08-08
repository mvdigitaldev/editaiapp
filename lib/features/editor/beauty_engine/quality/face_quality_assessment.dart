import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../color/color_science.dart';
import '../filters/face/face_warp_utils.dart';
import '../models/face_landmark.dart';
import '../models/face_mesh_result.dart';
import '../segment/face_parts_segmentation.dart';
import 'face_quality_context.dart';

/// Face Quality Assessment determinístico (cap. 7) — ~5–15 ms em 1080p.
abstract final class FaceQualityAssessment {
  static FaceQualityContext assess({
    required Uint8List rgba,
    required int width,
    required int height,
    FaceMeshResult? face,
    FacePartsSegmentation? faceParts,
  }) {
    final metrics = _computeMetrics(
      rgba: rgba,
      width: width,
      height: height,
      face: face,
      faceParts: faceParts,
    );
    final score = _computeScore(metrics);
    return FaceQualityContext(
      metrics: metrics,
      score: score,
      face: face,
      faceParts: faceParts,
    );
  }

  static FaceQualityMetrics _computeMetrics({
    required Uint8List rgba,
    required int width,
    required int height,
    FaceMeshResult? face,
    FacePartsSegmentation? faceParts,
  }) {
    final hasFace = face != null && face.landmarks.isNotEmpty;
    final box = hasFace
        ? face!.boundingBox
        : Rect.fromLTWH(0.25, 0.15, 0.5, 0.7);

    final x0 = (box.left * width).round().clamp(0, width - 1);
    final y0 = (box.top * height).round().clamp(0, height - 1);
    final x1 = (box.right * width).round().clamp(x0 + 1, width);
    final y1 = (box.bottom * height).round().clamp(y0 + 1, height);

    final blurVariance = _laplacianVariance(rgba, width, height, x0, y0, x1, y1);
    final noiseLevel = _noiseLevel(rgba, width, height, x0, y0, x1, y1);
    final (hi, lo) = _clipRatios(rgba, width, height, x0, y0, x1, y1);
    final wbWarmth = _wbWarmth(rgba, width, height, x0, y0, x1, y1);
    final compression = _blockinessScore(rgba, width, height);

    var yawAsymmetry = 0.0;
    var pitchEstimate = 0.0;
    var confidenceMean = 1.0;
    var occlusionRatio = 0.0;

    if (hasFace) {
      yawAsymmetry = 1 - FaceWarpUtils.yawClampFactor(face!);
      pitchEstimate = _pitchEstimate(face);
      confidenceMean = _meanVisibility(face.landmarks);
      occlusionRatio = _occlusionRatio(face.landmarks);
    }

    return FaceQualityMetrics(
      faceWidthPx: box.width * width,
      faceHeightPx: box.height * height,
      blurVariance: blurVariance,
      noiseLevel: noiseLevel,
      highlightClipRatio: hi,
      shadowClipRatio: lo,
      wbWarmth: wbWarmth,
      compressionScore: compression,
      yawAsymmetry: yawAsymmetry,
      pitchEstimate: pitchEstimate,
      landmarkConfidenceMean: confidenceMean,
      occlusionRatio: occlusionRatio,
      hasFace: hasFace,
      hasSkinSegmentation: faceParts != null &&
          !faceParts.isEmpty &&
          faceParts.coverageOf(FacePartClass.faceSkin) > 0.02,
    );
  }

  static FaceQualityScore _computeScore(FaceQualityMetrics m) {
    // Laplacian típico: <80 borrado, >400 nítido (escala empírica).
    final sharpness = ((m.blurVariance - 40) / 360).clamp(0.0, 1.0);
    final clipPenalty =
        (m.highlightClipRatio + m.shadowClipRatio).clamp(0.0, 1.0);
    final lighting = (1 - clipPenalty * 1.4).clamp(0.0, 1.0);
    final pose =
        (1 - m.yawAsymmetry * 1.2 - m.pitchEstimate.abs() * 0.5).clamp(0.0, 1.0);

    final sizeFactor = m.faceShortEdgePx <= 0
        ? 0
        : (m.faceShortEdgePx / 240).clamp(0.0, 1.0);
    final integrity = (sizeFactor *
            m.landmarkConfidenceMean *
            (1 - m.occlusionRatio * 0.7))
        .clamp(0.0, 1.0);

    return FaceQualityScore(
      sharpness: sharpness,
      lighting: lighting,
      pose: pose,
      integrity: integrity,
    );
  }

  static double _laplacianVariance(
    Uint8List rgba,
    int width,
    int height,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final samples = <double>[];
    for (var y = y0 + 1; y < y1 - 1; y++) {
      for (var x = x0 + 1; x < x1 - 1; x++) {
        final c = _lumaAt(rgba, width, x, y);
        final lap = -4 * c +
            _lumaAt(rgba, width, x - 1, y) +
            _lumaAt(rgba, width, x + 1, y) +
            _lumaAt(rgba, width, x, y - 1) +
            _lumaAt(rgba, width, x, y + 1);
        samples.add(lap);
      }
    }
    if (samples.isEmpty) return 0;
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    var varSum = 0.0;
    for (final v in samples) {
      final d = v - mean;
      varSum += d * d;
    }
    return varSum / samples.length;
  }

  static double _noiseLevel(
    Uint8List rgba,
    int width,
    int height,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final cx = ((x0 + x1) ~/ 2).clamp(1, width - 2);
    final cy = ((y0 + y1) ~/ 2).clamp(1, height - 2);
    final patch = <double>[];
    for (var dy = -3; dy <= 3; dy++) {
      for (var dx = -3; dx <= 3; dx++) {
        final x = (cx + dx).clamp(x0, x1 - 1);
        final y = (cy + dy).clamp(y0, y1 - 1);
        patch.add(_lumaAt(rgba, width, x, y));
      }
    }
    if (patch.length < 9) return 0;
    final mean = patch.reduce((a, b) => a + b) / patch.length;
    var highPass = 0.0;
    for (final v in patch) {
      highPass += (v - mean).abs();
    }
    return (highPass / patch.length * 8).clamp(0.0, 1.0);
  }

  static (double, double) _clipRatios(
    Uint8List rgba,
    int width,
    int height,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    var hi = 0;
    var lo = 0;
    var total = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final l = _lumaAt(rgba, width, x, y);
        total++;
        if (l > 0.97) hi++;
        if (l < 0.03) lo++;
      }
    }
    if (total == 0) return (0, 0);
    return (hi / total, lo / total);
  }

  static double _wbWarmth(
    Uint8List rgba,
    int width,
    int height,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final oklab = Float64List(3);
    var sumA = 0.0;
    var count = 0;
    final step = math.max(2, ((x1 - x0) * (y1 - y0) ~/ 400).clamp(2, 8));
    for (var y = y0; y < y1; y += step) {
      for (var x = x0; x < x1; x += step) {
        final i = (y * width + x) * 4;
        final r = ColorScience.srgbToLinear(rgba[i] / 255.0);
        final g = ColorScience.srgbToLinear(rgba[i + 1] / 255.0);
        final b = ColorScience.srgbToLinear(rgba[i + 2] / 255.0);
        ColorScience.linearRgbToOklab(r, g, b, oklab);
        sumA += oklab[1];
        count++;
      }
    }
    if (count == 0) return 0;
    return (sumA / count * 4).clamp(-1.0, 1.0);
  }

  static double _blockinessScore(Uint8List rgba, int width, int height) {
    var edgeEnergy = 0.0;
    var samples = 0;
    for (var y = 8; y < height; y += 8) {
      for (var x = 8; x < width; x += 8) {
        final a = _lumaAt(rgba, width, x, y);
        final b = _lumaAt(rgba, width, x - 1, y);
        edgeEnergy += (a - b).abs();
        samples++;
      }
    }
    if (samples == 0) return 0;
    return ((edgeEnergy / samples) * 12).clamp(0.0, 1.0);
  }

  static double _pitchEstimate(FaceMeshResult face) {
    final nose = _landmark(face, 1);
    final chin = _landmark(face, 152);
    if (nose == null || chin == null) return 0;
    return ((chin.normalized.dy - nose.normalized.dy) - 0.18).clamp(-0.5, 0.5);
  }

  static double _meanVisibility(List<FaceLandmark> landmarks) {
    if (landmarks.isEmpty) return 0;
    var sum = 0.0;
    for (final lm in landmarks) {
      sum += lm.visibility.clamp(0, 1);
    }
    return sum / landmarks.length;
  }

  static double _occlusionRatio(List<FaceLandmark> landmarks) {
    if (landmarks.isEmpty) return 1;
    var low = 0;
    for (final lm in landmarks) {
      if (lm.visibility < 0.45) low++;
    }
    return low / landmarks.length;
  }

  static FaceLandmark? _landmark(FaceMeshResult face, int index) {
    for (final lm in face.landmarks) {
      if (lm.index == index) return lm;
    }
    return null;
  }

  static double _lumaAt(Uint8List rgba, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return ColorScience.linearLuma(
      ColorScience.srgbToLinearTable[rgba[i]],
      ColorScience.srgbToLinearTable[rgba[i + 1]],
      ColorScience.srgbToLinearTable[rgba[i + 2]],
    );
  }
}
