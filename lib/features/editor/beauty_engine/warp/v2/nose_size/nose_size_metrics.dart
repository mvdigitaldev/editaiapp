import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'nose_size_masks.dart';

class NoseSizeRegionStats {
  const NoseSizeRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double p95Abs;

  static const zero = NoseSizeRegionStats(
    pixelCount: 0,
    maxAbs: 0,
    p95Abs: 0,
  );
}

/// Métricas do Tamanho do nariz. Não altera [FieldMetrics].
class NoseSizeFieldMetrics {
  const NoseSizeFieldMetrics({
    required this.faceWidth,
    required this.influenceMax,
    required this.minDetJ,
    required this.coreCurvature,
    required this.entryStep,
    required this.radialAtTip,
    required this.radialAtAlaLeft,
    required this.radialAtAlaRight,
    required this.absAtCenter,
    required this.absAtIrisLeft,
    required this.absAtIrisRight,
    required this.absAtBrow,
    required this.absAtMouth,
    required this.absAtHairline,
    required this.eyes,
    required this.mouth,
  });

  final double faceWidth;
  final double influenceMax;
  final double minDetJ;
  final double coreCurvature;
  final double entryStep;

  /// Componente ao longo de (ponta − centro). Positivo = afasta-se.
  final double radialAtTip;
  final double radialAtAlaLeft;
  final double radialAtAlaRight;
  final double absAtCenter;
  final double absAtIrisLeft;
  final double absAtIrisRight;
  final double absAtBrow;
  final double absAtMouth;
  final double absAtHairline;
  final NoseSizeRegionStats eyes;
  final NoseSizeRegionStats mouth;

  bool get noseEnlarges =>
      radialAtTip > 0.4 && radialAtAlaLeft > 0.3 && radialAtAlaRight > 0.3;

  bool get noseShrinks =>
      radialAtTip < -0.4 && radialAtAlaLeft < -0.3 && radialAtAlaRight < -0.3;

  static const skipped = NoseSizeFieldMetrics(
    faceWidth: 1,
    influenceMax: 0,
    minDetJ: 1,
    coreCurvature: 0,
    entryStep: 0,
    radialAtTip: 0,
    radialAtAlaLeft: 0,
    radialAtAlaRight: 0,
    absAtCenter: 0,
    absAtIrisLeft: 0,
    absAtIrisRight: 0,
    absAtBrow: 0,
    absAtMouth: 0,
    absAtHairline: 0,
    eyes: NoseSizeRegionStats.zero,
    mouth: NoseSizeRegionStats.zero,
  );

  static NoseSizeFieldMetrics compute({
    required DisplacementField field,
    required NoseSizeMasks masks,
    required List<Offset?> px,
    required Offset center,
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

    return NoseSizeFieldMetrics(
      faceWidth: faceWidth,
      influenceMax: influenceMax,
      minDetJ: minDet,
      coreCurvature: _coreCurvature(field, influenceMax),
      entryStep: _entryStep(field),
      radialAtTip: _radial(field, px, center, 1),
      radialAtAlaLeft: _radial(field, px, center, 98),
      radialAtAlaRight: _radial(field, px, center, 327),
      absAtCenter: _absAtOffset(field, center),
      absAtIrisLeft: _absAt(field, px, 468),
      absAtIrisRight: _absAt(field, px, 473),
      absAtBrow: _absAt(field, px, 105),
      absAtMouth: _absAt(field, px, 13),
      absAtHairline: _absAt(field, px, 10),
      eyes: _stats(field, masks.eyes),
      mouth: _stats(field, masks.mouth),
    );
  }

  static double _radial(
    DisplacementField field,
    List<Offset?> px,
    Offset center,
    int pointId,
  ) {
    final p = _point(px, pointId);
    if (p == null) {
      return 0;
    }
    final vx = p.dx - center.dx;
    final vy = p.dy - center.dy;
    final len = math.sqrt(vx * vx + vy * vy);
    if (len < 1e-6) {
      return 0;
    }
    final dx = _sample(field.dx, field, p);
    final dy = _sample(field.dy, field, p);
    return (dx * vx + dy * vy) / len;
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

  static NoseSizeRegionStats _stats(DisplacementField field, Uint8List mask) {
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
      return NoseSizeRegionStats.zero;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return NoseSizeRegionStats(
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
