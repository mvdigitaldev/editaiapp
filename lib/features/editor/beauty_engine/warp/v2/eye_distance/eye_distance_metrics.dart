import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'eye_distance_masks.dart';

class EyeDistanceRegionStats {
  const EyeDistanceRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double p95Abs;

  static const zero = EyeDistanceRegionStats(
    pixelCount: 0,
    maxAbs: 0,
    p95Abs: 0,
  );
}

/// Métricas da Distância dos olhos. Não altera [FieldMetrics].
class EyeDistanceFieldMetrics {
  const EyeDistanceFieldMetrics({
    required this.faceWidth,
    required this.influenceMax,
    required this.minDetJ,
    required this.coreCurvature,
    required this.entryStep,
    required this.dxAtCenterLeft,
    required this.dxAtCenterRight,
    required this.dxAtOuterLeft,
    required this.dxAtOuterRight,
    required this.dxAtLidLeft,
    required this.dxAtLidRight,
    required this.absAtBrowLeft,
    required this.absAtBrowRight,
    required this.absAtHairline,
    required this.nose,
    required this.mouth,
  });

  final double faceWidth;
  final double influenceMax;
  final double minDetJ;
  final double coreCurvature;
  final double entryStep;

  /// `dx` em pixels. Negativo na foto esquerda afasta; positivo aproxima.
  final double dxAtCenterLeft;
  final double dxAtCenterRight;
  final double dxAtOuterLeft;
  final double dxAtOuterRight;
  final double dxAtLidLeft;
  final double dxAtLidRight;
  final double absAtBrowLeft;
  final double absAtBrowRight;
  final double absAtHairline;
  final EyeDistanceRegionStats nose;
  final EyeDistanceRegionStats mouth;

  bool get eyesApart => dxAtCenterLeft < -0.4 && dxAtCenterRight > 0.4;

  bool get eyesTogether => dxAtCenterLeft > 0.4 && dxAtCenterRight < -0.4;

  static const skipped = EyeDistanceFieldMetrics(
    faceWidth: 1,
    influenceMax: 0,
    minDetJ: 1,
    coreCurvature: 0,
    entryStep: 0,
    dxAtCenterLeft: 0,
    dxAtCenterRight: 0,
    dxAtOuterLeft: 0,
    dxAtOuterRight: 0,
    dxAtLidLeft: 0,
    dxAtLidRight: 0,
    absAtBrowLeft: 0,
    absAtBrowRight: 0,
    absAtHairline: 0,
    nose: EyeDistanceRegionStats.zero,
    mouth: EyeDistanceRegionStats.zero,
  );

  static EyeDistanceFieldMetrics compute({
    required DisplacementField field,
    required EyeDistanceMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required int centerLeft,
    required int centerRight,
    required int outerLeft,
    required int outerRight,
    required int lidLeft,
    required int lidRight,
    required int browLeft,
    required int browRight,
    required int hairlineTop,
  }) {
    var influenceMax = 0.0;
    var minDet = double.infinity;
    for (var y = 0; y < field.height; y++) {
      for (var x = 0; x < field.width; x++) {
        final i = y * field.width + x;
        final mag = math.sqrt(
          field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i],
        );
        if (mag > influenceMax) {
          influenceMax = mag;
        }
        if (x + 1 >= field.width) {
          continue;
        }
        final dxx = field.dx[i + 1] - field.dx[i];
        final dyx = field.dy[i + 1] - field.dy[i];
        final dxy = y + 1 < field.height
            ? field.dx[i + field.width] - field.dx[i]
            : 0.0;
        final dyy = y + 1 < field.height
            ? field.dy[i + field.width] - field.dy[i]
            : 0.0;
        final det = (1 + dxx) * (1 + dyy) - dxy * dyx;
        if (det < minDet) {
          minDet = det;
        }
      }
    }
    if (minDet.isInfinite) {
      minDet = 1;
    }

    return EyeDistanceFieldMetrics(
      faceWidth: faceWidth,
      influenceMax: influenceMax,
      minDetJ: minDet,
      coreCurvature: _coreCurvature(field, influenceMax),
      entryStep: _entryStep(field),
      dxAtCenterLeft: _dxAt(field, px, centerLeft),
      dxAtCenterRight: _dxAt(field, px, centerRight),
      dxAtOuterLeft: _dxAt(field, px, outerLeft),
      dxAtOuterRight: _dxAt(field, px, outerRight),
      dxAtLidLeft: _dxAt(field, px, lidLeft),
      dxAtLidRight: _dxAt(field, px, lidRight),
      absAtBrowLeft: _absAt(field, px, browLeft),
      absAtBrowRight: _absAt(field, px, browRight),
      absAtHairline: _absAt(field, px, hairlineTop),
      nose: _stats(field, masks.nose),
      mouth: _stats(field, masks.mouth),
    );
  }

  static double _dxAt(DisplacementField field, List<Offset?> px, int id) {
    final p = _point(px, id);
    if (p == null) {
      return 0;
    }
    return _sample(field.dx, field, p);
  }

  static Offset? _point(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static double _sample(
    Float32List channel,
    DisplacementField field,
    Offset p,
  ) {
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return channel[field.indexOf(x, y)];
  }

  static double _absAt(DisplacementField field, List<Offset?> px, int id) {
    return _dxAt(field, px, id).abs();
  }

  static EyeDistanceRegionStats _stats(
    DisplacementField field,
    Uint8List mask,
  ) {
    final values = <double>[];
    var maxAbs = 0.0;
    final n = math.min(mask.length, field.pixelCount);
    for (var i = 0; i < n; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final mag = field.dx[i].abs();
      values.add(mag);
      if (mag > maxAbs) {
        maxAbs = mag;
      }
    }
    if (values.isEmpty) {
      return EyeDistanceRegionStats.zero;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return EyeDistanceRegionStats(
      pixelCount: values.length,
      maxAbs: maxAbs,
      p95Abs: values[i],
    );
  }

  static double _entryStep(DisplacementField field) {
    var worst = 0.0;
    for (var y = 1; y + 1 < field.height; y++) {
      for (var x = 1; x + 1 < field.width; x++) {
        final i = y * field.width + x;
        final v = field.dx[i].abs();
        if (v <= worst) {
          continue;
        }
        for (final j in [i - 1, i + 1, i - field.width, i + field.width]) {
          if (field.dx[j].abs() < 1e-9) {
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
        if (field.dx[i].abs() < gate) {
          continue;
        }
        final v = field.dx;
        worst = math.max(
          worst,
          math.max(
            (v[i + 1] - 2 * v[i] + v[i - 1]).abs(),
            (v[i + field.width] - 2 * v[i] + v[i - field.width]).abs(),
          ),
        );
      }
    }
    return worst;
  }
}
