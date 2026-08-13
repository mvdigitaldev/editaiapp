import 'dart:math' as math;
import 'dart:typed_data';

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'face_warp_hole_fill.dart';
import 'face_warp_renderer.dart';

/// Payload mesh + ACE para warp piecewise-affine na malha.
class FaceMeshForwardPayload {
  const FaceMeshForwardPayload({
    required this.mesh,
    required this.vertexField,
    required this.influenceMap,
    this.personMask,
  });

  final TriMesh mesh;
  final ConstrainedVertexField vertexField;
  final InfluenceMap influenceMap;
  final PersonMask? personMask;

  bool get isIdentity => vertexField.maxDisplacementMagnitude() <= 0.05;
}

/// Piecewise-affine **backward** por malha (padrão FaceSlim / skimage warp).
///
/// Para cada pixel no espaço deformado, localiza triângulo destino e amostra
/// a posição correspondente na malha origem — sem splat forward (z-fighting /
/// serrilhado) e sem composite de vaga em ~2k px de bochecha.
abstract final class FaceMeshForwardWarp {
  static const _lateralNormMin = 0.38;
  static const _lateralInfluenceMin = 0.05;
  static const _personOuterMax = 0.52;
  static const _maxBgDistancePx = 32;

  static Uint8List apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    String runId = 'mesh-backward',
  }) {
    if (payload.isIdentity || rgba.isEmpty) {
      return rgba;
    }

    final mesh = payload.mesh;
    final vf = payload.vertexField;
    final personMask = payload.personMask;

    final renderResult = FaceWarpRenderer.renderFromPayload(
      rgba: rgba,
      width: width,
      height: height,
      payload: payload,
      runId: runId,
    );

    final output = Uint8List.fromList(renderResult.rgba);
    final coverage =
        renderResult.coverage ?? Float32List(width * height);
    final meshHitPx = coverage.where((v) => v > 0.5).length;
    final vertexCount = math.min(
      vf.landmarkCount,
      mesh.vertices.length ~/ 2,
    );

    var seamImputePx = 0;
    var bgFillPx = 0;
    var lateralGhostPx = 0;

    if (personMask != null &&
        personMask.bytes.isNotEmpty &&
        !payload.influenceMap.isEmpty) {
      final ghost = _buildLateralSeamGhostMask(
        original: rgba,
        output: output,
        coverage: coverage,
        width: width,
        height: height,
        influence: payload.influenceMap,
        personMask: personMask,
      );
      lateralGhostPx = ghost.where((v) => v == 1).length;

      if (lateralGhostPx > 0) {
        final imputed = FaceWarpHoleFill.imputeFromGhostMask(
          rgba: output,
          ghost: ghost,
          width: width,
          height: height,
          maxRadius: 14,
          passes: 2,
        );
        for (var p = 0; p < width * height; p++) {
          if (ghost[p] == 0) {
            continue;
          }
          final o = p * 4;
          if (output[o] != imputed[o] ||
              output[o + 1] != imputed[o + 1] ||
              output[o + 2] != imputed[o + 2]) {
            output[o] = imputed[o];
            output[o + 1] = imputed[o + 1];
            output[o + 2] = imputed[o + 2];
            seamImputePx++;
          }
        }

        bgFillPx = _fillRemainingOuterVacancy(
          output: output,
          original: rgba,
          ghost: ghost,
          coverage: coverage,
          width: width,
          height: height,
          personMask: personMask,
        );
      }
    }

    // #region agent log
    AgentDebugLog.write(
      location: 'face_mesh_forward_warp.dart:apply',
      message: 'mesh_backward_warp',
      hypothesisId: 'B2',
      runId: runId,
      phase: '2',
      data: {
        ...renderResult.metrics.toJson(),
        'meshHitPx': meshHitPx,
        'holeFillPx': seamImputePx + bgFillPx,
        'seamImputePx': seamImputePx,
        'bgFillPx': bgFillPx,
        'lateralGhostPx': lateralGhostPx,
        'peakDisp': vf.maxDisplacementMagnitude(),
        'vertexCount': vertexCount,
        'landmarkCount': vf.landmarkCount,
        'meshVertexCount': mesh.vertices.length ~/ 2,
      },
    );
    // #endregion

    return output;
  }

  /// Fantasma lateral: fora da malha deformada mas ainda com textura original.
  static Uint8List _buildLateralSeamGhostMask({
    required Uint8List original,
    required Uint8List output,
    required Float32List coverage,
    required int width,
    required int height,
    required InfluenceMap influence,
    required PersonMask personMask,
  }) {
    final ghost = Uint8List(width * height);
    final centerX = width * 0.5;

    for (var y = 0; y < height; y++) {
      final ny = y / height;
      if (ny < 0.16 || ny > 0.70) {
        continue;
      }
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        if (coverage[p] > 0.02) {
          continue;
        }

        final nx = x / width;
        final lateral = (x - centerX).abs() / (width * 0.5);
        if (lateral < _lateralNormMin) {
          continue;
        }

        final person = personMask.sampleNormalized(nx, ny);
        if (person < 0.22 || person > _personOuterMax) {
          continue;
        }

        final inf = influence.sampleNormalized(nx, ny);
        if (inf < _lateralInfluenceMin) {
          continue;
        }

        final o = p * 4;
        final similar = (original[o] - output[o]).abs() <= 8 &&
            (original[o + 1] - output[o + 1]).abs() <= 8 &&
            (original[o + 2] - output[o + 2]).abs() <= 8;
        if (!similar) {
          continue;
        }

        if (!_hasCoveredNeighbor(coverage, width, height, x, y, radius: 5) &&
            !_hasCoveredNeighbor(coverage, width, height, x, y, radius: 10)) {
          continue;
        }

        ghost[p] = 1;
      }
    }
    return ghost;
  }

  static bool _hasCoveredNeighbor(
    Float32List coverage,
    int width,
    int height,
    int x,
    int y, {
    required int radius,
  }) {
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
        if (coverage[ny * width + nx] > 0.5) {
          return true;
        }
      }
    }
    return false;
  }

  /// Borda externa restante — fundo imediato (faixa estreita).
  static int _fillRemainingOuterVacancy({
    required Uint8List output,
    required Uint8List original,
    required Uint8List ghost,
    required Float32List coverage,
    required int width,
    required int height,
    required PersonMask personMask,
  }) {
    var filled = 0;
    final centerX = width * 0.5;

    for (var y = 0; y < height; y++) {
      final ny = y / height;
      if (ny < 0.14 || ny > 0.72) {
        continue;
      }
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        if (ghost[p] == 0 || coverage[p] > 0.02) {
          continue;
        }

        final nx = x / width;
        final person = personMask.sampleNormalized(nx, ny);
        if (person > 0.44) {
          continue;
        }

        final side = x >= centerX ? 1 : -1;
        final bg = _sampleBackgroundOutward(
          original: original,
          personMask: personMask,
          width: width,
          height: height,
          x: x,
          y: y,
          ny: ny,
          side: side,
        );
        if (bg == null) {
          continue;
        }

        final o = p * 4;
        if ((output[o] - original[o]).abs() <= 8 &&
            (output[o + 1] - original[o + 1]).abs() <= 8) {
          output[o] = bg[0];
          output[o + 1] = bg[1];
          output[o + 2] = bg[2];
          filled++;
        }
      }
    }
    return filled;
  }

  static List<int>? _sampleBackgroundOutward({
    required Uint8List original,
    required PersonMask personMask,
    required int width,
    required int height,
    required int x,
    required int y,
    required double ny,
    required int side,
  }) {
    const bgThreshold = 0.18;
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var count = 0;

    for (var r = 1; r <= _maxBgDistancePx; r++) {
      final sx = x + side * r;
      if (sx < 0 || sx >= width) {
        break;
      }
      if (personMask.sampleNormalized(sx / width, ny) >= bgThreshold) {
        continue;
      }
      final o = (y * width + sx) * 4;
      sumR += original[o];
      sumG += original[o + 1];
      sumB += original[o + 2];
      count++;
      if (count >= 2) {
        break;
      }
    }

    if (count == 0) {
      return null;
    }
    return [
      (sumR / count).round(),
      (sumG / count).round(),
      (sumB / count).round(),
    ];
  }
}
