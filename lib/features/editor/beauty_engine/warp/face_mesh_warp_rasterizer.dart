import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/maps/influence_map.dart';
import '../config/face_warp_v3_config.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/mesh_region.dart';
import '../filters/face/face_warp_utils.dart';
import '../models/tri_mesh.dart';
import '../models/warp_field.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'anatomy/face_warp_vacancy_fill.dart';

/// Rasteriza warp facial via malha triangulada piecewise-affine (V3).
///
/// Deforma vértices com [ConstrainedVertexField] — **sem MLS**.
abstract final class FaceMeshWarpRasterizer {
  /// Caminho V3 — deslocamento por landmark via ACE.
  static WarpField rasterizeFromVertexField({
    required TriMesh sourceMesh,
    required ConstrainedVertexField vertexField,
    required Size imageSize,
    required MeshRegion region,
    required int gridWidth,
    required int gridHeight,
    InfluenceMap? influenceMap,
    required double intensity,
    Map<String, double> parameters = const {},
    double fse = 0,
    bool directMesh = false,
    bool applyVacancyFill = true,
  }) {
    if (intensity <= 0 || sourceMesh.triangleCount == 0) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    if (vertexField.maxDisplacementMagnitude() <= 0.05) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final sourceIndex = TriMeshSpatialIndex(
      sourceMesh,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
    );

    final cellCount = gridWidth * gridHeight;
    final displacement = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);
    final invW = imageSize.width > 0 ? 1.0 / imageSize.width : 0.0;
    final invH = imageSize.height > 0 ? 1.0 / imageSize.height : 0.0;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final nx = px * invW;
        final ny = py * invH;
        final idx = gy * gridWidth + gx;

        var m = 1.0;
        if (influenceMap != null && !influenceMap.isEmpty) {
          m = influenceMap.sampleNormalized(nx, ny);
          if (m <= 0.001) {
            continue;
          }
        }

        final hit = sourceIndex.locate(px, py);
        if (hit == null) {
          continue;
        }

        final d0 = vertexField.displacementAt(hit.i0);
        final d1 = vertexField.displacementAt(hit.i1);
        final d2 = vertexField.displacementAt(hit.i2);
        final dx = d0.dx * hit.w0 + d1.dx * hit.w1 + d2.dx * hit.w2;
        final dy = d0.dy * hit.w0 + d1.dy * hit.w1 + d2.dy * hit.w2;

