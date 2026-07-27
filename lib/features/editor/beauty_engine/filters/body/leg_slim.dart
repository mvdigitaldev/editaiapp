import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita coxas e panturrilhas ao longo do eixo da perna.
class LegSlimFilter extends BodyWarpFilter {
  LegSlimFilter();

  @override
  String get id => 'leg_slim';

  @override
  String get parameterKey => 'leg_slim';

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

    final t = intensity * intensity * (3 - 2 * intensity);
    final halfWidth = context.imageSize.width * 0.055;
    final shiftFraction = 0.5 * t;

    final movable = <ControlPoint>[];

    // Perna esquerda: quadril(23) → joelho(25) → tornozelo(27)
    final lHip = BodyWarpUtils.vertexAt(context.mesh, 23);
    final lKnee = BodyWarpUtils.vertexAt(context.mesh, 25);
    final lAnkle = BodyWarpUtils.vertexAt(context.mesh, 27);
    if (lHip != null && lKnee != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: lHip,
          distal: lKnee,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth,
          shiftFraction: shiftFraction,
          freezeProximal: true,
          samples: 6,
        ),
      );
    }
    if (lKnee != null && lAnkle != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: lKnee,
          distal: lAnkle,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth * 0.75,
          shiftFraction: shiftFraction,
          freezeProximal: true,
          samples: 5,
        ),
      );
    }

    // Perna direita: 24 → 26 → 28
    final rHip = BodyWarpUtils.vertexAt(context.mesh, 24);
    final rKnee = BodyWarpUtils.vertexAt(context.mesh, 26);
    final rAnkle = BodyWarpUtils.vertexAt(context.mesh, 28);
    if (rHip != null && rKnee != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: rHip,
          distal: rKnee,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth,
          shiftFraction: shiftFraction,
          freezeProximal: true,
          samples: 6,
        ),
      );
    }
    if (rKnee != null && rAnkle != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: rKnee,
          distal: rAnkle,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth * 0.75,
          shiftFraction: shiftFraction,
          freezeProximal: true,
          samples: 5,
        ),
      );
    }

    if (movable.isEmpty) {
      return const [];
    }

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {25, 26, 27, 28},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: context.imageSize,
        ringScale: 1.65,
      ),
    ];
  }
}
