import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Ajusta largura dos ombros.
class ShoulderWidthFilter extends BodyWarpFilter {
  ShoulderWidthFilter();

  @override
  String get id => 'shoulder_width';

  @override
  String get parameterKey => 'shoulder_width';

  @override
  List<String> get affectedRegions => ['torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final shift = context.imageSize.width * 0.04 * intensity;

    final left = BodyWarpUtils.vertexAt(context.mesh, 11);
    if (left != null) {
      points.add(
        ControlPoint(
          source: left,
          target: Offset(left.dx - shift, left.dy),
        ),
      );
    }

    final right = BodyWarpUtils.vertexAt(context.mesh, 12);
    if (right != null) {
      points.add(
        ControlPoint(
          source: right,
          target: Offset(right.dx + shift, right.dy),
        ),
      );
    }

    return points;
  }
}
