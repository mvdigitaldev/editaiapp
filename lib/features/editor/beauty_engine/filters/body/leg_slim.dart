import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita coxas e panturrilhas.
class LegSlimFilter extends BodyWarpFilter {
  LegSlimFilter();

  @override
  String get id => 'leg_slim';

  @override
  String get parameterKey => 'leg_slim';

  @override
  List<String> get affectedRegions => ['left_leg', 'right_leg'];

  @override
  Set<int> get requiredPoseIndices => {25, 26, 27, 28};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0 || context.pose.isPartial) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.04 * intensity;

    for (final region in [MeshRegion.leftLeg, MeshRegion.rightLeg]) {
      for (final index in BodyWarpUtils.regionIndices(region)) {
        if (index == 23 || index == 24) {
          continue;
        }
        final source = BodyWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardAxis = context.centerX - source.dx;
        points.add(
          ControlPoint(
            source: source,
            target: Offset(
              source.dx + towardAxis.sign * maxShift * 0.7,
              source.dy,
            ),
          ),
        );
      }
    }

    return points;
  }
}
