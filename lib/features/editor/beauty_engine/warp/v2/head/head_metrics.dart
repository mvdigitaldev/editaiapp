import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'head_masks.dart';

class HeadRegionStats {
  const HeadRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double meanAbs;
  final double p95Abs;

  static const zero = HeadRegionStats(
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

/// Métricas do Head. Não altera [FieldMetrics] (contrato Jaw).
class HeadFieldMetrics {
  const HeadFieldMetrics({
    required this.faceWidth,
    required this.scale,
    required this.alpha,
    required this.influenceMax,
    required this.outsideHeadP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.coreCurvature,
    required this.entryStep,
    required this.dxAt152,
    required this.dyAt152,
    required this.absAtGonionLeft,
    required this.absAtGonionRight,
    required this.headActive,
  });

  final double faceWidth;
  final double scale;
  final double alpha;
  final double influenceMax;
  final double outsideHeadP95;
  final double minDetJ;
  final double maxNeighborJump;
  final double coreCurvature;
  final double entryStep;
  final double dxAt152;
  final double dyAt152;
  final double absAtGonionLeft;
  final double absAtGonionRight;
  final HeadRegionStats headActive;

  bool get headGrows => scale > 1 + 1e-6;

  bool get headShrinks => scale < 1 - 1e-6;

  static const skipped = HeadFieldMetrics(
    faceWidth: 0,
    scale: 1,
    alpha: 0,
    influenceMax: 0,
    outsideHeadP95: 0,
    minDetJ: 1,
    maxNeighborJump: 0,
    coreCurvature: 0,
    entryStep: 0,
    dxAt152: 0,
    dyAt152: 0,
    absAtGonionLeft: 0,
    absAtGonionRight: 0,
    headActive: HeadRegionStats.zero,
  );

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'scale': scale,
        'alpha': alpha,
        'influenceMax': influenceMax,
        'outsideHeadP95': outsideHeadP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'coreCurvature': coreCurvature,
        'entryStep': entryStep,
        'headGrows': headGrows,
        'headShrinks': headShrinks,
        'dxAt152': dxAt152,
        'dyAt152': dyAt152,
        'absAtGonionLeft': absAtGonionLeft,
        'absAtGonionRight': absAtGonionRight,
        'headActive': headActive.toJson(),
      };

  static HeadFieldMetrics compute({
    required DisplacementField field,
    required HeadMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double scale,
    required double alpha,
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
        if (masks.headActive[i] == 0) {
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

    return HeadFieldMetrics(
      faceWidth: faceWidth,
      scale: scale,
      alpha: alpha,
      influenceMax: influenceMax,
      outsideHeadP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      coreCurvature: _coreCurvature(field, peakComp),
      entryStep: _entryStep(field),
      dxAt152: _sampleDx(field, _point(px, 152)),
      dyAt152: _sampleDy(field, _point(px, 152)),
      absAtGonionLeft: _absAt(field, px, 58),
      absAtGonionRight: _absAt(field, px, 288),
      headActive: statsFor(field, masks.headActive),
    );
  }

  static HeadRegionStats statsFor(DisplacementField field, Uint8List mask) {
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
      return HeadRegionStats.zero;
    }
    return HeadRegionStats(
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
