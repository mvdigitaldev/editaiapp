import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita braços (ombro → punho).
class ArmSlimFilter extends BodyWarpFilter {
  ArmSlimFilter();

  @override
  String get id => 'arm_slim';

  @override
  String get parameterKey => 'arm_slim';

  @override
  List<String> get affectedRegions => ['left_arm', 'right_arm'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 13, 14, 15, 16};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.035 * intensity;

    for (final region in [MeshRegion.leftArm, MeshRegion.rightArm]) {
      for (final index in BodyWarpUtils.regionIndices(region)) {
        if (index == 11 || index == 12) {
          continue;
        }
        final source = BodyWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final shoulderX = index <= 15
            ? BodyWarpUtils.vertexAt(context.mesh, 11)?.dx ?? context.centerX
            : BodyWarpUtils.vertexAt(context.mesh, 12)?.dx ?? context.centerX;
        final towardShoulder = shoulderX - source.dx;
        points.add(
          ControlPoint(
            source: source,
            target: Offset(
              source.dx + towardShoulder.sign * maxShift,
              source.dy,
            ),
          ),
        );
      }
    }

    return points;
  }
}
