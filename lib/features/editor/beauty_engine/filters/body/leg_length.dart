import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Alonga pernas a partir do quadril (clamp no frame).
class LegLengthFilter extends BodyWarpFilter {
  LegLengthFilter();

  @override
  String get id => 'leg_length';

  @override
  String get parameterKey => 'leg_length';

  @override
  List<String> get affectedRegions => ['left_leg', 'right_leg'];

  @override
  Set<int> get requiredPoseIndices => {23, 24, 25, 26, 27, 28};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0 || context.pose.isPartial) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final stretch = context.imageSize.height * 0.06 * intensity;
    final maxY = context.imageSize.height * 0.97;

    for (final index in [25, 26, 27, 28]) {
      final source = BodyWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final targetY = (source.dy + stretch).clamp(source.dy, maxY);
      points.add(
        ControlPoint(
          source: source,
          target: BodyWarpUtils.clampToFrame(
            Offset(source.dx, targetY),
            context.imageSize,
          ),
        ),
      );
    }

    return points;
  }
}
