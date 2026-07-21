import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Eleva ou abaixa nariz inteiro.
class NoseHeightFilter extends FaceWarpFilter {
  NoseHeightFilter();

  @override
  String get id => 'nose_height';

  @override
  String get parameterKey => 'nose_height';

  @override
  List<String> get affectedRegions => ['nose'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final shiftY = -context.imageSize.height * 0.025 * intensity;

    for (final index in FaceWarpUtils.regionIndices(MeshRegion.nose)) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy + shiftY),
        ),
      );
    }

    return points;
  }
}
