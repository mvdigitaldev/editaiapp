import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../displacement_field.dart';
import 'chin_masks.dart';

class ChinRegionStats {
  const ChinRegionStats({
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

/// Métricas do Chin. Não altera [FieldMetrics] (contrato Jaw).
class ChinFieldMetrics {
  const ChinFieldMetrics({
    required this.faceWidth,
    required this.chinAmplitude,
    required this.influenceMax,
    required this.outsideChinZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.primaryHandle,
    required this.chinYBefore,
    required this.chinYAfter,
    required this.dyAtPrimary,
    required this.dxAtPrimary,
    required this.absAtGonionLeft,
    required this.absAtGonionRight,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.ears,
    required this.jawDomain,
    required this.chinActive,
  });

  final double faceWidth;
  final double chinAmplitude;
  final double influenceMax;
  final double outsideChinZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final int primaryHandle;
  final double chinYBefore;
  final double chinYAfter;
  final double dyAtPrimary;
  final double dxAtPrimary;
  final double absAtGonionLeft;
  final double absAtGonionRight;
  final ChinRegionStats eyes;
  final ChinRegionStats brows;
  final ChinRegionStats nose;
  final ChinRegionStats mouth;
  final ChinRegionStats faceCenter;
  final ChinRegionStats ears;
  final ChinRegionStats jawDomain;
  final ChinRegionStats chinActive;

  bool get chinShortens => chinYAfter < chinYBefore - 1e-6;

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'chinAmplitude': chinAmplitude,
        'influenceMax': influenceMax,
        'outsideChinZoneP95': outsideChinZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'primaryHandle': primaryHandle,
        'chinYBefore': chinYBefore,
        'chinYAfter': chinYAfter,
        'chinShortens': chinShortens,
        'dyAtPrimary': dyAtPrimary,
        'dxAtPrimary': dxAtPrimary,
        'absAtGonionLeft': absAtGonionLeft,
        'absAtGonionRight': absAtGonionRight,
        'eyes': eyes.toJson(),
        'brows': brows.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'faceCenter': faceCenter.toJson(),
        'ears': ears.toJson(),
        'jawDomain': jawDomain.toJson(),
        'chinActive': chinActive.toJson(),
      };

  static ChinFieldMetrics compute({
    required DisplacementField field,
    required ChinMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double chinAmplitude,
    required int primaryHandle,
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

    final primary = _point(px, primaryHandle);
    final dyPrimary = primary == null ? 0.0 : _sampleDy(field, primary);
    final dxPrimary = primary == null ? 0.0 : _sampleDx(field, primary);
    final yBefore = primary?.dy ?? 0.0;

    return ChinFieldMetrics(
      faceWidth: faceWidth,
      chinAmplitude: chinAmplitude,
      influenceMax: influenceMax,
      outsideChinZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      primaryHandle: primaryHandle,
      chinYBefore: yBefore,
      chinYAfter: yBefore + dyPrimary,
      dyAtPrimary: dyPrimary,
      dxAtPrimary: dxPrimary,
      absAtGonionLeft: _absAt(field, px, gonionLeft),
      absAtGonionRight: _absAt(field, px, gonionRight),
      eyes: statsFor(field, masks.eyes),
      brows: statsFor(field, masks.brows),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      faceCenter: statsFor(field, masks.faceCenter),
      ears: statsFor(field, masks.ears),
      jawDomain: statsFor(field, masks.jawDomain),
      chinActive: statsFor(field, masks.chinActive),
    );
  }

  static ChinRegionStats statsFor(DisplacementField field, Uint8List mask) {
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
      return const ChinRegionStats(
        pixelCount: 0,
        maxAbs: 0,
        meanAbs: 0,
        p95Abs: 0,
      );
    }
    return ChinRegionStats(
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
