import 'dart:math' as math;
import 'dart:typed_data';

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'face_warp_hole_fill.dart';

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

    final vertexCount = math.min(
      vf.landmarkCount,
      mesh.vertices.length ~/ 2,
    );

    final deformedVerts = Float32List.fromList(mesh.vertices);
    for (var i = 0; i < vertexCount; i++) {
      final d = vf.displacementAt(i);
      deformedVerts[i * 2] += d.dx;
      deformedVerts[i * 2 + 1] += d.dy;
    }

    final deformedMesh = TriMesh(
      vertices: deformedVerts,
      uvs: mesh.uvs,
      indices: mesh.indices,
      regionBuffers: mesh.regionBuffers,
      isPartial: mesh.isPartial,
    );

    final spatialIndex = TriMeshSpatialIndex(
      deformedMesh,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
    );

    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    for (var i = 0; i < deformedVerts.length; i += 2) {
      final x = deformedVerts[i];
      final y = deformedVerts[i + 1];
      minX = math.min(minX, x.floor());
      minY = math.min(minY, y.floor());
      maxX = math.max(maxX, x.ceil());
      maxY = math.max(maxY, y.ceil());
    }
    const margin = 3;
    final x0 = (minX - margin).clamp(0, width - 1);
    final y0 = (minY - margin).clamp(0, height - 1);
    final x1 = (maxX + margin).clamp(0, width - 1);
    final y1 = (maxY + margin).clamp(0, height - 1);

    final output = Uint8List.fromList(rgba);
    final coverage = Float32List(width * height);
    var meshHitPx = 0;

    for (var y = y0; y <= y1; y++) {
      final py = y + 0.5;
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5;
        final hit = spatialIndex.locate(px, py);
        if (hit == null) {
          continue;
        }

        final s0 = FaceWarpUtils.vertexAt(mesh, hit.i0);
        final s1 = FaceWarpUtils.vertexAt(mesh, hit.i1);
        final s2 = FaceWarpUtils.vertexAt(mesh, hit.i2);
        if (s0 == null || s1 == null || s2 == null) {
          continue;
        }

        final srcX =
            hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx;
        final srcY =
            hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy;
        final rgb = _sampleBilinear(rgba, width, height, srcX, srcY);

        final p = y * width + x;
        final o = p * 4;
        output[o] = rgb[0];
        output[o + 1] = rgb[1];
        output[o + 2] = rgb[2];
        coverage[p] = 1.0;
        meshHitPx++;
      }
    }

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
      data: {
        'meshHitPx': meshHitPx,
        'holeFillPx': seamImputePx + bgFillPx,
        'seamImputePx': seamImputePx,
        'bgFillPx': bgFillPx,
        'lateralGhostPx': lateralGhostPx,
        'peakDisp': vf.maxDisplacementMagnitude(),
        'bboxW': x1 - x0 + 1,
        'bboxH': y1 - y0 + 1,
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

  static List<int> _sampleBilinear(
    Uint8List rgba,
    int width,
    int height,
    double x,
    double y,
  ) {
    if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) {
      final cx = x.clamp(0, width - 1).round();
      final cy = y.clamp(0, height - 1).round();
      final idx = (cy * width + cx) * 4;
      return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final tx = x - x0;
    final ty = y - y0;

    final c00 = _pixel(rgba, width, x0, y0);
    final c10 = _pixel(rgba, width, x0 + 1, y0);
    final c01 = _pixel(rgba, width, x0, y0 + 1);
    final c11 = _pixel(rgba, width, x0 + 1, y0 + 1);

    return List.generate(4, (c) {
      final v = _lerp(
        _lerp(c00[c].toDouble(), c10[c].toDouble(), tx),
        _lerp(c01[c].toDouble(), c11[c].toDouble(), tx),
        ty,
      );
      return v.round().clamp(0, 255);
    });
  }

  static List<int> _pixel(Uint8List rgba, int width, int x, int y) {
    final idx = (y * width + x) * 4;
    return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
