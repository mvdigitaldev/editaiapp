import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'hairline_masks.dart';

class HairlineRegionStats {
  const HairlineRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double meanAbs;
  final double p95Abs;

  static const zero = HairlineRegionStats(
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

/// Métricas do Hairline. Não altera [FieldMetrics] (contrato Jaw).
class HairlineFieldMetrics {
  const HairlineFieldMetrics({
    required this.faceWidth,
    required this.hairlineAmplitude,
    required this.influenceMax,
    required this.outsideHairlineZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.primaryHandle,
    required this.hairlineYBefore,
    required this.hairlineYAfter,
    required this.dyAtPrimary,
    required this.dxAtPrimary,
    required this.dyAtCrown,
    required this.dxAtCrown,
    required this.absAtTempleMax,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.cheeks,
    required this.jawDomain,
    required this.temples,
    required this.hairlineActive,
  });

  final double faceWidth;
  final double hairlineAmplitude;
  final double influenceMax;
  final double outsideHairlineZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final int primaryHandle;
  final double hairlineYBefore;
  final double hairlineYAfter;
  final double dyAtPrimary;
  final double dxAtPrimary;
  final double dyAtCrown;
  final double dxAtCrown;
  final double absAtTempleMax;
  final HairlineRegionStats eyes;
  final HairlineRegionStats brows;
  final HairlineRegionStats nose;
  final HairlineRegionStats mouth;
  final HairlineRegionStats faceCenter;
  final HairlineRegionStats ears;
  final HairlineRegionStats cheeks;
  final HairlineRegionStats jawDomain;
  final HairlineRegionStats temples;
  final HairlineRegionStats hairlineActive;

  bool get hairlineInflates => dyAtCrown < -1e-6;

  bool get hairlineDeflates => dyAtCrown > 1e-6;

  static const skipped = HairlineFieldMetrics(
    faceWidth: 0,
    hairlineAmplitude: 0,
    influenceMax: 0,
    outsideHairlineZoneP95: 0,
    minDetJ: 1,
    maxNeighborJump: 0,
    primaryHandle: 10,
    hairlineYBefore: 0,
    hairlineYAfter: 0,
    dyAtPrimary: 0,
    dxAtPrimary: 0,
    dyAtCrown: 0,
    dxAtCrown: 0,
    absAtTempleMax: 0,
    eyes: HairlineRegionStats.zero,
    brows: HairlineRegionStats.zero,
    nose: HairlineRegionStats.zero,
    mouth: HairlineRegionStats.zero,
    faceCenter: HairlineRegionStats.zero,
    ears: HairlineRegionStats.zero,
    cheeks: HairlineRegionStats.zero,
    jawDomain: HairlineRegionStats.zero,
    temples: HairlineRegionStats.zero,
    hairlineActive: HairlineRegionStats.zero,
  );

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'hairlineAmplitude': hairlineAmplitude,
        'influenceMax': influenceMax,
        'outsideHairlineZoneP95': outsideHairlineZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'primaryHandle': primaryHandle,
        'hairlineYBefore': hairlineYBefore,
        'hairlineYAfter': hairlineYAfter,
        'hairlineInflates': hairlineInflates,
        'hairlineDeflates': hairlineDeflates,
        'dyAtPrimary': dyAtPrimary,
        'dxAtPrimary': dxAtPrimary,
        'dyAtCrown': dyAtCrown,
        'dxAtCrown': dxAtCrown,
        'absAtTempleMax': absAtTempleMax,
        'eyes': eyes.toJson(),
        'brows': brows.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'faceCenter': faceCenter.toJson(),
        'ears': ears.toJson(),
        'cheeks': cheeks.toJson(),
        'jawDomain': jawDomain.toJson(),
        'temples': temples.toJson(),
        'hairlineActive': hairlineActive.toJson(),
      };

  static HairlineFieldMetrics compute({
    required DisplacementField field,
    required HairlineMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double hairlineAmplitude,
    required int primaryHandle,
    required Set<int> templeLandmarks,
    Offset? crown,
  }) {
    final width = field.width;
    final height = field.height;
    var influenceMax = 0.0;
    var maxJump = 0.0;
    var minDet = double.infinity;
    final outside = <double>[];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final mag =
            math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
        if (mag > influenceMax) {
          influenceMax = mag;
        }
        if (masks.hairline[i] == 0) {
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

    final primary = _point(px, primaryHandle);
    final dyPrimary = primary == null ? 0.0 : _sampleDy(field, primary);
    final dxPrimary = primary == null ? 0.0 : _sampleDx(field, primary);
    final crownPoint = crown ?? primary;
    final dyCrown = crownPoint == null ? 0.0 : _sampleDy(field, crownPoint);
    final dxCrown = crownPoint == null ? 0.0 : _sampleDx(field, crownPoint);
    final yBefore = crownPoint?.dy ?? 0.0;

    var templeMax = 0.0;
    for (final id in templeLandmarks) {
      templeMax = math.max(templeMax, _absAt(field, px, id));
    }

    return HairlineFieldMetrics(
      faceWidth: faceWidth,
      hairlineAmplitude: hairlineAmplitude,
      influenceMax: influenceMax,
      outsideHairlineZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      primaryHandle: primaryHandle,
      hairlineYBefore: yBefore,
      hairlineYAfter: yBefore + dyCrown,
      dyAtPrimary: dyPrimary,
      dxAtPrimary: dxPrimary,
      dyAtCrown: dyCrown,
      dxAtCrown: dxCrown,
      absAtTempleMax: templeMax,
      eyes: statsFor(field, masks.eyes),
      brows: statsFor(field, masks.brows),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      faceCenter: statsFor(field, masks.faceCenter),
      ears: statsFor(field, masks.ears),
      cheeks: statsFor(field, masks.cheeks),
      jawDomain: statsFor(field, masks.jawDomain),
      temples: statsFor(field, masks.temples),
      hairlineActive: statsFor(field, masks.hairlineActive),
    );
  }

  static HairlineRegionStats statsFor(DisplacementField field, Uint8List mask) {
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
      return HairlineRegionStats.zero;
    }
    return HairlineRegionStats(
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

  static double _sampleDx(DisplacementField field, Offset p) {
    final x = p.dx.round().clamp(0, field.width - 1);
    final y = p.dy.round().clamp(0, field.height - 1);
    return field.dx[field.indexOf(x, y)];
  }

  static double _sampleDy(DisplacementField field, Offset p) {
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

  static double _p95(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    values.sort();
    final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
    return values[i];
  }
}
