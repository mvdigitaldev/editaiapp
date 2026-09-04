import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'eyebrow_end_masks.dart';

class EyebrowEndRegionStats {
  const EyebrowEndRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double meanAbs;
  final double p95Abs;

  static const zero = EyebrowEndRegionStats(
    pixelCount: 0,
    maxAbs: 0,
    meanAbs: 0,
    p95Abs: 0,
  );

  Map<String, Object> toJson() => {
        'pixelCount': pixelCount,
        'maxAbs': maxAbs,
        'meanAbs': meanAbs,
        'p95Abs': p95Abs,
      };
}

/// Métricas do Eyebrow End. Não altera [FieldMetrics] (contrato Jaw).
class EyebrowEndFieldMetrics {
  const EyebrowEndFieldMetrics({
    required this.faceWidth,
    required this.amplitude,
    required this.influenceMax,
    required this.outsideBrowZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.coreCurvature,
    required this.entryStep,
    required this.dxAtInnerLeft,
    required this.dxAtInnerRight,
    required this.dxAtArchLeft,
    required this.dxAtArchRight,
    required this.dxAtTailLeft,
    required this.dxAtTailRight,
    required this.dyAtInnerLeft,
    required this.dyAtInnerRight,
    required this.absAtLidLeft,
    required this.absAtLidRight,
    required this.absAtOuterCreaseLeft,
    required this.absAtOuterCreaseRight,
    required this.absAtHairline,
    required this.eyes,
    required this.nose,
    required this.mouth,
    required this.hairline,
    required this.browActive,
  });

  final double faceWidth;
  final double amplitude;
  final double influenceMax;
  final double outsideBrowZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final double coreCurvature;
  final double entryStep;
  final double dxAtInnerLeft;
  final double dxAtInnerRight;
  final double dxAtArchLeft;
  final double dxAtArchRight;
  final double dxAtTailLeft;
  final double dxAtTailRight;
  final double dyAtInnerLeft;
  final double dyAtInnerRight;
  final double absAtLidLeft;
  final double absAtLidRight;
  final double absAtOuterCreaseLeft;
  final double absAtOuterCreaseRight;
  final double absAtHairline;
  final EyebrowEndRegionStats eyes;
  final EyebrowEndRegionStats nose;
  final EyebrowEndRegionStats mouth;
  final EyebrowEndRegionStats hairline;
  final EyebrowEndRegionStats browActive;

  /// Pontas internas afastam-se da linha média.
  bool get browsSeparate => dxAtInnerLeft > 1e-6 && dxAtInnerRight < -1e-6;

  /// Pontas internas aproximam-se da linha média.
  bool get browsJoin => dxAtInnerLeft < -1e-6 && dxAtInnerRight > 1e-6;

