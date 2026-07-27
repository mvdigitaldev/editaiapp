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

    final a = BodyWarpUtils.vertexAt(context.mesh, 11);
    final b = BodyWarpUtils.vertexAt(context.mesh, 12);
    if (a == null || b == null) {
      return BodyWarpUtils.anchorPoints(context.mesh);
    }

    final imageLeft = a.dx <= b.dx ? a : b;
    final imageRight = a.dx <= b.dx ? b : a;
    final shift = context.imageSize.width * 0.04 * intensity;

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {11, 12},
      ),
      ControlPoint(
        source: imageLeft,
        target: Offset(imageLeft.dx - shift, imageLeft.dy),
      ),
      ControlPoint(
        source: imageRight,
        target: Offset(imageRight.dx + shift, imageRight.dy),
      ),
    ];
  }
}
