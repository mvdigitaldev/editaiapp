import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'v_chin_masks.dart';

class VChinRegionStats {
  const VChinRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double meanAbs;
  final double p95Abs;

  static const zero = VChinRegionStats(
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

/// Métricas do V Chin. Não altera [FieldMetrics] (contrato Jaw).
class VChinFieldMetrics {
  const VChinFieldMetrics({
    required this.faceWidth,
    required this.vChinAmplitude,
    required this.influenceMax,
    required this.outsideChinZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.primaryLeft,
    required this.primaryRight,
    required this.chinWidthBefore,
    required this.chinWidthAfter,
    required this.dxAtPrimaryLeft,
    required this.dxAtPrimaryRight,
    required this.dyAtPrimaryLeft,
    required this.dyAtPrimaryRight,
    required this.absAtChinTip,
    required this.absAtGonionLeft,
    required this.absAtGonionRight,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinTip,
    required this.chinActive,
  });

  final double faceWidth;
  final double vChinAmplitude;
  final double influenceMax;
  final double outsideChinZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final int primaryLeft;
  final int primaryRight;
  final double chinWidthBefore;
  final double chinWidthAfter;
  final double dxAtPrimaryLeft;
  final double dxAtPrimaryRight;
  final double dyAtPrimaryLeft;
  final double dyAtPrimaryRight;
  final double absAtChinTip;
  final double absAtGonionLeft;
  final double absAtGonionRight;
  final VChinRegionStats eyes;
  final VChinRegionStats brows;
  final VChinRegionStats nose;
  final VChinRegionStats mouth;
  final VChinRegionStats faceCenter;
  final VChinRegionStats ears;
  final VChinRegionStats jawDomain;
  final VChinRegionStats chinTip;
  final VChinRegionStats chinActive;

  bool get vChinSharpens => chinWidthAfter < chinWidthBefore - 1e-6;

  bool get vChinSquares => chinWidthAfter > chinWidthBefore + 1e-6;

  static const skipped = VChinFieldMetrics(
    faceWidth: 0,
    vChinAmplitude: 0,
    influenceMax: 0,
    outsideChinZoneP95: 0,
    minDetJ: 1,
    maxNeighborJump: 0,
    primaryLeft: 148,
    primaryRight: 377,
    chinWidthBefore: 0,
    chinWidthAfter: 0,
    dxAtPrimaryLeft: 0,
    dxAtPrimaryRight: 0,
    dyAtPrimaryLeft: 0,
    dyAtPrimaryRight: 0,
    absAtChinTip: 0,
    absAtGonionLeft: 0,
    absAtGonionRight: 0,
    eyes: VChinRegionStats.zero,
    brows: VChinRegionStats.zero,
    nose: VChinRegionStats.zero,
    mouth: VChinRegionStats.zero,
    faceCenter: VChinRegionStats.zero,
    ears: VChinRegionStats.zero,
    jawDomain: VChinRegionStats.zero,
    chinTip: VChinRegionStats.zero,
    chinActive: VChinRegionStats.zero,
  );

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'vChinAmplitude': vChinAmplitude,
        'influenceMax': influenceMax,
        'outsideChinZoneP95': outsideChinZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'primaryLeft': primaryLeft,
        'primaryRight': primaryRight,
        'chinWidthBefore': chinWidthBefore,
        'chinWidthAfter': chinWidthAfter,
        'vChinSharpens': vChinSharpens,
        'vChinSquares': vChinSquares,
        'dxAtPrimaryLeft': dxAtPrimaryLeft,
        'dxAtPrimaryRight': dxAtPrimaryRight,
        'dyAtPrimaryLeft': dyAtPrimaryLeft,
        'dyAtPrimaryRight': dyAtPrimaryRight,
        'absAtChinTip': absAtChinTip,
        'absAtGonionLeft': absAtGonionLeft,
        'absAtGonionRight': absAtGonionRight,
        'eyes': eyes.toJson(),
        'brows': brows.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'faceCenter': faceCenter.toJson(),
        'ears': ears.toJson(),
        'jawDomain': jawDomain.toJson(),
        'chinTip': chinTip.toJson(),
        'chinActive': chinActive.toJson(),
      };

  static VChinFieldMetrics compute({
    required DisplacementField field,
    required VChinMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double vChinAmplitude,
    required int primaryLeft,
    required int primaryRight,
    required int chinTip,
    required int gonionLeft,
    required int gonionRight,
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
        final mag = math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
        if (mag > influenceMax) {
          influenceMax = mag;
        }
        if (masks.chin[i] == 0) {
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

    final left = _point(px, primaryLeft);
    final right = _point(px, primaryRight);
    final dxLeft = left == null ? 0.0 : _sampleDx(field, left);
    final dxRight = right == null ? 0.0 : _sampleDx(field, right);
    final dyLeft = left == null ? 0.0 : _sampleDy(field, left);
    final dyRight = right == null ? 0.0 : _sampleDy(field, right);
    final widthBefore =
        (left == null || right == null) ? 0.0 : (right.dx - left.dx).abs();
    final widthAfter = (left == null || right == null)
        ? 0.0
        : ((right.dx + dxRight) - (left.dx + dxLeft)).abs();

    return VChinFieldMetrics(
      faceWidth: faceWidth,
      vChinAmplitude: vChinAmplitude,
      influenceMax: influenceMax,
      outsideChinZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      primaryLeft: primaryLeft,
      primaryRight: primaryRight,
      chinWidthBefore: widthBefore,
      chinWidthAfter: widthAfter,
      dxAtPrimaryLeft: dxLeft,
      dxAtPrimaryRight: dxRight,
      dyAtPrimaryLeft: dyLeft,
      dyAtPrimaryRight: dyRight,
      absAtChinTip: _absAt(field, px, chinTip),
      absAtGonionLeft: _absAt(field, px, gonionLeft),
      absAtGonionRight: _absAt(field, px, gonionRight),
      eyes: statsFor(field, masks.eyes),
      brows: statsFor(field, masks.brows),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      faceCenter: statsFor(field, masks.faceCenter),
      ears: statsFor(field, masks.ears),
      jawDomain: statsFor(field, masks.jawDomain),
      chinTip: statsFor(field, masks.chinTip),
      chinActive: statsFor(field, masks.chinActive),
    );
  }

  static VChinRegionStats statsFor(DisplacementField field, Uint8List mask) {
    final values = <double>[];
    var sum = 0.0;
    var maxAbs = 0.0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) {
        continue;
      }
      final mag = math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
      values.add(mag);
      sum += mag;
      if (mag > maxAbs) {
        maxAbs = mag;
      }
    }
    if (values.isEmpty) {
      return VChinRegionStats.zero;
    }
    return VChinRegionStats(
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