  static const skipped = EyebrowEndFieldMetrics(
    faceWidth: 0,
    amplitude: 0,
    influenceMax: 0,
    outsideBrowZoneP95: 0,
    minDetJ: 1,
    maxNeighborJump: 0,
    coreCurvature: 0,
    entryStep: 0,
    dxAtInnerLeft: 0,
    dxAtInnerRight: 0,
    dxAtArchLeft: 0,
    dxAtArchRight: 0,
    dxAtTailLeft: 0,
    dxAtTailRight: 0,
    dyAtInnerLeft: 0,
    dyAtInnerRight: 0,
    absAtLidLeft: 0,
    absAtLidRight: 0,
    absAtOuterCreaseLeft: 0,
    absAtOuterCreaseRight: 0,
    absAtHairline: 0,
    eyes: EyebrowEndRegionStats.zero,
    nose: EyebrowEndRegionStats.zero,
    mouth: EyebrowEndRegionStats.zero,
    hairline: EyebrowEndRegionStats.zero,
    browActive: EyebrowEndRegionStats.zero,
  );

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'amplitude': amplitude,
        'influenceMax': influenceMax,
        'outsideBrowZoneP95': outsideBrowZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'coreCurvature': coreCurvature,
        'entryStep': entryStep,
        'browsSeparate': browsSeparate,
        'browsJoin': browsJoin,
        'dxAtInnerLeft': dxAtInnerLeft,
        'dxAtInnerRight': dxAtInnerRight,
        'dxAtArchLeft': dxAtArchLeft,
        'dxAtArchRight': dxAtArchRight,
        'dxAtTailLeft': dxAtTailLeft,
        'dxAtTailRight': dxAtTailRight,
        'dyAtInnerLeft': dyAtInnerLeft,
        'dyAtInnerRight': dyAtInnerRight,
        'absAtLidLeft': absAtLidLeft,
        'absAtLidRight': absAtLidRight,
        'absAtOuterCreaseLeft': absAtOuterCreaseLeft,
        'absAtOuterCreaseRight': absAtOuterCreaseRight,
        'absAtHairline': absAtHairline,
        'eyes': eyes.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'hairline': hairline.toJson(),
        'browActive': browActive.toJson(),
      };

  static EyebrowEndFieldMetrics compute({
    required DisplacementField field,
    required EyebrowEndMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double amplitude,
    required int innerLeft,
    required int innerRight,
    required int archLeft,
    required int archRight,
    required int tailLeft,
    required int tailRight,
    required int lidLeft,
    required int lidRight,
    required int hairlineTop,
  }) {
    final width = field.width;
    final height = field.height;
    var influenceMax = 0.0;
    var maxJump = 0.0;
    var minDet = double.infinity;
    var peakComp = 0.0;
    final outside = <double>[];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final mag =
            math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
        if (mag > influenceMax) {
          influenceMax = mag;
        }
        peakComp = math.max(
          peakComp,
          math.max(field.dx[i].abs(), field.dy[i].abs()),
        );
        if (masks.brow[i] == 0) {
          outside.add(mag);
        }
        if (x + 1 < width) {
          final jx = (field.dx[i + 1] - field.dx[i]).abs();
          final jy = (field.dy[i + 1] - field.dy[i]).abs();
          maxJump = math.max(maxJump, math.max(jx, jy));
          final dxx = field.dx[i + 1] - field.dx[i];
          final dyx = field.dy[i + 1] - field.dy[i];
          final dxy = y + 1 < height ? field.dx[i + width] - field.dx[i] : 0.0;
          final dyy = y + 1 < height ? field.dy[i + width] - field.dy[i] : 0.0;
          final det = (1 + dxx) * (1 + dyy) - dxy * dyx;
          if (det < minDet) {
            minDet = det;
          }
        }
      }
    }
    if (minDet.isInfinite) {
      minDet = 1;
    }

    return EyebrowEndFieldMetrics(
      faceWidth: faceWidth,
      amplitude: amplitude,
      influenceMax: influenceMax,
      outsideBrowZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      coreCurvature: _coreCurvature(field, peakComp),
      entryStep: _entryStep(field),
      dxAtInnerLeft: _sampleDx(field, _point(px, innerLeft)),
      dxAtInnerRight: _sampleDx(field, _point(px, innerRight)),
      dxAtArchLeft: _sampleDx(field, _point(px, archLeft)),
      dxAtArchRight: _sampleDx(field, _point(px, archRight)),
      dxAtTailLeft: _sampleDx(field, _point(px, tailLeft)),
      dxAtTailRight: _sampleDx(field, _point(px, tailRight)),
      dyAtInnerLeft: _sampleDy(field, _point(px, innerLeft)),
      dyAtInnerRight: _sampleDy(field, _point(px, innerRight)),
      absAtLidLeft: _absAt(field, px, lidLeft),
      absAtLidRight: _absAt(field, px, lidRight),
      absAtOuterCreaseLeft: _absAtOffset(field, _midpoint(px, 300, 263)),
      absAtOuterCreaseRight: _absAtOffset(field, _midpoint(px, 70, 33)),
      absAtHairline: _absAt(field, px, hairlineTop),
      eyes: statsFor(field, masks.eyes),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      hairline: statsFor(field, masks.hairline),
      browActive: statsFor(field, masks.browActive),
    );
  }

  static EyebrowEndRegionStats statsFor(
    DisplacementField field,
    Uint8List mask,
  ) {
    final values = <double>[];
    var sum = 0.0;
    var maxAbs = 0.0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final mag =
          math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
      values.add(mag);
      sum += mag;
      if (mag > maxAbs) {
        maxAbs = mag;
      }
    }
    if (values.isEmpty) {
      return EyebrowEndRegionStats.zero;
    }
    return EyebrowEndRegionStats(
      pixelCount: values.length,
      maxAbs: maxAbs,
      meanAbs: sum / values.length,
      p95Abs: _p95(values),
    );
  }

  static Offset? _point(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static double _sampleDx(DisplacementField field, Offset? p) {
    if (p == null) {
      return 0;
    }
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return field.dx[field.indexOf(x, y)];
  }

  static double _sampleDy(DisplacementField field, Offset? p) {
    if (p == null) {
      return 0;
    }
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return field.dy[field.indexOf(x, y)];
  }

  static Offset? _midpoint(List<Offset?> px, int a, int b) {
    final p = _point(px, a);
    final q = _point(px, b);
    if (p == null || q == null) {
      return null;
    }
    return Offset((p.dx + q.dx) * 0.5, (p.dy + q.dy) * 0.5);
  }

  static double _absAtOffset(DisplacementField field, Offset? p) {
    if (p == null) {
      return 0;
    }
    final dx = _sampleDx(field, p);
    final dy = _sampleDy(field, p);
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _absAt(DisplacementField field, List<Offset?> px, int id) {
    final p = _point(px, id);
    if (p == null) {
      return 0;
    }
    final dx = _sampleDx(field, p);
    final dy = _sampleDy(field, p);
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _entryStep(DisplacementField field) {
    var worst = 0.0;
    for (var y = 1; y + 1 < field.height; y++) {
      for (var x = 1; x + 1 < field.width; x++) {
        final i = y * field.width + x;
        final v = math.sqrt(
          field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i],
        );
        if (v <= worst) {
          continue;
        }
        for (final j in [i - 1, i + 1, i - field.width, i + field.width]) {
          if (field.dx[j].abs() < 1e-9 && field.dy[j].abs() < 1e-9) {
            worst = v;
            break;
          }
        }
      }
    }
    return worst;
  }

  static double _coreCurvature(DisplacementField field, double peak) {
    if (peak < 1e-6) {
      return 0;
    }
    final gate = 0.25 * peak;
    var worst = 0.0;
    for (var y = 1; y + 1 < field.height; y++) {
      for (var x = 1; x + 1 < field.width; x++) {
        final i = y * field.width + x;
        if (math.max(field.dx[i].abs(), field.dy[i].abs()) < gate) {
          continue;
        }
        for (final v in [field.dx, field.dy]) {
          worst = math.max(
            worst,
            math.max(
              (v[i + 1] - 2 * v[i] + v[i - 1]).abs(),
              (v[i + field.width] - 2 * v[i] + v[i - field.width]).abs(),
            ),
          );
        }
      }
    }
    return worst;
  }

  static double _p95(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return values[i];
  }
}
