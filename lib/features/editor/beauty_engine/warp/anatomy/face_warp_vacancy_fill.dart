import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/face/face_warp_utils.dart';
import '../../models/tri_mesh.dart';
import '../face_warp_mvp_operations.dart';
import 'constrained_vertex_field.dart';
import 'vertex_role_map.dart';

/// Preenche regiões “vazias” após warps laterais (olhos/boca afastam).
///
/// Liquify backward deixa pixels na posição original sem Δv → fantasma.
/// Propaga o Δv inverso ao redor da posição **original** de cada vértice movido.
///
/// **face_slim / contorno:** sem vacancy na grade (malha/GPU piecewise).
/// **eye_distance / mouth_width:** só vértices de olhos e lábios.
abstract final class FaceWarpVacancyFill {
  static const lateralToolKeys = {
    'eye_distance',
    'mouth_width',
    'face_slim',
    'narrow_face',
    'v_face',
    'jaw',
    'temple',
  };

  /// Warps de contorno lateral — vacancy na grade causa blocos na bochecha.
  static const _contourOnlyTools = {
    'face_slim',
    'narrow_face',
    'v_face',
    'jaw',
    'temple',
  };

  static bool hasActiveLateralTool(Map<String, double> parameters) {
    for (final key in lateralToolKeys) {
      if ((parameters[key] ?? 0) > 1e-6) {
        return true;
      }
    }
    return false;
  }

  /// Malha backward V3 para ferramentas MVP de contorno (Fase 15).
  ///
  /// Substitui [isFaceSlimOnly] quando múltiplas ferramentas MVP estão ativas.
  static bool usesMvpMeshPath(Map<String, double> parameters) =>
      FaceWarpMvpOperations.usesMvpMeshPath(parameters);

  /// Só [face_slim] ativo — alias legado; preferir [usesMvpMeshPath].
  static bool isFaceSlimOnly(Map<String, double> parameters) {
    if (usesMvpMeshPath(parameters) &&
        (parameters['face_slim'] ?? 0) > 1e-6 &&
        _onlyFaceSlimAmongMvp(parameters)) {
      return true;
    }
    return _legacyIsFaceSlimOnly(parameters);
  }

  static bool _onlyFaceSlimAmongMvp(Map<String, double> parameters) {
    for (final key in FaceWarpMvpOperations.parameterKeys) {
      if (key == 'face_slim') {
        continue;
      }
      if ((parameters[key] ?? 0) > 1e-6) {
        return false;
      }
    }
    return true;
  }

  static bool _legacyIsFaceSlimOnly(Map<String, double> parameters) {
    if ((parameters['face_slim'] ?? 0) <= 1e-6) {
      return false;
    }
    for (final key in lateralToolKeys) {
      if (key == 'face_slim') {
        continue;
      }
      if ((parameters[key] ?? 0) > 1e-6) {
        return false;
      }
    }
    return true;
  }

  /// Índices de vértice elegíveis para vacancy fill na grade.
  static Set<int> vacancySourceIndices(Map<String, double> parameters) {
    if (isFaceSlimOnly(parameters)) {
      return const {};
    }
    for (final key in _contourOnlyTools) {
      if (key == 'face_slim') {
        continue;
      }
      if ((parameters[key] ?? 0) > 1e-6) {
        return const {};
      }
    }

    final allowed = <int>{};
    if ((parameters['eye_distance'] ?? 0) > 1e-6) {
      allowed.addAll(VertexRoleMap.eyeLeft);
      allowed.addAll(VertexRoleMap.eyeRight);
    }
    if ((parameters['mouth_width'] ?? 0) > 1e-6) {
      allowed.addAll(VertexRoleMap.upperLip);
      allowed.addAll(VertexRoleMap.lowerLip);
      allowed.addAll(VertexRoleMap.mouthCorner);
    }
    return allowed;
  }

  static void applyToGrid({
    required Map<String, double> parameters,
    required ConstrainedVertexField vertexField,
    required TriMesh mesh,
    required Size imageSize,
    required Float32List displacement,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required double fse,
    double maxOverlapRatio = 0.45,
  }) {
    if (!hasActiveLateralTool(parameters)) {
      return;
    }

    final sourceIndices = vacancySourceIndices(parameters);
    if (sourceIndices.isEmpty) {
      return;
    }

    final faceSlimOnly = isFaceSlimOnly(parameters);
    final radiusPx = faceSlimOnly
        ? (fse * 0.11).clamp(10.0, 72.0)
        : (fse * 0.075).clamp(6.0, 48.0);
    final radiusSq = radiusPx * radiusPx;
    const minVertexMovePx = 1.25;

    for (var i = 0; i < vertexField.landmarkCount; i++) {
      if (!sourceIndices.contains(i)) {
        continue;
      }

      final delta = vertexField.displacementAt(i);
      final moveMag = delta.distance;
      if (moveMag < minVertexMovePx) {
        continue;
      }

      final base = FaceWarpUtils.vertexAt(mesh, i);
      if (base == null) {
        continue;
      }

      // Remap liquify usa -Δv; na posição original preenchemos o buraco.
      final fillDx = -delta.dx;
      final fillDy = -delta.dy;
      final fillMag = math.sqrt(fillDx * fillDx + fillDy * fillDy);
      if (fillMag <= 1e-6) {
        continue;
      }

      for (var gy = 0; gy < gridHeight; gy++) {
        for (var gx = 0; gx < gridWidth; gx++) {
          final idx = gy * gridWidth + gx;
          if (mask[idx] <= 0.001) {
            continue;
          }

          final px = (gx / (gridWidth - 1)) * imageSize.width;
          final py = (gy / (gridHeight - 1)) * imageSize.height;
          final dx = px - base.dx;
          final dy = py - base.dy;
          if (dx * dx + dy * dy > radiusSq) {
            continue;
          }

          final curDx = displacement[idx * 2];
          final curDy = displacement[idx * 2 + 1];
          final curMag = math.sqrt(curDx * curDx + curDy * curDy);
          if (curMag > fillMag * maxOverlapRatio) {
            continue;
          }

          final dist = math.sqrt(dx * dx + dy * dy);
          final t = (1 - dist / radiusPx).clamp(0.0, 1.0);
          final w = t * t;
          displacement[idx * 2] = fillDx * w;
          displacement[idx * 2 + 1] = fillDy * w;
        }
      }
    }
  }

  /// Raio proporcional ao pico de sliders laterais ativos.
  static double radiusScaleFor(Map<String, double> parameters) {
    var peak = 0.0;
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      if (!lateralToolKeys.contains(key)) {
        continue;
      }
      peak = math.max(peak, parameters[key] ?? 0);
    }
    return peak.clamp(0.0, 1.0);
  }
}
