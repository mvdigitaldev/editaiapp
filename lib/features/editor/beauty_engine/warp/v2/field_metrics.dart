import 'dart:math' as math;
import 'dart:typed_data';

import 'displacement_field.dart';
import 'region_masks.dart';

class RegionDisplacementStats {
  const RegionDisplacementStats({
    required this.pixelCount,
    required this.maxAbs,
    required this.meanAbs,
    required this.p95Abs,
  });

  static const zero = RegionDisplacementStats(
    pixelCount: 0,
    maxAbs: 0,
    meanAbs: 0,
    p95Abs: 0,
  );

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

/// Métricas do campo (sem RGBA).
class FieldMetrics {
  const FieldMetrics({
    required this.faceWidth,
    required this.jawAmplitude,
    required this.influenceMax,
    required this.outsideJawZoneP95,
    required this.minDetJ,
    required this.maxNeighborJump,
    required this.jawWidthBefore,
    required this.jawWidthAfter,
    required this.gonionWidthBefore,
    required this.gonionWidthAfter,
    required this.dxAtGonionLeft,
    required this.dxAtGonionRight,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.beard,
    required this.ears,
    required this.jawActive,
  });

  final double faceWidth;
  final double jawAmplitude;
  final double influenceMax;
  final double outsideJawZoneP95;
  final double minDetJ;
  final double maxNeighborJump;
  final double jawWidthBefore;
  final double jawWidthAfter;
  final double gonionWidthBefore;
  final double gonionWidthAfter;
  final double dxAtGonionLeft;
  final double dxAtGonionRight;
  final RegionDisplacementStats eyes;
  final RegionDisplacementStats brows;
  final RegionDisplacementStats nose;
  final RegionDisplacementStats mouth;
  final RegionDisplacementStats faceCenter;
  final RegionDisplacementStats beard;
  final RegionDisplacementStats ears;
  final RegionDisplacementStats jawActive;

  /// Marcador para quem constrói o campo só para o render e não lê métricas.
  /// Percorrer a imagem inteira a medir regiões custa mais do que reescalar o
  /// campo, e a cadeia de preview não usa nada disto.
  static const skipped = FieldMetrics(
    faceWidth: 0,
    jawAmplitude: 0,
    influenceMax: 0,
    outsideJawZoneP95: 0,
    minDetJ: 1,
    maxNeighborJump: 0,
    jawWidthBefore: 0,
    jawWidthAfter: 0,
    gonionWidthBefore: 0,
    gonionWidthAfter: 0,
    dxAtGonionLeft: 0,
    dxAtGonionRight: 0,
    eyes: RegionDisplacementStats.zero,
    brows: RegionDisplacementStats.zero,
    nose: RegionDisplacementStats.zero,
    mouth: RegionDisplacementStats.zero,
    faceCenter: RegionDisplacementStats.zero,
    beard: RegionDisplacementStats.zero,
    ears: RegionDisplacementStats.zero,
    jawActive: RegionDisplacementStats.zero,
  );

  bool get jawNarrows => jawWidthAfter < jawWidthBefore - 1e-6;

  bool get gonionNarrows => gonionWidthAfter < gonionWidthBefore - 1e-6;

  Map<String, Object> toJson() => {
        'faceWidth': faceWidth,
        'jawAmplitude': jawAmplitude,
        'influenceMax': influenceMax,
        'outsideJawZoneP95': outsideJawZoneP95,
        'minDetJ': minDetJ,
        'maxNeighborJump': maxNeighborJump,
        'jawWidthBefore': jawWidthBefore,
        'jawWidthAfter': jawWidthAfter,
        'jawNarrows': jawNarrows,
        'gonionWidthBefore': gonionWidthBefore,
        'gonionWidthAfter': gonionWidthAfter,
        'gonionNarrows': gonionNarrows,
        'dxAtGonionLeft': dxAtGonionLeft,
        'dxAtGonionRight': dxAtGonionRight,
        'eyes': eyes.toJson(),
        'brows': brows.toJson(),
        'nose': nose.toJson(),
        'mouth': mouth.toJson(),
        'faceCenter': faceCenter.toJson(),
        'beard': beard.toJson(),
        'ears': ears.toJson(),
        'jawActive': jawActive.toJson(),
      };

  static FieldMetrics compute({
    required DisplacementField field,
    required RegionMasks masks,
    required double faceWidth,
    required double jawAmplitude,
    required double jawWidthBefore,
    required double jawWidthAfter,
    required double gonionWidthBefore,
    required double gonionWidthAfter,
    required double dxAtGonionLeft,
    required double dxAtGonionRight,
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
        if (masks.jaw[i] == 0) {
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

    return FieldMetrics(
      faceWidth: faceWidth,
      jawAmplitude: jawAmplitude,
      influenceMax: influenceMax,
      outsideJawZoneP95: _p95(outside),
      minDetJ: minDet,
      maxNeighborJump: maxJump,
      jawWidthBefore: jawWidthBefore,
      jawWidthAfter: jawWidthAfter,
      gonionWidthBefore: gonionWidthBefore,
      gonionWidthAfter: gonionWidthAfter,
      dxAtGonionLeft: dxAtGonionLeft,
      dxAtGonionRight: dxAtGonionRight,
      eyes: statsFor(field, masks.eyes),
      brows: statsFor(field, masks.brows),
      nose: statsFor(field, masks.nose),
      mouth: statsFor(field, masks.mouth),
      faceCenter: statsFor(field, masks.faceCenter),
      beard: statsFor(field, masks.beard),
      ears: statsFor(field, masks.ears),
      jawActive: statsFor(field, masks.jawActive),
    );
  }

  static RegionDisplacementStats statsFor(DisplacementField field, Uint8List mask) {
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
      return const RegionDisplacementStats(
        pixelCount: 0,
        maxAbs: 0,
        meanAbs: 0,
        p95Abs: 0,
      );
    }
    return RegionDisplacementStats(
      pixelCount: values.length,
      maxAbs: maxAbs,
      meanAbs: sum / values.length,
      p95Abs: _p95(values),
    );
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
