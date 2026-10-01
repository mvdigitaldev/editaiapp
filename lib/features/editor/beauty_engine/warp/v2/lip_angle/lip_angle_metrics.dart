import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'lip_angle_masks.dart';

class LipAngleRegionStats {
  const LipAngleRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double p95Abs;

  static const zero = LipAngleRegionStats(
    pixelCount: 0,
    maxAbs: 0,
    p95Abs: 0,
  );
}

/// Métricas do Ângulo dos lábios. Não altera [FieldMetrics].
class LipAngleFieldMetrics {
  const LipAngleFieldMetrics({
    required this.faceWidth,
    required this.influenceMax,
    required this.minDetJ,
    required this.coreCurvature,
    required this.entryStep,
    required this.dyAtCornerLeft,
    required this.dyAtCornerRight,
    required this.dxAtCornerLeft,
    required this.dxAtCornerRight,
    required this.maxAbsDx,
    required this.maxAbsDy,
    required this.absAtCenter,
    required this.absAtNoseTip,
    required this.absAtChin,
    required this.absAtIrisLeft,
    required this.absAtIrisRight,
    required this.absAtBrow,
    required this.absAtHairline,
    required this.eyes,
    required this.nose,
  });

  final double faceWidth;
  final double influenceMax;
  final double minDetJ;
  final double coreCurvature;
  final double entryStep;
  final double dyAtCornerLeft;
  final double dyAtCornerRight;
  final double dxAtCornerLeft;
  final double dxAtCornerRight;
  final double maxAbsDx;
  final double maxAbsDy;
  final double absAtCenter;
  final double absAtNoseTip;
  final double absAtChin;
  final double absAtIrisLeft;
  final double absAtIrisRight;
  final double absAtBrow;
  final double absAtHairline;
  final LipAngleRegionStats eyes;
  final LipAngleRegionStats nose;

  /// t>0: canto da foto à esquerda desce, o da direita sobe.
  bool get angleTiltsRight =>
      dyAtCornerLeft > 0.3 && dyAtCornerRight < -0.3;

  /// t<0: canto da foto à esquerda sobe, o da direita desce.
  bool get angleTiltsLeft =>
      dyAtCornerLeft < -0.3 && dyAtCornerRight > 0.3;

  /// O campo tem as duas componentes — não é só Δy da Altura.
  bool get movesDiagonally => maxAbsDx > 0.3 && maxAbsDy > 0.3;

  static const skipped = LipAngleFieldMetrics(
    faceWidth: 1,
    influenceMax: 0,
    minDetJ: 1,
    coreCurvature: 0,
    entryStep: 0,
    dyAtCornerLeft: 0,
    dyAtCornerRight: 0,
    dxAtCornerLeft: 0,
    dxAtCornerRight: 0,
    maxAbsDx: 0,
    maxAbsDy: 0,
    absAtCenter: 0,
    absAtNoseTip: 0,
    absAtChin: 0,
    absAtIrisLeft: 0,
    absAtIrisRight: 0,
    absAtBrow: 0,
    absAtHairline: 0,
    eyes: LipAngleRegionStats.zero,
    nose: LipAngleRegionStats.zero,
  );

  static LipAngleFieldMetrics compute({
    required DisplacementField field,
    required LipAngleMasks masks,
    required List<Offset?> px,
    required Offset center,
    required double faceWidth,
  }) {
    var influenceMax = 0.0;
    var maxAbsDx = 0.0;
    var maxAbsDy = 0.0;
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
        maxAbsDx = math.max(maxAbsDx, field.dx[i].abs());
        maxAbsDy = math.max(maxAbsDy, field.dy[i].abs());
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

    return LipAngleFieldMetrics(
      faceWidth: faceWidth,
      influenceMax: influenceMax,
      minDetJ: minDet,
      coreCurvature: _coreCurvature(field, influenceMax),
      entryStep: _entryStep(field),
      dyAtCornerLeft: _dyAt(field, px, 61),
      dyAtCornerRight: _dyAt(field, px, 291),
      dxAtCornerLeft: _dxAt(field, px, 61),
      dxAtCornerRight: _dxAt(field, px, 291),
      maxAbsDx: maxAbsDx,
      maxAbsDy: maxAbsDy,
      absAtCenter: _absAtOffset(field, center),
      absAtNoseTip: _absAt(field, px, 1),
      absAtChin: _absAt(field, px, 152),
      absAtIrisLeft: _absAt(field, px, 468),
      absAtIrisRight: _absAt(field, px, 473),
      absAtBrow: _absAt(field, px, 105),
      absAtHairline: _absAt(field, px, 10),
      eyes: _stats(field, masks.eyes),
      nose: _stats(field, masks.nose),
    );
  }

  static Offset? _point(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static double _sample(
      Float32List channel, DisplacementField field, Offset p) {
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return channel[field.indexOf(x, y)];
  }

  static double _dxAt(DisplacementField field, List<Offset?> px, int id) {
    final p = _point(px, id);
    if (p == null) {
      return 0;
    }
    return _sample(field.dx, field, p);
  }

  static double _dyAt(DisplacementField field, List<Offset?> px, int id) {
    final p = _point(px, id);
    if (p == null) {
      return 0;
    }
    return _sample(field.dy, field, p);
  }

  static double _absAt(DisplacementField field, List<Offset?> px, int id) {
    final p = _point(px, id);
    if (p == null) {
      return 0;
    }
    return _absAtOffset(field, p);
  }

  static double _absAtOffset(DisplacementField field, Offset p) {
    final dx = _sample(field.dx, field, p);
    final dy = _sample(field.dy, field, p);
    return math.sqrt(dx * dx + dy * dy);
  }

  static LipAngleRegionStats _stats(DisplacementField field, Uint8List mask) {
    final values = <double>[];
    var maxAbs = 0.0;
    final n = math.min(mask.length, field.pixelCount);
    for (var i = 0; i < n; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final mag = math.sqrt(
        field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i],
      );
      values.add(mag);
      if (mag > maxAbs) {
        maxAbs = mag;
      }
    }
    if (values.isEmpty) {
      return LipAngleRegionStats.zero;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return LipAngleRegionStats(
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
        final mag = math.sqrt(
          field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i],
        );
        if (mag < gate) {
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
}