        mask[idx] = m;
        // Remap liquify: amostra em (px + disp). Δv dos vértices é forward.
        displacement[idx * 2] = -dx;
        displacement[idx * 2 + 1] = -dy;
      }
    }

    final lateral = FaceWarpVacancyFill.hasActiveLateralTool(parameters);
    final faceSlimOnly = FaceWarpVacancyFill.isFaceSlimOnly(parameters);
    final skipGridHeuristics =
        directMesh || (faceSlimOnly && FaceWarpV3Config.useForwardMeshWarpFaceSlim);

    if (!skipGridHeuristics) {
      if (faceSlimOnly) {
        _seedFaceSlimVertices(
          vertexField: vertexField,
          mesh: sourceMesh,
          imageSize: imageSize,
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        );
      }

      _spreadDisplacement(
        displacement: displacement,
        mask: mask,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        iterations: faceSlimOnly
            ? 5
            : (lateral ? 6 : ((parameters['lip_thickness'] ?? 0) > 1e-6 ? 2 : 4)),
        horizontalOnly: faceSlimOnly,
        preservePeaks: faceSlimOnly,
      );

      if (applyVacancyFill && lateral && fse > 0) {
        FaceWarpVacancyFill.applyToGrid(
          parameters: parameters,
          vertexField: vertexField,
          mesh: sourceMesh,
          imageSize: imageSize,
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
          fse: fse *
              (0.85 + 0.15 * FaceWarpVacancyFill.radiusScaleFor(parameters)) *
              (faceSlimOnly ? 1.15 : 1.0),
          maxOverlapRatio: faceSlimOnly ? 0.62 : 0.45,
        );
      }

      if (faceSlimOnly) {
        _protectFaceSlimCenter(
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        );
        _boostFaceSlimLateral(
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        );
        _smoothDisplacementField(
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
          iterations: 2,
        );
      }

      if ((parameters['lip_thickness'] ?? 0) > 1e-6) {
        _smoothDisplacementField(
          displacement: displacement,
          mask: mask,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
          iterations: 3,
        );
      }
    }

    var active = 0;
    for (var i = 0; i < cellCount; i++) {
      if (mask[i] <= 0.001) {
        continue;
      }
      final dx = displacement[i * 2];
      final dy = displacement[i * 2 + 1];
      if (math.sqrt(dx * dx + dy * dy) > 0.05) {
        active++;
      }
    }

    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: displacement,
      mask: mask,
      imageSize: imageSize,
      region: region,
      controlPoints: const [],
      intensity: intensity,
      activeCellCount: active,
      passId: directMesh ? 'face_mesh_v3_direct' : 'face_mesh_v3',
    );
  }

  /// Preenche células com Δv=0 a partir de vizinhos (warps locais olho/boca).
  static void _spreadDisplacement({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required int iterations,
    bool horizontalOnly = false,
    bool preservePeaks = false,
  }) {
    if (iterations <= 0) {
      return;
    }
    final tmpDisp = Float32List.fromList(displacement);

    for (var iter = 0; iter < iterations; iter++) {
      for (var gy = 0; gy < gridHeight; gy++) {
        for (var gx = 0; gx < gridWidth; gx++) {
          final idx = gy * gridWidth + gx;
          if (mask[idx] <= 0.001) {
            continue;
          }

          final curDx = displacement[idx * 2];
          final curDy = displacement[idx * 2 + 1];
          final curMag = math.sqrt(curDx * curDx + curDy * curDy);

          var sumDx = 0.0;
          var sumDy = 0.0;
          var maxNeighbor = 0.0;
          var count = 0.0;

          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) {
                continue;
              }
              final nx = gx + dx;
              final ny = gy + dy;
              if (nx < 0 || ny < 0 || nx >= gridWidth || ny >= gridHeight) {
                continue;
              }
              final nIdx = ny * gridWidth + nx;
              if (mask[nIdx] <= 0.001) {
                continue;
              }
              final ndx = displacement[nIdx * 2];
              final ndy = displacement[nIdx * 2 + 1];
              final nMag = math.sqrt(ndx * ndx + ndy * ndy);
              if (nMag <= 1e-6) {
                continue;
              }
              sumDx += ndx;
              sumDy += ndy;
              count += 1;
              if (nMag > maxNeighbor) {
                maxNeighbor = nMag;
              }
            }
          }

          if (count <= 0) {
            continue;
          }

          if (curMag > 0.05) {
            final peakKeep = preservePeaks ? 0.92 : 0.82;
            final avgMix = 1.0 - peakKeep;
            tmpDisp[idx * 2] = curDx * peakKeep + (sumDx / count) * avgMix;
            tmpDisp[idx * 2 + 1] = horizontalOnly
                ? curDy * 0.65
                : curDy * peakKeep + (sumDy / count) * avgMix;
          } else {
            final fill = maxNeighbor * (preservePeaks ? 0.96 : 0.88);
            final avgDx = sumDx / count;
            final avgDy = sumDy / count;
            final avgMag = math.sqrt(avgDx * avgDx + avgDy * avgDy);
            if (avgMag < 1e-6) {
              continue;
            }
            final s = fill / avgMag;
            tmpDisp[idx * 2] = avgDx * s;
            tmpDisp[idx * 2 + 1] = horizontalOnly ? curDy * 0.15 : avgDy * s;
          }
        }
      }
      displacement.setAll(0, tmpDisp);
    }
  }

  /// Injeta Δv dos landmarks na grade — recupera pico perdido na interp. baricêntrica.
  static void _seedFaceSlimVertices({
    required ConstrainedVertexField vertexField,
    required TriMesh mesh,
    required Size imageSize,
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
  }) {
    const minMovePx = 1.0;
    const stampRadius = 2;

    for (var i = 0; i < vertexField.landmarkCount; i++) {
      final fwd = vertexField.displacementAt(i);
      if (fwd.dx.abs() < minMovePx) {
        continue;
      }

      final base = FaceWarpUtils.vertexAt(mesh, i);
      if (base == null) {
        continue;
      }

      final bdx = -fwd.dx;
      final bdy = -fwd.dy;
      final gxc = ((base.dx / imageSize.width) * (gridWidth - 1))
          .round()
          .clamp(0, gridWidth - 1);
      final gyc = ((base.dy / imageSize.height) * (gridHeight - 1))
          .round()
          .clamp(0, gridHeight - 1);

      for (var dy = -stampRadius; dy <= stampRadius; dy++) {
        for (var dx = -stampRadius; dx <= stampRadius; dx++) {
          final gx = gxc + dx;
          final gy = gyc + dy;
          if (gx < 0 || gy < 0 || gx >= gridWidth || gy >= gridHeight) {
            continue;
          }
          final idx = gy * gridWidth + gx;
          if (mask[idx] <= 0.001) {
            continue;
          }
          final dist = math.sqrt(dx * dx + dy * dy);
          final w = (1 - dist / (stampRadius + 0.5)).clamp(0.35, 1.0);
          final targetDx = bdx * w;
          if (targetDx.abs() > displacement[idx * 2].abs()) {
            displacement[idx * 2] = targetDx;
            displacement[idx * 2 + 1] = bdy * w * 0.08;
          }
        }
      }
    }
  }

  /// Reforça contorno lateral após proteção central.
  static void _boostFaceSlimLateral({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    double boost = 1.08,
  }) {
    final centerGx = (gridWidth - 1) * 0.5;
    final halfW = math.max(gridWidth * 0.5, 1.0);
    final ghM1 = math.max(gridHeight - 1, 1);
    for (var gy = 0; gy < gridHeight; gy++) {
      final ny = gy / ghM1;
      if (ny > 0.70) {
        continue;
      }
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        if (mask[idx] <= 0.001) {
          continue;
        }
        final lateral = (gx - centerGx).abs() / halfW;
        if (lateral < 0.34) {
          continue;
        }
        final t = ((lateral - 0.34) / 0.66).clamp(0.0, 1.0);
        var earFade = 1.0;
        if (ny < 0.24) {
          earFade = (0.45 + 0.55 * (ny / 0.24)).clamp(0.45, 1.0);
        }
        final mul = 1.0 + (boost - 1.0) * t * earFade;
        displacement[idx * 2] *= mul;
      }
    }
  }

  /// Zera Δv no centro (nariz/olhos) — spread lateral não deve vazar para rigid.
  static void _protectFaceSlimCenter({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
  }) {
    final centerGx = (gridWidth - 1) * 0.5;
    final halfW = math.max(gridWidth * 0.5, 1.0);
    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        if (mask[idx] <= 0.001) {
          continue;
        }
        final lateral = (gx - centerGx).abs() / halfW;
        if (lateral >= 0.28) {
          continue;
        }
        final fade = math.pow(lateral / 0.28, 2.0).toDouble();
        displacement[idx * 2] *= fade;
        displacement[idx * 2 + 1] *= fade;
      }
    }
  }

  /// Suaviza Δv na grade — reduz faixas horizontais em warps labiais.
  static void _smoothDisplacementField({
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required int iterations,
  }) {
    if (iterations <= 0) {
      return;
    }
    final tmp = Float32List.fromList(displacement);

    for (var iter = 0; iter < iterations; iter++) {
      for (var gy = 0; gy < gridHeight; gy++) {
        for (var gx = 0; gx < gridWidth; gx++) {
          final idx = gy * gridWidth + gx;
          if (mask[idx] <= 0.001) {
            continue;
          }

          var sumDx = 0.0;
          var sumDy = 0.0;
          var count = 0.0;

          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = gx + dx;
              final ny = gy + dy;
              if (nx < 0 || ny < 0 || nx >= gridWidth || ny >= gridHeight) {
                continue;
              }
              final nIdx = ny * gridWidth + nx;
              if (mask[nIdx] <= 0.001) {
                continue;
              }
              sumDx += displacement[nIdx * 2];
              sumDy += displacement[nIdx * 2 + 1];
              count += 1;
            }
          }

          if (count <= 0) {
            continue;
          }
          final avgDx = sumDx / count;
          final avgDy = sumDy / count;
          final curDx = displacement[idx * 2];
          final curDy = displacement[idx * 2 + 1];
          tmp[idx * 2] = curDx * 0.35 + avgDx * 0.65;
          tmp[idx * 2 + 1] = curDy * 0.35 + avgDy * 0.65;
        }
      }
      displacement.setAll(0, tmp);
    }
  }
}
