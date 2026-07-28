import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Detecta e remove inversões de jacobiano na grade do [WarpField].
///
/// φ(p) ≈ p + d(p)·m(p). Se det(∇φ) < 0, escala o deslocamento local.
class AntiFoldingPass implements BodyReshapePass {
  const AntiFoldingPass({
    this.maxIterations = 8,
    this.scaleFactor = 0.7,
    this.determinantEpsilon = 1e-4,
  });

  final int maxIterations;
  final double scaleFactor;
  final double determinantEpsilon;

  @override
  String get id => 'anti_folding';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.antiFolding;

  @override
  WarpField run(BodyPassContext context) {
    final field = context.field;
    if (field == null || field.isIdentity) {
      return field ??
          WarpField.identity(
            imageSize: context.imageSize,
            region: context.region,
          );
    }

    final result = resolve(field);
    context.field = result.field;
    context.intermediateBuffers['folding_before'] =
        Float32List.fromList([result.invertedBefore.toDouble()]);
    context.intermediateBuffers['folding_after'] =
        Float32List.fromList([result.invertedAfter.toDouble()]);
    return result.field;
  }

  AntiFoldingResult resolve(WarpField field) {
    if (field.isIdentity) {
      return AntiFoldingResult(
        field: field,
        invertedBefore: 0,
        invertedAfter: 0,
        iterations: 0,
      );
    }

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final disp = Float32List.fromList(field.displacement);
    final mask = field.mask;
    final before = countInversions(
      displacement: disp,
      mask: mask,
      gridWidth: gw,
      gridHeight: gh,
      imageSize: field.imageSize,
    );

    var remaining = before;
    var iterations = 0;
    for (var iter = 0; iter < maxIterations && remaining > 0; iter++) {
      iterations++;
      final inverted = _invertedCellMask(
        displacement: disp,
        mask: mask,
        gridWidth: gw,
        gridHeight: gh,
        imageSize: field.imageSize,
      );
      for (var i = 0; i < inverted.length; i++) {
        if (!inverted[i]) {
          continue;
        }
        disp[i * 2] *= scaleFactor;
        disp[i * 2 + 1] *= scaleFactor;
        // Também atenua vizinhos para evitar reintroduzir flip.
        final gx = i % gw;
        final gy = i ~/ gw;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
              continue;
            }
            final x = gx + dx;
            final y = gy + dy;
            if (x < 0 || y < 0 || x >= gw || y >= gh) {
              continue;
            }
            final n = y * gw + x;
            disp[n * 2] *= math.sqrt(scaleFactor);
            disp[n * 2 + 1] *= math.sqrt(scaleFactor);
          }
        }
      }
      remaining = countInversions(
        displacement: disp,
        mask: mask,
        gridWidth: gw,
        gridHeight: gh,
        imageSize: field.imageSize,
      );
    }

    final after = remaining;
    final out = field.copyWith(
      displacement: disp,
      passId: id,
      foldingCellsBefore: before,
      foldingCellsAfter: after,
    );
    return AntiFoldingResult(
      field: out,
      invertedBefore: before,
      invertedAfter: after,
      iterations: iterations,
    );
  }

  /// Conta células (i,j) cujo jacobiano local é negativo.
  int countInversions({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required Size imageSize,
  }) {
    final flags = _invertedCellMask(
      displacement: displacement,
      mask: mask,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      imageSize: imageSize,
    );
    var count = 0;
    for (final flag in flags) {
      if (flag) {
        count++;
      }
    }
    return count;
  }

  List<bool> _invertedCellMask({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required Size imageSize,
  }) {
    final flags = List<bool>.filled(gridWidth * gridHeight, false);
    if (gridWidth < 2 || gridHeight < 2) {
      return flags;
    }

    final cellW = imageSize.width / (gridWidth - 1);
    final cellH = imageSize.height / (gridHeight - 1);

    Offset warped(int gx, int gy) {
      final idx = gy * gridWidth + gx;
      final m = mask[idx];
      final px = gx * cellW;
      final py = gy * cellH;
      return Offset(
        px + displacement[idx * 2] * m,
        py + displacement[idx * 2 + 1] * m,
      );
    }

    for (var gy = 0; gy < gridHeight - 1; gy++) {
      for (var gx = 0; gx < gridWidth - 1; gx++) {
        final p00 = warped(gx, gy);
        final p10 = warped(gx + 1, gy);
        final p01 = warped(gx, gy + 1);

        final ex = Offset(p10.dx - p00.dx, p10.dy - p00.dy);
        final ey = Offset(p01.dx - p00.dx, p01.dy - p00.dy);
        final det = ex.dx * ey.dy - ex.dy * ey.dx;
        // Área do cell de referência ≈ cellW * cellH > 0.
        if (det < determinantEpsilon) {
          flags[gy * gridWidth + gx] = true;
        }
      }
    }
    return flags;
  }
}

class AntiFoldingResult {
  const AntiFoldingResult({
    required this.field,
    required this.invertedBefore,
    required this.invertedAfter,
    required this.iterations,
  });

  final WarpField field;
  final int invertedBefore;
  final int invertedAfter;
  final int iterations;

  bool get eliminatedInversions =>
      invertedBefore > 0 && invertedAfter == 0;
}
