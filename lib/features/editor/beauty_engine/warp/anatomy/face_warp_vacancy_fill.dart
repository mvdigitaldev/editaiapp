import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/face/face_warp_utils.dart';
import '../../models/tri_mesh.dart';
import 'constrained_vertex_field.dart';

/// Preenche regiões “vazias” após warps laterais (olhos/boca afastam).
///
/// Liquify backward deixa pixels na posição original sem Δv → fantasma.
/// Propaga o Δv inverso ao redor da posição **original** de cada vértice movido.
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

  static bool hasActiveLateralTool(Map<String, double> parameters) {
    for (final key in lateralToolKeys) {
      if ((parameters[key] ?? 0) > 1e-6) {
        return true;
      }
    }
    return false;
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
  }) {
    if (!hasActiveLateralTool(parameters)) {
      return;
    }

    final radiusPx = (fse * 0.075).clamp(6.0, 48.0);
    final radiusSq = radiusPx * radiusPx;
    const minVertexMovePx = 1.25;

    for (var i = 0; i < vertexField.landmarkCount; i++) {
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
          if (curMag > fillMag * 0.45) {
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
