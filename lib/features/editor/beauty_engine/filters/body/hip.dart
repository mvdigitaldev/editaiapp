import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Ajusta largura do quadril (landmarks 23/24 + borda estimada).
class HipFilter extends BodyWarpFilter {
  HipFilter();

  @override
  String get id => 'hip';

  @override
  String get parameterKey => 'hip';

  @override
  List<String> get affectedRegions => ['waist'];

  @override
  Set<int> get requiredPoseIndices => {23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final t = intensity * intensity * (3 - 2 * intensity);
    final left = BodyWarpUtils.vertexAt(context.mesh, 23);
    final right = BodyWarpUtils.vertexAt(context.mesh, 24);
    if (left == null || right == null) {
      return const [];
    }

    final shift = context.imageSize.width * 0.04 * t;
    final pad = context.imageSize.width * 0.03;
    final movable = <ControlPoint>[
      ControlPoint(
        source: BodyWarpUtils.clampToFrame(
          Offset(left.dx - pad, left.dy),
          context.imageSize,
        ),
        target: BodyWarpUtils.clampToFrame(
          Offset(left.dx - pad - shift, left.dy),
          context.imageSize,
        ),
      ),
      ControlPoint(
        source: BodyWarpUtils.clampToFrame(
          Offset(right.dx + pad, right.dy),
          context.imageSize,
        ),
        target: BodyWarpUtils.clampToFrame(
          Offset(right.dx + pad + shift, right.dy),
          context.imageSize,
        ),
      ),
      // Âncora no meio do quadril.
      ControlPoint(
        source: Offset((left.dx + right.dx) * 0.5, left.dy),
        target: Offset((left.dx + right.dx) * 0.5, left.dy),
      ),
    ];

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {23, 24},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: context.imageSize,
      ),
    ];
  }
}
