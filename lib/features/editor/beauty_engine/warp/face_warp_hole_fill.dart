import 'dart:math' as math;
import 'dart:typed_data';

import '../body_reshape/maps/influence_map.dart';
import '../models/warp_field.dart';
import 'anatomy/face_warp_vacancy_fill.dart';

/// Preenche buracos pós-warp backward (disocclusões) via vizinho mais próximo.
///
/// Baseado em imputação NN usada em Laplacian Pyramid Warping (ETH 2025):
/// pixels não amostrados pelo liquify recebem cor do vizinho válido mais
/// próximo — evita “cópia da origem” visível sem blur pesado.
abstract final class FaceWarpHoleFill {
  static Uint8List imputeFromGhostMask({
    required Uint8List rgba,
    required Uint8List ghost,
    required int width,
    required int height,
    int maxRadius = 18,
    int passes = 2,
  }) {
    if (!ghost.any((v) => v == 1)) {
      return rgba;
    }

    final out = Uint8List.fromList(rgba);
    var work = Uint8List.fromList(ghost);

    for (var pass = 0; pass < passes; pass++) {
      final next = Uint8List.fromList(work);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final p = y * width + x;
          if (work[p] == 0) {
            continue;
          }

          final sampled = _nearestValidRgb(
            out,
            work,
            width,
            height,
            x,
            y,
            maxRadius,
          );
          if (sampled == null) {
            continue;
          }

          final o = p * 4;
          out[o] = sampled[0];
          out[o + 1] = sampled[1];
          out[o + 2] = sampled[2];
          next[p] = 0;
        }
      }
      work = next;
    }

    return out;
  }

  static List<int>? _nearestValidRgb(
    Uint8List rgba,
    Uint8List ghost,
    int width,
    int height,
    int x,
    int y,
    int maxRadius,
  ) {
    for (var r = 1; r <= maxRadius; r++) {
      List<int>? best;
      var bestDist = double.infinity;

      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) {
            continue;
          }
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
            continue;
          }
          final n = ny * width + nx;
          if (ghost[n] == 1) {
            continue;
          }
          final dist = math.sqrt(dx * dx + dy * dy).toDouble();
          if (dist < bestDist) {
            bestDist = dist;
            final o = n * 4;
            best = [rgba[o], rgba[o + 1], rgba[o + 2]];
          }
        }
      }

      if (best != null) {
        return best;
      }
    }
    return null;
  }

  /// Máscara de buracos — detecção O(grade) + upsample por célula.
  static Uint8List buildGhostMask({
    required WarpField field,
    InfluenceMap? influenceMap,
    required Map<String, double> parameters,
  }) {
    final imgW = field.imageSize.width.round();
    final imgH = field.imageSize.height.round();
    final mask = Uint8List(imgW * imgH);
    if (!FaceWarpVacancyFill.hasActiveLateralTool(parameters)) {
      return mask;
    }

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(parameters);
    const ghostRatioDefault = 2.2;
    const minNeighborDefault = 2.5;
    const influenceFloorDefault = 0.05;
    final ghostRatio = faceSlimOnly ? 1.65 : ghostRatioDefault;
    final minNeighbor = faceSlimOnly ? 2.0 : minNeighborDefault;
    final influenceFloor = faceSlimOnly ? 0.03 : influenceFloorDefault;
    const minLateralNorm = 0.30;

    final centerGx = (gw - 1) * 0.5;
    final halfGw = math.max(gw * 0.5, 1.0);

    final ghostCell = Uint8List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final lateralNorm = (gx - centerGx).abs() / halfGw;
        if (faceSlimOnly && lateralNorm < minLateralNorm) {
          continue;
        }

        final gIdx = gy * gw + gx;
        if (field.mask[gIdx] <= 0.001) {
          continue;
        }

        final curDx = field.displacement[gIdx * 2];
        final curDy = field.displacement[gIdx * 2 + 1];
        final curMag = math.sqrt(curDx * curDx + curDy * curDy);

        var maxNeighbor = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
              continue;
            }
            final ngx = (gx + dx).clamp(0, gw - 1);
            final ngy = (gy + dy).clamp(0, gh - 1);
            final nIdx = ngy * gw + ngx;
            if (field.mask[nIdx] <= 0.001) {
              continue;
            }
            final ndx = field.displacement[nIdx * 2];
            final ndy = field.displacement[nIdx * 2 + 1];
            maxNeighbor = math.max(
              maxNeighbor,
              math.sqrt(ndx * ndx + ndy * ndy),
            );
          }
        }

        if (maxNeighbor >= minNeighbor &&
            curMag * ghostRatio < maxNeighbor) {
          ghostCell[gIdx] = 1;
        }
      }
    }

    if (!ghostCell.any((v) => v == 1)) {
      return mask;
    }

    final cellW = imgW / gw;
    final cellH = imgH / gh;
    final w = field.imageSize.width;
    final h = field.imageSize.height;

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final gIdx = gy * gw + gx;
        if (ghostCell[gIdx] == 0) {
          continue;
        }

        final x0 = (gx * cellW).floor().clamp(0, imgW - 1);
        final y0 = (gy * cellH).floor().clamp(0, imgH - 1);
        final x1 = ((gx + 1) * cellW).ceil().clamp(0, imgW);
        final y1 = ((gy + 1) * cellH).ceil().clamp(0, imgH);

        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            if (influenceMap != null && !influenceMap.isEmpty) {
              final nx = w > 0 ? x / w : 0.0;
              final ny = h > 0 ? y / h : 0.0;
              if (influenceMap.sampleNormalized(nx, ny) <= influenceFloor) {
                continue;
              }
            }
            mask[y * imgW + x] = 1;
          }
        }
      }
    }

    return mask;
  }
}
