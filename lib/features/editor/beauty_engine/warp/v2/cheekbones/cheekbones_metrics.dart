import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'cheekbones_masks.dart';

class CheekbonesRegionStats {
  const CheekbonesRegionStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  final int pixelCount;
  final double maxAbs;
  final double meanAbs;
  final double p95Abs;

  Map<String, Object> toJson() => {
        'pixelCount': pixelCount,
        'maxAbs': maxAbs,
        'meanAbs': meanAbs,
        'p95Abs': p95Abs,
      };
}

/// Métricas do Cheekbones. Não altera [FieldMetrics] (contrato Jaw).
class CheekbonesFieldMetrics {
  const CheekbonesFieldMetrics({
    required this.faceWidth,
    required this.cheekAmplitude,
    required this.influenceMax,
    required this.outsideCheekZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.primaryLeft,
    required this.primaryRight,
    required this.malarWidthBefore,
    required this.malarWidthAfter,
    required this.dxAtPrimaryLeft,
    required this.dxAtPrimaryRight,
    required this.dyAtPrimaryLeft,
    required this.dyAtPrimaryRight,
    required this.absAtGonionLeft,
    required this.absAtGonionRight,
    required this.absAtChinTip,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinDomain,
    required this.cheekActive,
  });

  final double faceWidth;
  final double cheekAmplitude;
  final double influenceMax;
  final double outsideCheekZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final int primaryLeft;
  final int primaryRight;
  final double malarWidthBefore;
  final double malarWidthAfter;
  final double dxAtPrimaryLeft;
  final double dxAtPrimaryRight;
  final double dyAtPrimaryLeft;
  final double dyAtPrimaryRight;
  final double absAtGonionLeft;
  final double absAtGonionRight;
  final double absAtChinTip;
  final CheekbonesRegionStats eyes;
  final CheekbonesRegionStats brows;
  final CheekbonesRegionStats nose;
  final CheekbonesRegionStats mouth;
  final CheekbonesRegionStats faceCenter;
  final CheekbonesRegionStats ears;
  final CheekbonesRegionStats jawDomain;
  final CheekbonesRegionStats chinDomain;
  final CheekbonesRegionStats cheekActive;

  bool get cheekbonesNarrows => malarWidthAfter < malarWidthBefore - 1e-6;

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'cheekAmplitude': cheekAmplitude,
        'influenceMax': influenceMax,
        'outsideCheekZoneP95': outsideCheekZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'primaryLeft': primaryLeft,
        'primaryRight': primaryRight,
        'malarWidthBefore': malarWidthBefore,
        'malarWidthAfter': malarWidthAfter,
        'cheekbonesNarrows': cheekbonesNarrows,
        'dxAtPrimaryLeft': dxAtPrimaryLeft,
        'dxAtPrimaryRight': dxAtPrimaryRight,
        'dyAtPrimaryLeft': dyAtPrimaryLeft,
        'dyAtPrimaryRight': dyAtPrimaryRight,
        'absAtGonionLeft': absAtGonionLeft,
        'absAtGonionRight': absAtGonionRight,
        'absAtChinTip': absAtChinTip,
        'eyes': eyes.toJson(),
        'brows': brows.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'faceCenter': faceCenter.toJson(),
        'ears': ears.toJson(),
        'jawDomain': jawDomain.toJson(),
        'chinDomain': chinDomain.toJson(),
        'cheekActive': cheekActive.toJson(),
      };

  static CheekbonesFieldMetrics compute({
    required DisplacementField field,
    required CheekbonesMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double cheekAmplitude,
    required int primaryLeft,
    required int primaryRight,
    required int gonionLeft,
    required int gonionRight,
    required int chinTip,
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
        if (masks.cheek[i] == 0) {
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

    return CheekbonesFieldMetrics(
      faceWidth: faceWidth,
      cheekAmplitude: cheekAmplitude,
      influenceMax: influenceMax,
      outsideCheekZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      primaryLeft: primaryLeft,
      primaryRight: primaryRight,
      malarWidthBefore: widthBefore,
      malarWidthAfter: widthAfter,
      dxAtPrimaryLeft: dxLeft,
      dxAtPrimaryRight: dxRight,
      dyAtPrimaryLeft: dyLeft,
      dyAtPrimaryRight: dyRight,
      absAtGonionLeft: _absAt(field, px, gonionLeft),
      absAtGonionRight: _absAt(field, px, gonionRight),
      absAtChinTip: _absAt(field, px, chinTip),
      eyes: statsFor(field, masks.eyes),
      brows: statsFor(field, masks.brows),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      faceCenter: statsFor(field, masks.faceCenter),
      ears: statsFor(field, masks.ears),
      jawDomain: statsFor(field, masks.jawDomain),
      chinDomain: statsFor(field, masks.chinDomain),
      cheekActive: statsFor(field, masks.cheekActive),
    );
  }

  static CheekbonesRegionStats statsFor(DisplacementField field, Uint8List mask) {
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
      return const CheekbonesRegionStats(
        pixelCount: 0,
        maxAbs: 0,
        meanAbs: 0,
        p95Abs: 0,
      );
    }
    return CheekbonesRegionStats(
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
