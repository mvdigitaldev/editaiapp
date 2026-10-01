import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'lip_height_masks.dart';

class LipHeightRegionStats {
  const LipHeightRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double p95Abs;

  static const zero = LipHeightRegionStats(
    pixelCount: 0,
    maxAbs: 0,
    p95Abs: 0,
  );
}

/// Métricas da Altura dos lábios. Não altera [FieldMetrics].
class LipHeightFieldMetrics {
  const LipHeightFieldMetrics({
    required this.faceWidth,
    required this.influenceMax,
    required this.minDetJ,
    required this.coreCurvature,
    required this.entryStep,
    required this.dyAtUpper,
    required this.dyAtLower,
    required this.dxAtUpper,
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
  final double dyAtUpper;
  final double dyAtLower;
  final double dxAtUpper;
  final double absAtNoseTip;
  final double absAtChin;
  final double absAtIrisLeft;
  final double absAtIrisRight;
  final double absAtBrow;
  final double absAtHairline;
  final LipHeightRegionStats eyes;
  final LipHeightRegionStats nose;

  /// t>0: boca sobe (y da imagem desce).
  bool get mouthLifts => dyAtUpper < -0.3 && dyAtLower < -0.3;

  /// t<0: boca desce.
  bool get mouthDrops => dyAtUpper > 0.3 && dyAtLower > 0.3;

  static const skipped = LipHeightFieldMetrics(
    faceWidth: 1,
    influenceMax: 0,
    minDetJ: 1,
    coreCurvature: 0,
    entryStep: 0,
    dyAtUpper: 0,
    dyAtLower: 0,
    dxAtUpper: 0,
    absAtNoseTip: 0,
    absAtChin: 0,
    absAtIrisLeft: 0,
    absAtIrisRight: 0,
    absAtBrow: 0,
    absAtHairline: 0,
    eyes: LipHeightRegionStats.zero,
    nose: LipHeightRegionStats.zero,
  );

  static LipHeightFieldMetrics compute({
    required DisplacementField field,
    required LipHeightMasks masks,
    required List<Offset?> px,
    required double faceWidth,
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

    return LipHeightFieldMetrics(
      faceWidth: faceWidth,
      influenceMax: influenceMax,
      minDetJ: minDet,
      coreCurvature: _coreCurvature(field, influenceMax),
      entryStep: _entryStep(field),
      dyAtUpper: _dyAt(field, px, 0),
      dyAtLower: _dyAt(field, px, 17),
      dxAtUpper: _dxAt(field, px, 0),
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
    final dx = _sample(field.dx, field, p);
    final dy = _sample(field.dy, field, p);
    return math.sqrt(dx * dx + dy * dy);
  }

  static LipHeightRegionStats _stats(DisplacementField field, Uint8List mask) {
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
      return LipHeightRegionStats.zero;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return LipHeightRegionStats(
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
