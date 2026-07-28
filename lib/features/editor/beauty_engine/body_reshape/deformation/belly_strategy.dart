import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Reduz a barriga (banda baixa do torso) em direção ao eixo medial.
class BellyStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const BellyStrategy({this.maxShiftFraction = 0.05});

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.bellyReduce,
      };

  @override
  void apply({
    required RegionDeformationContext context,
    required Float32List deltas,
  }) {
    final intensity = context.intensity;
    if (intensity <= 0) {
      return;
    }

    final leftShoulder = context.landmarkPx(BodyJoint.leftShoulder);
    final rightShoulder = context.landmarkPx(BodyJoint.rightShoulder);
    final leftHip = context.landmarkPx(BodyJoint.leftHip);
    final rightHip = context.landmarkPx(BodyJoint.rightHip);
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return;
    }

    final topMid = Offset(
      (leftShoulder.dx + rightShoulder.dx) * 0.5,
      (leftShoulder.dy + rightShoulder.dy) * 0.5,
    );
    final bottomMid = Offset(
      (leftHip.dx + rightHip.dx) * 0.5,
      (leftHip.dy + rightHip.dy) * 0.5,
    );
    final span = math.max(bottomMid.dy - topMid.dy, 1.0);
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final halfWidth = context.imageSize.width * 0.2;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.waist => 1.0,
        BodyRegion.torso => 0.7,
        BodyRegion.hip => 0.35,
        BodyRegion.chest => 0.1,
        _ => context.regionMatches(region) ? 0.4 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final t = ((point.dy - topMid.dy) / span).clamp(0.0, 1.0);
      // Pico na barriga (~0.55–0.85 ombro→quadril).
      final centered = ((t - 0.7) / 0.18).abs();
      final profile = centered >= 1 ? 0.1 : (0.3 + 0.7 * (1 - centered * centered));
      final axisFalloff = falloffAlongAxis(
        point: point,
        a: topMid,
        b: bottomMid,
        halfWidth: halfWidth,
      );
      if (axisFalloff <= 0 || profile <= 0) {
        continue;
      }

      final inward = inwardNormalTowardAxis(
        point: point,
        a: topMid,
        b: bottomMid,
      );
      if (inward == Offset.zero) {
        continue;
      }

      final w = regionWeight *
          profile *
          axisFalloff *
          mesh.weights[i].clamp(0.0, 1.0);
      accumulateDelta(
        deltas,
        i,
        inward.dx * shiftPx,
        inward.dy * shiftPx,
        w,
      );
    }
  }
}
