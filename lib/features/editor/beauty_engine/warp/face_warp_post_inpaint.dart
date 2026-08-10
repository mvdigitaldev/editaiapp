import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/influence_map.dart';
import '../models/warp_field.dart';
import 'anatomy/face_warp_vacancy_fill.dart';
import 'face_warp_hole_fill.dart';

/// Inpainting leve pós-warp para warps laterais (Sprint 37).
///
/// Preenche faixas fantasma onde o deslocamento local é baixo mas vizinhos
/// tiveram warp forte (`eye_distance`, contorno, etc.).
abstract final class FaceWarpPostInpaint {
  static const _ghostNeighborRatio = 2.2;
  static const _minNeighborDispPx = 2.5;
  static const _iterations = 4;

  static Uint8List ghostMaskFor({
    required WarpField field,
    InfluenceMap? influenceMap,
    required Map<String, double> parameters,
  }) {
    if (!FaceWarpVacancyFill.hasActiveLateralTool(parameters)) {
      return Uint8List(
        field.imageSize.width.round() * field.imageSize.height.round(),
      );
    }
    return _buildGhostMask(
      field: field,
      influenceMap: influenceMap,
      parameters: parameters,
    );
  }

  @visibleForTesting
  static int countGhostPixels({
    required WarpField field,
    InfluenceMap? influenceMap,
    required Map<String, double> parameters,
  }) {
    if (!FaceWarpVacancyFill.hasActiveLateralTool(parameters)) {
      return 0;
    }
    final ghost = ghostMaskFor(
      field: field,
      influenceMap: influenceMap,
      parameters: parameters,
    );
    return ghost.where((v) => v == 1).length;
  }

  static Uint8List apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required WarpField field,
    InfluenceMap? influenceMap,
    required Map<String, double> parameters,
    int? iterations,
  }) {
    if (!FaceWarpVacancyFill.hasActiveLateralTool(parameters)) {
      return rgba;
    }
    if (field.isIdentity || field.gridWidth < 2 || field.gridHeight < 2) {
      return rgba;
    }

    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(parameters);
    final ghost = faceSlimOnly
        ? FaceWarpHoleFill.buildGhostMask(
            field: field,
            influenceMap: influenceMap,
            parameters: parameters,
          )
        : _buildGhostMask(
            field: field,
            influenceMap: influenceMap,
            parameters: parameters,
          );
    if (!ghost.any((v) => v == 1)) {
      return rgba;
    }

    final iterCount = iterations ?? (faceSlimOnly ? 2 : _iterations);
    final out = Uint8List.fromList(rgba);
    var ghostWork = Uint8List.fromList(ghost);
    final imgW = width;

    for (var iter = 0; iter < iterCount; iter++) {
      final radius = faceSlimOnly ? 6 + iter * 6 : 4 + iter * 8;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final p = y * imgW + x;
          if (ghostWork[p] == 0) {
            continue;
          }

          var sumR = 0.0;
          var sumG = 0.0;
          var sumB = 0.0;
          var count = 0.0;

          for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
              if (dx == 0 && dy == 0) {
                continue;
              }
              final nx = x + dx;
              final ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
                continue;
              }
              final n = ny * imgW + nx;
              if (ghostWork[n] == 1) {
                continue;
              }
              final o = n * 4;
              sumR += out[o];
              sumG += out[o + 1];
              sumB += out[o + 2];
              count += 1;
            }
          }

          if (count <= 0) {
            continue;
          }

          final o = p * 4;
          final blend =
              iter == iterCount - 1 ? (faceSlimOnly ? 0.88 : 0.92) : 0.78;
          out[o] = (out[o] * (1 - blend) + (sumR / count) * blend).round().clamp(
                0,
                255,
              );
          out[o + 1] =
              (out[o + 1] * (1 - blend) + (sumG / count) * blend).round().clamp(
                    0,
                    255,
                  );
          out[o + 2] =
              (out[o + 2] * (1 - blend) + (sumB / count) * blend).round().clamp(
                    0,
                    255,
                  );
          ghostWork[p] = 0;
        }
      }
    }

    return out;
  }

  static Uint8List _buildGhostMask({
    required WarpField field,
    InfluenceMap? influenceMap,
    Map<String, double> parameters = const {},
  }) {
    final imgW = field.imageSize.width.round();
    final imgH = field.imageSize.height.round();
    final mask = Uint8List(imgW * imgH);

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final w = field.imageSize.width;
    final h = field.imageSize.height;
    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(parameters);
    final ghostRatio =
        faceSlimOnly ? 1.55 : _ghostNeighborRatio;
    final minNeighbor =
        faceSlimOnly ? 1.8 : _minNeighborDispPx;
    final influenceFloor = faceSlimOnly ? 0.02 : 0.05;

    for (var y = 0; y < imgH; y++) {
      for (var x = 0; x < imgW; x++) {
        final px = x.toDouble();
        final py = y.toDouble();
        final nx = w > 0 ? px / w : 0.0;
        final ny = h > 0 ? py / h : 0.0;

        if (influenceMap != null && !influenceMap.isEmpty) {
          if (influenceMap.sampleNormalized(nx, ny) <= influenceFloor) {
            continue;
          }
        }

        final gx = ((px / w) * (gw - 1)).round().clamp(0, gw - 1);
        final gy = ((py / h) * (gh - 1)).round().clamp(0, gh - 1);
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

        final ratioGhost =
            maxNeighbor >= minNeighbor && curMag * ghostRatio < maxNeighbor;
        final gapGhost = !faceSlimOnly &&
            maxNeighbor >= minNeighbor &&
            maxNeighbor - curMag >= 2.5;

        if (ratioGhost || gapGhost) {
          mask[y * imgW + x] = 1;
        }
      }
    }

    return mask;
  }
}
