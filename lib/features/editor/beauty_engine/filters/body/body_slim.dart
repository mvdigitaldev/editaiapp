import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Emagrece torso globalmente.
class BodySlimFilter extends BodyWarpFilter {
  BodySlimFilter();

  @override
  String get id => 'body_slim';

  @override
  String get parameterKey => 'body_slim';

  @override
  List<String> get affectedRegions => ['torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.06 * intensity;

    for (final region in [MeshRegion.torso, MeshRegion.waist]) {
      for (final index in BodyWarpUtils.regionIndices(region)) {
        final source = BodyWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardCenter = context.centerX - source.dx;
        points.add(
          ControlPoint(
            source: source,
            target: Offset(
              source.dx + towardCenter.sign * maxShift * 0.85,
              source.dy,
            ),
          ),
        );
      }
    }

    return points;
  }
}
