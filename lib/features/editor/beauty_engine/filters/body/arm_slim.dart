import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita braços ao longo do eixo do osso (silhueta → eixo).
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

    // Suaviza extremos — evita over-slim que rasga textura.
    final t = intensity * intensity * (3 - 2 * intensity); // smoothstep
    final halfWidth = context.imageSize.width * 0.045;
    final shiftFraction = 0.55 * t;

    final movable = <ControlPoint>[];

    // Braço esquerdo: ombro(11) → cotovelo(13) → punho(15)
    final lShoulder = BodyWarpUtils.vertexAt(context.mesh, 11);
    final lElbow = BodyWarpUtils.vertexAt(context.mesh, 13);
    final lWrist = BodyWarpUtils.vertexAt(context.mesh, 15);
    if (lShoulder != null && lElbow != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: lShoulder,
          distal: lElbow,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth,
          shiftFraction: shiftFraction,
          freezeProximal: true,
        ),
      );
    }
    if (lElbow != null && lWrist != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: lElbow,
          distal: lWrist,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth * 0.85,
          shiftFraction: shiftFraction,
          freezeProximal: true,
        ),
      );
    }

    // Braço direito: 12 → 14 → 16
    final rShoulder = BodyWarpUtils.vertexAt(context.mesh, 12);
    final rElbow = BodyWarpUtils.vertexAt(context.mesh, 14);
    final rWrist = BodyWarpUtils.vertexAt(context.mesh, 16);
    if (rShoulder != null && rElbow != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: rShoulder,
          distal: rElbow,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth,
          shiftFraction: shiftFraction,
          freezeProximal: true,
        ),
      );
    }
    if (rElbow != null && rWrist != null) {
      movable.addAll(
        BodyWarpUtils.slimBoneSegment(
          proximal: rElbow,
          distal: rWrist,
          imageSize: context.imageSize,
          limbHalfWidth: halfWidth * 0.85,
          shiftFraction: shiftFraction,
          freezeProximal: true,
        ),
      );
    }

    if (movable.isEmpty) {
      return const [];
    }

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {13, 14, 15, 16},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: context.imageSize,
      ),
    ];
  }
}
