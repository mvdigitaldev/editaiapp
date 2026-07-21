import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Reduz altura da testa — exclui hairline (Sprint 15).
class ForeheadFilter extends FaceWarpFilter {
  ForeheadFilter();

  @override
  String get id => 'forehead';

  @override
  String get parameterKey => 'forehead';

  @override
  List<String> get affectedRegions => ['forehead'];

  /// Hairline — não warpar (máscara superior).
  static const hairlineLandmarkIndices = {9, 10, 151, 337, 338};

  /// Região média/baixa da testa (abaixo da hairline).
  static const _foreheadLower = {297, 332, 109, 67, 103, 54, 21};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final lift = context.imageSize.height * 0.022 * intensity;

    for (final index in _foreheadLower) {
      if (hairlineLandmarkIndices.contains(index)) {
        continue;
      }
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy - lift),
        ),
      );
    }

    return points;
  }
}
