import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita cintura (silhueta lateral → centro, mais forte no meio).
class WaistSlimFilter extends BodyWarpFilter {
  WaistSlimFilter();

  @override
  String get id => 'waist_slim';

  @override
  String get parameterKey => 'waist_slim';

  @override
  List<String> get affectedRegions => ['waist', 'torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final t = intensity * intensity * (3 - 2 * intensity);
    final leftTop = BodyWarpUtils.vertexAt(context.mesh, 11);
    final rightTop = BodyWarpUtils.vertexAt(context.mesh, 12);
    final leftBottom = BodyWarpUtils.vertexAt(context.mesh, 23);
    final rightBottom = BodyWarpUtils.vertexAt(context.mesh, 24);
    if (leftTop == null ||
        rightTop == null ||
        leftBottom == null ||
        rightBottom == null) {
      return const [];
    }

    final shiftPx = context.imageSize.width * 0.07 * t;
    final movable = BodyWarpUtils.slimTorsoSides(
      leftTop: leftTop,
      rightTop: rightTop,
      leftBottom: leftBottom,
      rightBottom: rightBottom,
      imageSize: context.imageSize,
      shiftPx: shiftPx,
      samples: 7,
    );

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {11, 12, 23, 24},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: context.imageSize,
        ringScale: 1.75,
      ),
    ];
  }
}
